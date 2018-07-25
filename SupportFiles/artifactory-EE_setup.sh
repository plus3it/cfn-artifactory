#!/bin/bash
# shellcheck disable=SC2015,SC2155,SC2046
#
# Script to:
# * Ready a watchmaker-hardened EL7 OS for installation of the
#   Artifactory Enterprise Edition software
# * Install and configure Artifactory using parm/vals kept in
#   an "environment" file
#
#################################################################
PROGNAME=$(basename "${0}")
# shellcheck disable=SC1091
source /etc/cfn/Artifactory.envs
TOOL_BUCKET="${ARTIFACTORY_TOOL_BUCKET}"
NFSSVR="${ARTIFACTORY_CLUSTER_HOME}"
AFSAHOME="${ARTIFACTORY_APP_HOME}"
AFCLHOME="${AFSAHOME}-cluster"
AFPORTS=(
      8081/tcp
      10001/tcp
      10001/udp
   )
FWSVCS=(
      http
      https
      artifactory
   )
RPMDEPLST=(
      autofs
      nfs-utils
      postgresql-jdbc
   )
NGINXRPM="nginx"
SVCALIASES=(${ARTIFACTORY_PROXY_AKAS//,/ })
MEMALLOC="$(awk '/^MemFree/{ printf("%d\n", ($2 * 0.80)/1024) }' /proc/meminfo)"


##
## Set up an error logging and exit-state
function err_exit {
   local ERRSTR="${1}"
   local SCRIPTEXIT=${2:-1}

   # Our output channels
   echo "${ERRSTR}" > /dev/stderr
   logger -t "${PROGNAME}" -p kern.crit "${ERRSTR}"

   # Need our exit to be an integer
   if [[ ${SCRIPTEXIT} =~ ^[0-9]+$ ]]
   then
      exit "${SCRIPTEXIT}"
   else
      exit 1
   fi
}

##
## Configure firewalld
function FirewalldSetup {

   ##
   ## Create custom firewalld service

   # Establish service name
   printf "Creating firewalld service for Artifactory... "
   firewall-cmd --permanent --new-service=artifactory || \
     err_exit 'Failed to initialize artifactory firewalld service'

   # Provide short description for service
   printf "Setting short description for Artifactory firewalld service... "
   firewall-cmd --permanent --service=artifactory \
     --set-short="Artifactory Service Ports" || \
     err_exit 'Failed to add short service description'

   # Provide long description for service
   printf "Setting long description for Artifactory firewalld service... "
   firewall-cmd --permanent --service=artifactory \
     --set-description="Firewalld options supporting Artifactory deployments" || \
     err_exit 'Failed to add long service description'

   # Define ports within service
   for SVCPORT in "${AFPORTS[@]}"
   do
      printf "Adding port %s to Artifactory's firewalld service-definition... " \
        "${SVCPORT}"
      firewall-cmd --permanent --service=artifactory \
      --add-port="${SVCPORT}" || \
        err_exit "Failed to add firewalld exception for ${SVCPORT}/tcp"
   done

   # Restart firewalld to ensure permanent files get read
   if [[ $(systemctl is-active firewalld) == active ]]
   then
      systemctl restart firewalld
   fi

   ##
   ## Activate needed firewalld services

   for FWSVC in "${FWSVCS[@]}"
   do
      printf "Adding service exception(s) for %s... " "${FWSVC}"
      firewall-cmd --add-service="${FWSVC}" --permanent || \
         echo "Failed adding service exception(s) for ${FWSVC}"
   done

   printf "Reloading firewalld (to activate new rules)... "
   firewall-cmd --reload && echo "Success!" || \
      echo "Failed to re-read firewalld rules."

}

##
## Install any missing RPMs
function InstMissingRPM {
   local INSTRPMS=()

   # Check if we're missing any vendor-enumerated RPMs
   for RPM in "${RPMDEPLST[@]}"
   do
      printf "Cheking for presence of %s... " "${RPM}"
      if [[ $(rpm --quiet -q "$RPM")$? -eq 0 ]]
      then
         echo "Already installed."
      else
         echo "Selecting for install"
         INSTRPMS+=(${RPM})
      fi
   done

   # Install any missing vendor-enumerated RPMs
   if [[ ${#INSTRPMS[@]} -ne 0 ]]
   then
      echo "Will attempt to install the following RPMS: ${INSTRPMS[*]}"
      yum install -y "${INSTRPMS[@]}" || \
         err_exit "Install of RPM-dependencies experienced failures"
   else
      echo "No RPM-dependencies to satisfy"
   fi
}

##
## Disable FIPS mode
function DisableFips {

   if [[ -x $(which wam) ]]
   then
      salt-call --local ash.fips_disable
   else
      printf "Removing FIPS kernel RPMs... "
      yum -q remove -y dracut-fips\* &&
         echo "Success!" || err_exit 'Failed to remove FIPS kernel RPMs'

      printf "Moving FIPSed initrafmfs aside... "
      mv -v /boot/initramfs-"$(uname -r)".img{,.FIPS-bak} &&
         echo "Success!" || err_exit 'Failed to move FIPSed initrafmfs aside'

      echo "Generating de-FIPSed initramfs"
      dracut -v || err_exit 'Error encountered during regeeration of initramfs'

      echo "Removing 'fips' kernel arguments from GRUB config"
      grubby --update-kernel=ALL --remove-args=fips=1
      [[ -f /etc/default/grub ]] && sed -i 's/ fips=1//' /etc/default/grub

      # Log a warning about FIPS
      echo "System must be rebooted for FIPS-disable to take full effect"
   fi
}

##
## Shared cluster-config
function SharedClusterHomeFsSetup {


   # Add Artifactory CLUSTER_HOME to fstab
   if [[ $( grep -q "${NFSSVR}" /etc/fstab )$? -eq 0 ]]
   then
      echo "Artifactory CLUSTER_HOME already in fstab"
   else
      printf "Adding Artifactory CLUSTER_HOME to fstab... "
      printf "%s:/\t%s\tnfs4\tdefaults\t0 0" "${NFSSVR}" "${AFCLHOME}" \
        >> /etc/fstab && echo Success || \
          err_exit "Failed adding Artifactory CLUSTER_HOME to fstab"
   fi

   # Mount shared CLUSTER_HOME
   printf "Mounting %s... " "${AFCLHOME}"
   mount -a nfs && echo "Success" || err_exit "Failed mounting ${AFCLHOME}"
}

function SharedClusterHomeAppSetup {
  # Add shared config-directives to ha-node file
  printf "Adding NFS-hosted shared-config location to ha-node.properties file...\n\t"
  (
    echo "artifactory.ha.data.dir=${AFSAHOME}-cluster/data"
    echo "artifactory.ha.backup.dir=${AFSAHOME}-cluster/backup"
   ) >> "${AFSAHOME}/etc/ha-node.properties" && echo "Success" || \
     err_exit "Failed to add shared-config location to HA node's properties"
}

##
## Un-shared cluster-config
function UnSharedClusterHomeFsSetup {

   VGNAME="$( vgs --noheadings -o vg_name | sed 's/ //g' )"

   printf "Creating volume for Artifactory data... "
   lvcreate -l 100%FREE -n cluDataDir "${VGNAME}" && echo "Success" || \
     err_exit "Failed creating volume for Artifactory data"

   printf "Creating filesystem on %s... " "/dev/${VGNAME}/cluDataDir"
   mkfs -t ext4 "/dev/${VGNAME}/cluDataDir" && echo "Success" || \
     err_exit "Failed while creating filesystem /dev/${VGNAME}/cluDataDir"

   # Add Artifactory CLUSTER_HOME to fstab
   if [[ $( grep -q "/dev/${VGNAME}/cluDataDir" /etc/fstab )$? -eq 0 ]]
   then
      echo "Artifactory CLUSTER_HOME already in fstab"
   else
      printf "Adding Artifactory CLUSTER_HOME to fstab... "
      printf "%s\t%s\text4\tdefaults\t0 0\n" "/dev/${VGNAME}/cluDataDir" "${AFCLHOME}" \
        >> /etc/fstab && echo Success || \
          err_exit "Failed adding Artifactory CLUSTER_HOME to fstab"
   fi

   # Mount un-shared CLUSTER_HOME
   printf "Mounting %s... " "${AFCLHOME}"
   mount -a "${AFCLHOME}" && echo "Success" || \
     err_exit "Failed mounting ${AFCLHOME}"
}

##
## Tweak SEL as necessary
function SelMods {
   printf "Ensure httpd processes can use network... "
   setsebool -P httpd_can_network_connect 1 && echo "Success" || \
     err_exit "Failed setting httpd network boolean"

   if [ ! "${1}" = "" ]
   then
      printf "Allow processes running httpd context to use NFS... "
      setsebool -P httpd_use_nfs 1 && echo "Success" || \
        err_exit "Failed setting httpd/NFS SEL-boolean"

      printf "Alow httpd rw access to %s... " "${1}"
      semanage fcontext -a -t "httpd_sys_rw_content_t" "${1}(/.*)?" && \
        echo "Success" || err_exit "Unable to give httpd rw access to ${1}"
   fi
}

##
## Set up NGINX-based reverse-proxy service
function ReverseProxy {
   # Install Nginx
   printf "Install Nginx service... "
   yum --enablerepo="*epel" install -y "${NGINXRPM}" && \
     echo "Success." || \
     err_exit 'Nginx installation failed'
   local NGINXDIR=$(
         dirname $(rpm -ql "${NGINXRPM}" | grep -E 'nginx.conf$')
      )

   local PROXTMPL="/etc/cfn/files/AFproxy.conf.tmpl" 
   local PROXCONF="${NGINXDIR}/conf.d/AFproxy.conf"

   if [[ ! -z ${PROXTMPL} ]]
   then

      # Create proxy config from template
      printf "Installing templated nginx proxy-config... "
      install -b -m 000644 -o root -g root "${PROXTMPL}" "${PROXCONF}" && \
        echo "Success" || \
          err_exit "Failed installing templated nginx proxy-config" 

      # Fix SEL labels as necessary
      if [[ $(getenforce) != Disabled ]]
      then
         chcon --reference="${NGINXDIR}"/nginx.conf "${PROXCONF}"
      fi

      printf "Localizing proxy-config... "
      SVCALIASES+=($(curl http://169.254.169.254/latest/meta-data/local-hostname/))
      SVCALIASES+=($(curl http://169.254.169.254/latest/meta-data/local-ipv4/))
      for ALIAS in "${SVCALIASES[@]}"
      do
         SVCALIASES+=('~(?<repo>.+)\.'${ALIAS})
      done

      sed -i '{
         s/__AF-FQDN__/'"$(hostname -f)"'/g
         /^[    ]*server_name/s/;$/ '"${SVCALIASES[*]}"';/
      }' "${PROXCONF}" && \
        echo "Success" || \
          err_exit "Failed to update config's alias-list"


      printf "Setting max proxy size to %sMiB... " "${MEMALLOC}"
      sed -i '{
        s/__AF_CLIENT_MAX__/'"${MEMALLOC}"'m/g
      }' "${PROXCONF}" && \
        echo "Success" || \
          err_exit "Failed to update config's max proxy size"

      printf "Update *_temp_path parm-vals... "
      sed -i '{
        s#__AF_CLUSTER_HOME__#'"${AFCLHOME}"'#g
      }' "${PROXCONF}" && \
        echo "Success" || \
          err_exit "Failed to update config's *_temp_path parm-vals"

   fi

   CURBUCKTHASH=$(nginx -T 2>&1 | grep 'server_names_hash_bucket_size' | \
                  sed 's/^.*: //')

   # Adjust
   if [[ -z ${CURBUCKTHASH+xxx} ]] || [ "${CURBUCKTHASH}" = "" ]
   then
      printf "No 'server_names_hash_bucket_size' error detected:\n"
      printf "\tserver config should be ok as is.\n"
   else
      echo "Doubling currently-defined 'server_names_hash_bucket_size' size."
      NEWHASH=$((CURBUCKTHASH * 2))
      sed -i '/^http /a server_names_hash_bucket_size '"${NEWHASH}"';' \
        "${NGINXDIR}"/nginx.conf
   fi

   # Lasso SELinux as necessary
   if [[ $(getenforce) = Disabled ]]
   then
      "SELinux not enabled: no need to tweak"
   else
      # Check for proxy-temp dirs to except
      if [[ $(grep -q proxy_temp_path "${PROXCONF}" )$? -eq 0 ]]
      then
         local PROXTMPDIR=$(
             awk '/proxy_temp_path/{ print $2 }' "${PROXCONF}" | \
               sed -e 's/;$//' -e 's/\/$//'
            )
      fi

      # Call routine to tweak SEL config
      SelMods "${PROXTMPDIR}"
   fi

   # Enable and start Nginx
   systemctl enable nginx
   systemctl start nginx
}


########################################
## Main Program Flow
########################################

# Update firewalld rules (adjusting SELinux as necessary)
GETSELSTATE=$(getenforce)
if [[ ${GETSELSTATE} = Enforcing ]]
then
   setenforce Permissive || echo "Couldn't dial-back SELinux"
   FirewalldSetup
   setenforce "${GETSELSTATE}" || echo "Couldn't reset SELinux"
else
   FirewalldSetup
fi

# Install additional RPMS to support installation requirements
InstMissingRPM

# Ensure Artifactory CLUSTER_HOME directory exists
if [[ ! -d ${AFCLHOME} ]]
then
  (
    umask 022
    printf "Creating %s... " "${AFCLHOME}"
    install -d -m 000755 "${AFCLHOME}"
   )
fi

# Check if using shared cluster-home
if [[ -z ${NFSSVR+x} ]] || [[ ${NFSSVR} = '' ]]
then
   echo "Not using shared cluster-home"

   # Call routines to configure for un-shared cluster-config
   UnSharedClusterHomeFsSetup
else
   echo "Using shared cluster-home"

   # Call routines to configure for NFS-shared cluster-config
   SharedClusterHomeFsSetup
fi

# Download license files
printf "Downloading license files... "
aws s3 sync "s3://${TOOL_BUCKET}/Licenses/" /etc/cfn/files/ && \
  echo "Success" || err_exit "Failed downloading license files"

# Install the Artifactory RPM
if [[ $( rpm -q --quiet "${ARTIFACTORY_RPM_NAME}" )$? -eq 0 ]]
then
   echo "Artifactory RPM already installed"
else
   printf "Installing %s... " "${ARTIFACTORY_RPM_NAME}"
   yum install -y "${ARTIFACTORY_RPM_NAME}" && echo "Success" || \
     err_exit "Failed to install ${ARTIFACTORY_RPM_NAME}"
fi

# Good news/bad news:
# * Artifactory 6.x now comes with systemd unit-files
# * Artifactory's systemd unit-files need massaging...
if [[ $( grep -q START_TMO /usr/lib/systemd/system/artifactory.service )$? -eq 0 ]]
then
   echo "Delayed starte-timeout already present"
else
   printf "Slackening systemd's start-timeout... "
   sed -i '/\[Service]/s/$/\nEnvironment=START_TMO=120/' \
     /usr/lib/systemd/system/artifactory.service && echo "Success" || \
       err_exit "Failed to update systemd unit file"

   printf "Reloading systemd service definitions... "
   systemctl daemon-reload && echo "Success" || echo "Failed"
fi


# Staging license files - only critical on first node but easier to
# just do "everywhere": Artifactory ignores redundant license files
printf "Staging license files... "
install -b -m 000644 -o artifactory -g artifactory \
  <( cat /etc/cfn/files/ArtifactoryEE_* ) "${AFSAHOME}/etc/artifactory.lic" && \
  echo "Success" || err_exit "Failed staging license files"

# Install pre-staged database connector definition
printf "Setting up DB connection... "
install -b -m 000644 -o artifactory -g artifactory \
  /etc/cfn/files/db.properties "${AFSAHOME}/etc/db.properties" \
    && echo "Success" || err_exit "Failed configuring DB connection"

# Ensure Tomcat can find JDBC library
printf "Ensure Tomcat can find JDBC connector... "
ln -s "$( rpm -ql postgresql-jdbc | grep jdbc.jar )" \
  "${AFSAHOME}/tomcat/lib" && echo "Success" ||  \
    err_exit "Failed linking JDBC lib"

# Cluster-comms require a secure directory to store authorization key
if [[ -d ${AFSAHOME}/etc/security ]]
then
   echo "Security-key directory already exists"
else
   printf "Ensure security-key directory exists... "
   install -d -m 0750 -o artifactory -g artifactory \
     "${AFSAHOME}/etc/security" && echo "Success" || \
       err_exit "Failed creating security-key directory"

   # Fix SEL label
   chcon --reference "${AFSAHOME}/etc" "${AFSAHOME}/etc/security"
fi

# Cluster-commes require a pre-shared authorization-key to
# enforce cluster membership
printf "Installing cluster-key file... "
install -b -m 000640 -o artifactory -g artifactory \
  <( awk -F= '/CLUSTER_KEY/{print $2}' /etc/cfn/Artifactory.envs ) \
  "${AFSAHOME}/etc/security/master.key" && \
    echo "Success" || err_exit "Failed to install pre-shared cluster-key"

# Create/install HA node's properties file
printf "Configuring cluster node's properties... "
install -b -m 000644 -o artifactory -g artifactory <(
  echo "node.id=$(hostname -s)"
  echo "context.url=http://$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$#:8081/artifactory#' )"
  echo "membership.port=10001"
  echo "primary=true"
  echo "hazelcast.interface=$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$##' )"
 ) "${AFSAHOME}/etc/ha-node.properties" && echo "Success" || \
  err_exit "Failed to set up HA node's properties"

if [[ -z ${NFSSVR+x} ]] || [[ ${NFSSVR} = '' ]]
then
   echo "No extra ha-node.properties settings to add"

else
   echo "Adding NFS-related settings to ha-node.properties file"
   SharedClusterHomeAppSetup
fi

# Preserve existing binarystore.xml file
if [[ -e ${AFSAHOME}/etc/binarystore.xml ]]
then
   printf "Preserving %s... " "${AFSAHOME}/etc/binarystore.xml"
   mv "${AFSAHOME}/etc/binarystore.xml" \
     "${AFSAHOME}/etc/binarystore.xml-BAK-$(date '+%Y%m%d%H%M')" && \
       echo "Success" || echo "Couldn't preserve prior-file"
fi

# Install tiering binarystore.xml file
printf "Installing %s..." "${AFSAHOME}/etc/binarystore.xml"
install -b -m 000644 -o artifactory -g artifactory \
  /etc/cfn/files/binarystore.xml "${AFSAHOME}/etc" && echo "Success" || \
    err_exit "Failed to install ${AFSAHOME}/etc/binarystore.xml"

# Ensure cluster's storage-dirs all exist
for CLUDIR in ${AFSAHOME}-cluster/{backup,data,cache}
do
  if [[ -d ${CLUDIR} ]]
  then
     echo "${CLUDIR} already exists"
  else
     printf "Attempting to create %s... " "${CLUDIR}"
     install -d -m 0750 -o artifactory -g artifactory "${CLUDIR}" && \
       echo "Success" || err_exit "Failed creating ${CLUDIR}"
  fi
done

# Configure NGINX-based reverse-proxy
ReverseProxy

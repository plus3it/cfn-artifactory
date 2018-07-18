#!/bin/bash
# shellcheck disable=SC2015
#
# Script to:
# * Ready a watchmaker-hardened EL7 OS for installation of the
#   Artifactory Enterprise Edition software
# * Install and configure Artifactory using parm/vals kept in 
#   an "environment" file
#
#################################################################
PROGNAME=$(basename "${0}")
CHKFIPS=/proc/sys/crypto/fips_enabled
# shellcheck disable=SC1091
source /etc/cfn/Artifactory.envs
TOOL_BUCKET="${ARTIFACTORY_TOOL_BUCKET}"
NFSSVR="${ARTIFACTORY_CLUSTER_HOME}"
AFSAHOME="${ARTIFACTORY_APP_HOME}"
AFCLHOME="${AFSAHOME}-cluster"
SHARDS3=(${ARTIFACAORY_S3_SHARD_LOCS//:/ })
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

######################################################
## "Rough-sketch" of further procedures to automate ##
######################################################
aws s3 cp s3://<TOOL_BUCKET>/SupportFiles/app-config.sh /etc/cfn/scripts/
aws s3 cp s3://<TOOL_BUCKET>/SupportFiles/artifactory-EE_setup.sh /etc/cfn/scripts/

aws s3 sync s3://<TOOL_BUCKET>/Licenses/ /etc/cfn/files/

yum install -y centos-release-scl\* jfrog-artifactory-pro

yum install -y rh-postgresql96

if [[ $( grep -q START_TMO /usr/lib/systemd/system/artifactory.service )$? -eq 0 ]]
then
   echo "Delayed starte-timeout already present"
else
   sed -i '/\[Service]/s/$/\nEnvironment=START_TMO=120/' /usr/lib/systemd/system/artifactory.service &&
     systemctl daemon-reload
fi


install -b -m 000644 -o artifactory -g artifactory <( cat /etc/cfn/files/ArtifactoryEE_* ) /var/opt/jfrog/artifactory/etc/artifactory.lic

install -b -m 000644 -o artifactory -g artifactory /etc/cfn/files/db.properties /var/opt/jfrog/artifactory/etc/db.properties

ln -s "$( rpm -ql postgresql-jdbc | grep jdbc.jar )" /var/opt/jfrog/artifactory/tomcat/lib/

install -d -m 0750 -o artifactory -g artifactory /var/opt/jfrog/artifactory/etc/security

chcon --reference /var/opt/jfrog/artifactory/etc/ /var/opt/jfrog/artifactory/etc/security

install -b -m 000640 <( awk -F= '/CLUSTER_KEY/{print $2}' /etc/cfn/Artifactory.envs ) -o artifactory -g artifactory /var/opt/jfrog/artifactory/etc/security/master.key

install -b -m 000644 -o artifactory -g artifactory <( 
  echo "node.id=$(hostname -s)"
  echo "context.url=http://$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$#:8081/artifactory#' )"
  echo "membership.port=10001"
  echo "primary=true"
  echo "artifactory.ha.data.dir=/var/opt/jfrog/artifactory-cluster/data"
  echo "artifactory.ha.backup.dir=/var/opt/jfrog/artifactory-cluster/backup"
  echo "hazelcast.interface=$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$##' )"
 ) /var/opt/jfrog/artifactory/etc/ha-node.properties

install -d -m 0750 -o artifactory -g artifactory /var/opt/jfrog/artifactory-cluster/{backup,data,cache}/


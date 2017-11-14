#!/bin/bash
# shellcheck disable=SC2015,SC2034
#
# Script to configure an OS for use with Gluster
#
#################################################################
PROGNAME=$(basename "${0}")
# shellcheck disable=SC1091
source /etc/cfn/AF.envs
AFINSTALLER="${ARTIFACTORY_INSTALLER:-UNDEF}"
CHKFIPS=/proc/sys/crypto/fips_enabled
FWPORTS=(
      8081/tcp
   )
FWSVCS=(
      http
      https
   )
PGSQLDBPORT="${ARTIFACTORY_DBPORT:-UNDEF}"
PGSQLDBHOST="${ARTIFACTORY_DBHOST:-UNDEF}"
PGSQLDBINST="${ARTIFACTORY_DBINST:-UNDEF}"
PGSQLDBUSER="${ARTIFACTORY_DBUSER:-UNDEF}"
PGSQLDBPASS="${ARTIFACTORY_DBPASS:-UNDEF}"
RPMDEPLST=(
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
## Add exceptions to host firewall config
function FwRules {
   for FWPORT in "${FWPORTS[@]}"
   do
      printf "Adding port exception(s) for %s... " "${FWPORT}"
      firewall-cmd --add-port="${FWPORT}" --permanent || \
         echo "Failed adding port exception(s) for ${FWPORT}"
   done

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
## Disable FIPS mode
function FipsDisable {
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

   # Prep for Artifactory install on reboot
   SetupRcLocal

   # Log a warning about FIPS
   echo "System will need to be rebooted for FIPS-disable to take full effect"
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
## Run app-setup via rc.local
function SetupRcLocal {
   local APPSCRIPT=/root/artifactory_Setup-PRO.sh
   local RUNONCE=/etc/rc.d/rc.local

   # Grab installer script
   printf "Downloading Artifactory installer-script... "
   curl -skL "${ARTIFACTORY_INSTALLER}" -o "${APPSCRIPT}" || \
     echo "Success!" || err_exit "Failed to download ${ARTIFACTORY_INSTALLER}"
   if [[ $(grep -q "/bin/bash" "${APPSCRIPT}")$? -ne 0 ]]
   then
     err_exit 'Failed to grab installer with valid contents'
   fi

   # Make it run from rc.local
   echo "Updating contents of ${RUNONCE}... "
   printf "\n### Artifactory config-tasks ###\n" >> "${RUNONCE}" || \
     err_exit "Failure updating ${RUNONCE}"
   echo "bash ${APPSCRIPT} 2>&1 | tee /var/log/AFinstall.log" \
     >> "${RUNONCE}" || err_exit "Failure updating ${RUNONCE}"
   chmod a+x "${RUNONCE}" || \
     err_exit 'Failed to make rc.local executable'
}


#######################
## Main Program Logic  
#######################
# Update firewalld rules (adjusting SELinux as necessary)
GETSELSTATE=$(getenforce)
if [[ ${GETSELSTATE} = Enforcing ]]
then
   setenforce Permissive || echo "Couldn't dial-back SELinux"
   FwRules
   setenforce "${GETSELSTATE}" || echo "Couldn't reset SELinux"
else
   FwRules
fi

# De-FIPS as necessary...
if [[ -f ${CHKFIPS} ]] && [[ $(grep -q 1 "${CHKFIPS}")$? -eq 0 ]]
then
   echo "FIPS mode is enabled. Attemtping to disable."
   FipsDisable
else
   # Prep for Artifactory install on reboot
   SetupRcLocal
   shutdown -r +1 'Rebooting to ensure system is ready to install Artifactory'
fi

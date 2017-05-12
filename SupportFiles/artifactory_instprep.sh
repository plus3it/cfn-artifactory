#!/bin/bash
#
# Prepare the instance for Installation of Artifactory
#
#################################################################
PROGNAME=$(basename "${0}")
RPMDEPLST=(
           postgresql-jdbc
          )
FWPORTS=(
         80
         443
         8081
        )
ARTIFACTORY_HOME=${ARTIFACTORY_HOME:-/var/opt/jfrog/artifactory}
ARTIFACTORY_ETC=${ARTIFACTORY_ETC:-${ARTIFACTORY_HOME}/etc}
ARTIFACTORY_LOGS=${ARTIFACTORY_LOGS:-${ARTIFACTORY_HOME}/logs}
ARTIFACTORY_VARS=${ARTIFACTORY_VARS:-${ARTIFACTORY_HOME}/etc/default}
ARTIFACTORY_TOMCAT_HOME=${ARTIFACTORY_TOMCAT_HOME:-${ARTIFACTORY_HOME}/tomcat}


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
      exit ${SCRIPTEXIT}
   else
      exit 1
   fi
}

##
## Open firewall ports
function FwStuff {
   # Temp-disable SELinux (need when used in cloud-init context)
   setenforce 0 || \
      err_exit "Failed to temp-disable SELinux"
   echo "Temp-disabled SELinux"

   if [[ $(systemctl --quiet is-active firewalld)$? -eq 0 ]]
   then
      local FWCMD='firewall-cmd'
   else
      local FWCMD='firewall-offline-cmd'
      ${FWCMD} --enabled
   fi

   for PORT in "${FWPORTS[@]}"
   do
      printf "Add firewall exception for port %s... " "${PORT}"
      ${FWCMD} --permanent --add-port=${PORT}/tcp || \
         err_exit "Failed to add port ${PORT} to firewalld"
   done

   # Restart firewalld with new rules loaded
   printf "Reloading firewalld rules... "
   ${FWCMD} --reload || \
      err_exit "Failed to reload firewalld rules"

   # Restart SELinux
   setenforce 1 || \
      err_exit "Failed to reactivate SELinux"
   echo "Re-enabled SELinux"
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


###
# Main
###

FwStuff
InstMissingRPM

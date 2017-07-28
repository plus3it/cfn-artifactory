#!/bin/bash
# shellcheck disable=SC2046
#
# This script is designed to update or create the
# ${ARTIFACTORY_HOME}/etc/db.properties file to enable Artifactory
# to leverage an external PGSQL database service.
#
#################################################################
PROGNAME=$(basename "${0}")
PGSQLJDBC=postgresql-jdbc
ARTIFACTORY_HOME=${ARTIFACTORY_HOME:-/var/opt/jfrog/artifactory}
ARTIFACTORY_ETC=${ARTIFACTORY_ETC:-${ARTIFACTORY_HOME}/etc}
ARTIFACTORY_LOGS=${ARTIFACTORY_LOGS:-${ARTIFACTORY_HOME}/logs}
ARTIFACTORY_VARS=${ARTIFACTORY_VARS:-${ARTIFACTORY_HOME}/etc/default}
ARTIFACTORY_TOMCAT_HOME=${ARTIFACTORY_TOMCAT_HOME:-${ARTIFACTORY_HOME}/tomcat}
ARTIFACTORY_DBINST="${ARTIFACTORY_DBINST:-UNDEF}"
ARTIFACTORY_DBUSER="${ARTIFACTORY_DBUSER:-UNDEF}"
ARTIFACTORY_DBPASS="${ARTIFACTORY_DBPASS:-UNDEF}"
ARTIFACTORY_DBHOST="${ARTIFACTORY_DBHOST:-UNDEF}"
ARTIFACTORY_DBPORT="${ARTIFACTORY_DBPORT:-5432}"
ARTIFACTORY_RPM=jfrog-artifactory-pro
ARTIFACTORY_LICKEY=${ARTIFACTORY_ETC}/artifactory.lic
DBPROPERTIES="${ARTIFACTORY_ETC}/db.properties"
SELSRC=${ARTIFACTORY_ETC}/mimetypes.xml

## Try not to let any prior stytem-hardening cause
## created files to have bad ownership-settings
umask 022

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
## Fix file attributes on requested file
function FixAttrs {
   local FIXFILE=${1}

   echo "Copying SEL contexts from ${SELSRC}"
   chcon --reference "${SELSRC}" "${FIXFILE}" || \
     err_exit "Unable to set SELinux context on new file."

   echo "Copying ownerships contexts from ${SELSRC}"
   chown $(stat -c "%U:%G" "${SELSRC}") "${FIXFILE}" || \
     err_exit "Unable to set proper ownership on new file."

   echo "Copying permissions contexts from original"
   chmod $(stat -c "%a" "${SELSRC}") "${FIXFILE}" || \
     err_exit "Unable to set proper permissions on new file."
}


##
## DB-setup for non-clustered nodes
function CreateDbProperties {
   if [[ -f ${DBPROPERTIES} ]]
   then
      mv "${DBPROPERTIES}" "${DBPROPERTIES}.BAK-${DATE}" || \
        err_exit "Failed to preserve existing '${DBPROPERTIES}' file"
   fi

   # Locate example contents
   SRCPGSQLCONF=$(rpm -ql ${ARTIFACTORY_RPM} | grep postgresql.properties)

   # Grab header-content from RPM's example file
   grep ^# "${SRCPGSQLCONF}" > "${DBPROPERTIES}" || \
      err_exit "Failed to create stub '${DBPROPERTIES}' content"

   ##
   ## Append db-connection info to db.properties file
   echo "Crerating new '${DBPROPERTIES}' file..."
cat << EOF >> "${DBPROPERTIES}"

type=postgresql
driver=org.postgresql.Driver
url=jdbc:postgresql://${ARTIFACTORY_DBHOST}:${ARTIFACTORY_DBPORT}/${ARTIFACTORY_DBINST}
username=${ARTIFACTORY_DBUSER}
password=${ARTIFACTORY_DBPASS}
EOF

   # Make sure the properites file actually got created/updated
   # shellcheck disable=SC2181
   if [[ $? -ne 0 ]]
   then
      err_exit "Error creating new '${DBPROPERTIES}' file. Aborting."
   fi

   # Fix the file attributes
   FixAttrs "${DBPROPERTIES}"
}


##
## Verify that the Artifactory RPM has been installed
if [[ $(rpm -q --quiet ${ARTIFACTORY_RPM})$? -eq 0 ]]
then
   echo "Found ${ARTIFACTORY_RPM} installed (via RPM)"
else
   err_exit "Did not find an installation of ${ARTIFACTORY_RPM}. Aborting."
fi

##
## Ensure mandatory values have been set
if [[ ${ARTIFACTORY_DBHOST} = UNDEF ]] ||
   [[ ${ARTIFACTORY_DBINST} = UNDEF ]] ||
   [[ ${ARTIFACTORY_DBUSER} = UNDEF ]] ||
   [[ ${ARTIFACTORY_DBPASS} = UNDEF ]]
then
   err_exit "One or more mandatory work-values not set"
fi

##
## Ensure PGSQL JAR file installed and linked
if [[ $(rpm -q --quiet ${PGSQLJDBC})$? -eq 0 ]]
then
   echo "PostGreSQL JDBC installed"
else
   echo "Attempting to install PostGreSQL JDBC..."
   yum install -y ${PGSQLJDBC} || \
      err_exit "Failed to install ${PGSQLJDBC}"
fi

if [[ $(stat "${ARTIFACTORY_TOMCAT_HOME}/lib/*jdbc.jar" \
        > /dev/null 2>&1)$? -eq 0 ]]
then
   echo "Found a PGSQL JDBC JAR in ${ARTIFACTORY_TOMCAT_HOME}/lib"
else
   echo "Linking PostGreSQL JDBC into Artifactory..."
   ln -s $(rpm -ql ${PGSQLJDBC} | grep jdbc.jar) \
      "${ARTIFACTORY_TOMCAT_HOME}/lib/" || \
         err_exit "Failed to link PostGreSQL JDBC into Artifactory."
fi

##
## Ensure file is usable by Artifactory
if [[ ${ARTIFACTORY_CL_MMBR} = false ]]
then
   CreateDbProperties
fi

FixAttrs "${ARTIFACTORY_LICKEY}"

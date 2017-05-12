#!/bin/bash
# shellcheck disable=SC2046,SC2086
#
# This script updated the ${ARTIFACTORY_HOME}/etc/binarystore.xml
#
# storage-configuration file to enable S3-based artifact storage.
#################################################################
PROGNAME=$(basename "${0}")
DATE=$(date "+%Y%m%d%H%M")
ARTIFACTORY_HOME="${ARTIFACTORY_HOME:-/var/opt/jfrog/artifactory}"
ARTIFACTORY_BUCKET="${ARTIFACTORY_BUCKET:-UNDEF}"
ARTIFACTORY_ROLE="${ARTIFACTORY_ROLE:-UNDEF}"
BINSTORXML="${ARTIFACTORY_HOME}/etc/binarystore.xml"

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
## Ensure minimal number of parms have been set
if [[ ${ARTIFACTORY_BUCKET} = UNDEF ]] ||
   [[ ${ARTIFACTORY_ROLE} = UNDEF ]] 
then
   err_exit "Failed to set a required parameter. Aborting..."
fi

##
## Preserve any existing binarystore.xml file
if [[ -f ${BINSTORXML} ]]
then
  mv "${BINSTORXML}" "${BINSTORXML}.BAK-${DATE}" || \
    err_exit "Unable to backup the \"${BINSTORXML}\" file! Aborting..."
  SELSRC="${BINSTORXML}.BAK-${DATE}"
fi

##
## Bail if the offered binarystore.xml directory doesn't exist
if [[ ! -d $(dirname "${BINSTORXML}") ]]
then
   err_exit "Aborting: no such directory '$(dirname ${BINSTORXML})'."
fi


##
## Create an S3-enabled binarystore.xml file with customized contents
cat << EOF > "${BINSTORXML}"
<!-- S3 chain template structure  -->
<config version="v1">
   <!-- Define flow of binary-data from cache to S3 -->
   <chain>
      <provider id="cache-fs" type="cache-fs">
         <!--It first tries to read from the cache -->
         <provider id="eventual" type="eventual">
            <!--It is eventually persistent so writes are also written directly to persistent storage -->
            <provider id="retry" type="retry">
               <!-- If a read or write fails, retry -->
               <provider id="s3" type="s3" />
               <!-- Actual storage is S3 -->
            </provider>
         </provider>
      </provider>
   </chain>
   <!--
    Pull max cache size from template
    Pull caching-dir from template
    -->
   <provider id="cache-fs" type="cache-fs">
      <maxCacheSize>5000000000</maxCacheSize>
      <!-- 5GB cache-size -->
      <cacheProviderDir>/var/cache/artifactory</cacheProviderDir>
      <!-- Caching location -->
   </provider>
   <provider id="eventual" type="eventual">
      <numberOfThreads>20</numberOfThreads>
      <!-- The maximum number of threads for parallel upload of files -->
   </provider>
   <provider id="retry" type="retry">
      <maxTrys>10</maxTrys>
      <!-- Try any read or write a maximum of 10 times -->
   </provider>
   <!--
    roleName, endpoint and bucketName should all be pulled from template
    -->
   <provider id="s3" type="s3">
      <roleName>${ARTIFACTORY_ROLE}</roleName>
      <endpoint>s3.amazonaws.com</endpoint>
      <bucketName>${ARTIFACTORY_BUCKET}</bucketName>
      <refreshCredentials>true</refreshCredentials>
   </provider>
</config>
EOF

##
## Apply SELinux contexts from replaced file
if [[ -z ${SELSRC+xxx} ]]
then
   echo "No previous file to recover ownership/perms/contexts from."
else
   echo "Copying SEL contexts from original"
   chcon --reference "${BINSTORXML}.BAK-${DATE}" "${BINSTORXML}" || \
     err_exit "Unable to set SELinux context on new file."
   echo "Copying ownerships contexts from original"
   chown $(stat -c "%U:%G" "${BINSTORXML}.BAK-${DATE}") "${BINSTORXML}" || \
     err_exit "Unable to set proper ownership on new file."
   echo "Copying permissions contexts from original"
   chmod $(stat -c "%a" "${BINSTORXML}.BAK-${DATE}") "${BINSTORXML}" || \
     err_exit "Unable to set proper permissions on new file."
fi

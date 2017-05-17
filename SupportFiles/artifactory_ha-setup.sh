#!/bin/bash
#
# Set up Artifactory node as a cluster-member (also suitable fo
# single-node "cluster" configurations
# 
#################################################################
PROGNAME="$(basename $0)"
HOSTNAME="$(curl -skL http://169.254.169.254/latest/meta-data/local-hostname/)"
NODEIPADDR="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4/)"
NODENAME="$(printf '%02X' $(echo ${NODEIPADDR}| sed 's/\./ /g'))"
ARTIFACTORY_HOME="${ARTIFACTORY_HOME:-/var/opt/jfrog/artifactory}"
ARTIFACTORY_ETC="${ARTIFACTORY_HOME}/etc"
ISPRIMARY=${ARTIFACTORY_CL_PRIM:-true}
HABUNDLE=${ARTIFACTORY_HABUNDLE:-UNDEF}
HACONF="${ARTIFACTORY_ETC}/ha-node.properties"

# Error-handler function
function err_exit {
   logger -s -p kern.crit -t "${PROGNAME}" "Failed: ${1}"
   exit 1
}

# Did we pass in location of the bundle file
if [[ ${HABUNDLE} = UNDEF ]]
then
   err_exit 'Location of HA-config bundle file not specified'
fi

# Download bootstrap bundle
curl -skL ${HABUNDLE} -o ${ARTIFACTORY_ETC}/bootstrap.bundle.tar.gz || \
  err_exit "was not able to download/save ${HABUNDLE}"

# Ensure the download didn't pull a bum file
if [[ $(file ${ARTIFACTORY_ETC}/bootstrap.bundle.tar.gz | grep -q gzip)$? -eq 0 ]]
then
   echo "Successfully installed ${ARTIFACTORY_ETC}/bootstrap.bundle.tar.gz"
else
  err_exit "Installed ${ARTIFACTORY_ETC}/bootstrap.bundle.tar.gz is not valid"
fi

# Create ha-node.properties file
printf "Creating %s... " "${HACONF}"
cat > ${HACONF} << EOF
node.id=${NODENAME}
context.url=http://${HOSTNAME}:8081/artifactory
membership.port=10001
primary=${ISPRIMARY}
hazelcast.interface=${NODEIPADDR}
EOF

if [[ $? -eq 0 ]]
then
   echo "Successfully created ${HACONF}"
else
   err_exit "Failed to create ${HACONF}"
fi

# Fix file perms/contexts
CHOWNER=$(stat -c "%U:%G" ${ARTIFACTORY_ETC})
for FIXIT in ${HACONF} ${ARTIFACTORY_ETC}/bootstrap.bundle.tar.gz
do
   chown "${CHOWNER}" "${FIXIT}"
   chcon --reference "${ARTIFACTORY_ETC}/mimetypes.xml" "${FIXIT}"
done

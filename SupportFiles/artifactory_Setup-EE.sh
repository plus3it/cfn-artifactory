#!/bin/bash
# shellcheck disable=
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
NFSSVR="${ARTIFACTORY_CLUSTER_HOME}"
AFSAHOME="${ARTIFACTORY_APP_HOME}"
AFCLHOME="${AFSAHOME}-cluster"
SHARDS3=(${ARTIFACAORY_S3_SHARD_LOCS//:/ })


##############################################
## "Rough-sketch" of procedures to automate ##
##############################################
aws s3 cp s3://<TOOL_BUCKET>/SupportFiles/app-config.sh /etc/cfn/scripts/
aws s3 cp s3://<TOOL_BUCKET>/SupportFiles/artifactory-EE_setup.sh /etc/cfn/scripts/

aws s3 sync s3://<TOOL_BUCKET>/Licenses/ /etc/cfn/files/

bash /etc/cfn/scripts/artifactory-EE_setup.sh 

init 6

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

install -b -m 000644 -o artifactory -g artifactory <( cat /var/opt/jfrog/artifactory/misc/db/postgresql.properties && awk -F= '/_DB_/{print $2}' /etc/cfn/Artifactory.envs ) /var/opt/jfrog/artifactory/etc/db.properties

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


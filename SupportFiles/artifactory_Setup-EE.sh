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


#################################################################
##
## Manual steps (ARTIFACTORY_APP_HOME=/var/opt/jfrog/artifactory)
##
## 1) yum install -y jfrog-artifactory-pro
## 2) Install Enterprise license (file)
##    - s3 to /etc/cfn/files
##    - copy to ${ARTIFACTORY_APP_HOME}/etc/artifactory.lic
##    - fix perms/ownerships/labels
## 3) create ${ARTIFACTORY_APP_HOME}/etc/db.properties file
##    type=postgresql
##    driver=org.postgresql.Driver
##    url=jdbc:postgresql://${ARTIFACTORY_DB_HOSTFQDN}:5432/${ARTIFACTORY_DB_INSTANCE}
##    username=${ARTIFACTORY_DB_ADMIN}
##    password=${ARTIFACTORY_DB_PASSWD}
## 4) Link PostGresql JDBC into Tomcat lib-dir:
##    ln -s $( rpm -ql postgresql-jdbc | grep jdbc.jar ) ${ARTIFACTORY_APP_HOME}/tomcat/lib
## 5) Create the ${ARTIFACTORY_APP_HOME}/etc/security/master.key file
##    install -b -m 000644 -o artifactory -g artifactory <( openssl rand -hex 16 ) \
##      ${ARTIFACTORY_APP_HOME}/etc/security/master.key file
## 6) Create ha-node.properties file:
##    install -b -m 000644 -o artifactory -g artifactory /dev/null /var/opt/jfrog/artifactory/etc/ha-node.properties
##    (
##     echo node.id=$( hostname -s )
##     echo contexturl=http://$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$##' )/artifactory
##     echo membership.port=10001
##     echo primary=$( awk -F = '/ARTIFACTORY_CLUSTER_MASTER/{print $2}' /etc/cfn/Artifactory.envs )
##     echo artifactory.ha.data.dir=/var/opt/jfrog/artifactory-cluster/data
##     echo artifactory.ha.backup.dir=/var/opt/jfrog/artifactory-cluster/backup
##     echo hazelcast.interface=$( ip addr show eth0 | awk '/ inet /{print $2}' | sed 's#/.*$##' )
##    )
## 7) Create binarystore.xml file:
##    install -b -m 000644 -o artifactory -g artifactory /dev/null /var/opt/jfrog/artifactory/etc/binarystore.xml
## 8) Ensure systemd unit-file has Environment=START_TMO=120 in [service] block
##

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
## 
## 
## 
## 
## 
## 

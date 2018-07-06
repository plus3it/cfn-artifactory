def RdsParmFile = 'Rds.parms.json'

pipeline {

    agent any

    options {
        buildDiscarder(
            logRotator(
                numToKeepStr: '5',
                daysToKeepStr: '30',
                artifactDaysToKeepStr: '30',
                artifactNumToKeepStr: '5'
            )
        )
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        AWS_DEFAULT_REGION = "${AwsRegion}"
        AWS_CA_BUNDLE = '/etc/pki/tls/certs/ca-bundle.crt'
        REQUESTS_CA_BUNDLE = '/etc/pki/tls/certs/ca-bundle.crt'
    }

    parameters {
        string(name: 'AwsRegion', defaultValue: 'us-east-1', description: 'Amazon region to deploy resources into')
        string(name: 'AwsCred', description: 'Jenkins-stored AWS credential with which to execute cloud-layer commands')
        string(name: 'GitCred', description: 'Jenkins-stored Git credential with which to execute git commands')
        string(name: 'GitProjUrl', description: 'SSH URL from which to download the Sonarqube git project')
        string(name: 'GitProjBranch', description: 'Project-branch to use from the Sonarqube git project')
        string(name: 'CfnStackRoot', description: 'Unique token to prepend to all stack-element names')
        string(name: 'TargetVpc', description: 'VPC in which to launch stack-resources into')
        string(name: 'DbAdminName', description: 'Name of the database instance administrator account')
        string(name: 'DbAdminPass', description: 'Password of the database instance administrator account')
        string(name: 'DbDataSize', defaultValue: '5', description: 'Size in GiB of the RDS table-space to create')
        string(name: 'DbInstanceName', description: 'Instance-name of the Artifactory database')
        string(name: 'DbInstanceType', defaultValue: 'db.m4.large', description: 'Amazon RDS instance type')
        string(name: 'DbIsMultiAz', defaultValue: 'true', description: 'Select whether to create a multi-AZ RDS deployment')
        string(name: 'DbNodeName', defaultValue: '', description: 'NodeName of the Artifactory database')
        string(name: 'DbSecurityGroup', description: 'List of security groups to apply to the RDS database')
        string(name: 'DbSnapshotId', defaultValue: '', description: 'RDS snapshot-ARN to clone new database from')
        string(name: 'DbStorageIops', defaultValue: '1000', description: 'Provisioned-IOPS of storage to used to host DB-data')
        string(name: 'DbStorageType', defaultValue: 'gp2', description: 'Type of storage used to host DB-data')
        string(name: 'DbSubnets', description: 'Subnets to build RDS into: Select at least two subnets, each in different Availability Zones')
        string(name: 'PgsqlVersion', defaultValue: '9.6.5', description: 'The X.Y.Z version of the PostGreSQL database to deploy.')
    }

    stages {
        stage ('Prepare Agent Environment') {
            steps {
                deleteDir()
                git branch: "${GitProjBranch}",
                    credentialsId: "${GitCred}",
                    url: "${GitProjUrl}"
                echo env.DbSnapshotId
                writeFile file: RdsParmFile,
                    text: /
                         [
                             {
                                 "ParameterKey": "DbAdminName",
                                 "ParameterValue": "${DbAdminName}"
                             },
                             {
                                 "ParameterKey": "DbAdminPass",
                                 "ParameterValue": "${DbAdminPass}"
                             },
                             {
                                 "ParameterKey": "DbDataSize",
                                 "ParameterValue": "${DbDataSize}"
                             },
                             {
                                 "ParameterKey": "DbInstanceName",
                                 "ParameterValue": "${DbInstanceName}"
                             },
                             {
                                 "ParameterKey": "DbInstanceType",
                                 "ParameterValue": "${DbInstanceType}"
                             },
                             {
                                 "ParameterKey": "DbIsMultiAz",
                                 "ParameterValue": "${DbIsMultiAz}"
                             },
                             {
                                 "ParameterKey": "DbSnapshotId",
                                 "ParameterValue": "${env.DbSnapshotId}"
                             },
                             {
                                 "ParameterKey": "DbNodeName",
                                 "ParameterValue": "${env.DbNodeName}"
                             },
                             {
                                 "ParameterKey": "DbSecurityGroup",
                                 "ParameterValue": "${DbSecurityGroup}"
                             },
                             {
                                 "ParameterKey": "DbStorageIops",
                                 "ParameterValue": "${DbStorageIops}"
                             },
                             {
                                 "ParameterKey": "DbStorageType",
                                 "ParameterValue": "${DbStorageType}"
                             },
                             {
                                 "ParameterKey": "DbSubnets",
                                 "ParameterValue": "${DbSubnets}"
                             },
                             {
                                 "ParameterKey": "PgsqlVersion",
                                 "ParameterValue": "${PgsqlVersion}"
                             },
                             {
                                 "ParameterKey": "TargetVPC",
                                 "ParameterValue": "${TargetVpc}"
                             }
                         ]
                   /
                sh "cat ${RdsParmFile}"
            }
        }
        stage ('Prepare AWS Environment') {
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to delete any active ${CfnStackRoot}-RdsRes stacks... "
                        aws --region "${AwsRegion}" cloudformation delete-stack --stack-name "${CfnStackRoot}-RdsRes" 

                        sleep 5

                        # Pause if delete is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-RdsRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q DELETE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-RdsRes to delete..."
                           sleep 30
                        done
                    '''
                }
            }
        }
        stage ('Launch Rds Stack') {
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to create stack ${CfnStackRoot}-RdsRes..."
                        aws --region "${AwsRegion}" cloudformation create-stack --stack-name "${CfnStackRoot}-RdsRes" \
                          --disable-rollback --capabilities CAPABILITY_NAMED_IAM \
                          --template-body file://Templates/make_artifactory-PRO_RDS.tmplt.json \
                          --parameters file://Rds.parms.json
 
                        sleep 15
 
                        # Pause if create is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-RdsRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q CREATE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-RdsRes to finish create process..."
                           sleep 30
                        done
 
                        if [[ $(
                                aws cloudformation describe-stacks \
                                  --stack-name ${CfnStackRoot}-RdsRes \
                                  --query 'Stacks[].{Status:StackStatus}' \
                                  --out text 2> /dev/null | \
                                grep -q CREATE_COMPLETE
                               )$? -eq 0 ]]
                        then
                           echo "Stack-creation successful"
                        else
                           echo "Stack-creation ended with non-successful state"
                           exit 1
                        fi
                    '''
                }
            }
        }
    }
}

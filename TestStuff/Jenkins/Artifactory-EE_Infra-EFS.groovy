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
        string(name: 'GitProjUrl', description: 'SSH URL from which to download the Artifactory git project')
        string(name: 'GitProjBranch', description: 'Project-branch to use from the Artifactory git project')
        string(name: 'CfnStackRoot', description: 'Unique token to prepend to all stack-element names')
        string(name: 'ArtifactoryListenPort', defaultValue: '443', description: 'TCP Port number on which the Artifactory ELB listens for requests')
        string(name: 'ArtifactoryListenerCert', description: 'Name/ID of the ACM-managed SSL Certificate securing the public listener')
        string(name: 'ArtifactoryServicePort', defaultValue: '80', description: 'TCP Port number that the Artifactory host listens to')
        string(name: 'BackendTimeout', defaultValue: '600', description: 'How long (in seconds) back-end connection may be idle before attempting session-cleanup')
        string(name: 'BackupBucketInventoryTracking', defaultValue: 'false', description: '(Optional) Whether to enable generic bucket inventory-tracking. Requires setting of the "BackupReportingBucket" parameter')
        string(name: 'BackupBucketName', description: '(Optional: will be randomly named if left un-set) Name to give to S3 Bucket used for longer-term retention of backups')
        string(name: 'BackupReportingBucket', description: '(Optional) Destination for storing analytics data. Must be provided in ARN format')
        string(name: 'CloudwatchBucketName', defaultValue: 'amazoncloudwatch-agent',description: 'Name of the S3 Bucket hosting the CloudWatch agent archive files')
        string(name: 'DbAdminName', description: 'Name of the Artifactory master database-user')
        string(name: 'DbAdminPass', description: 'Password of the Artifactory master database-user')
        string(name: 'DbDataSize', defaultValue: '5', description: 'Size in GiB of the RDS table-space to create')
        string(name: 'DbInstanceName', description: 'Instance-name of the Artifactory database')
        string(name: 'DbInstanceType', defaultValue: 'db.m4.large', description: 'Amazon RDS instance type')
        string(name: 'DbIsMultiAz', defaultValue: 'true', description: 'Select whether to create a multi-AZ RDS deployment')
        string(name: 'DbNodeName', description: 'NodeName to assign to the RDS endpoint')
        string(name: 'DbSnapshotId', description: '(Optional) RDS snapshot-ARN to clone new database from')
        string(name: 'DbStorageIops', defaultValue: '1000', description: 'Provisioned-IOPS of storage to used to host DB-data')
        string(name: 'DbStorageType', defaultValue: 'gp2', description: 'Type of storage used to host DB-data')
        string(name: 'FinalExpirationDays', defaultValue: '30', description: 'Number of days to retain backups before aging them out of the bucket')
        string(name: 'PgsqlVersion', defaultValue: '9.6.9', description: 'The X.Y.Z version of the PostGreSQL database to deploy')
        string(name: 'ProxyPrettyName', description: 'A short, human-friendly label to assign to the ELB (no capital letters)')
        string(name: 'RetainIncompleteDays', defaultValue: '3', description: 'Number of days to retain backups that were not completely uploaded')
        string(name: 'RolePrefix', description: '(Optional) Prefix to apply to IAM role')
        string(name: 'RootTemplateUrl', description: 'Root URL where all S3-hosted, template files are stored')
        string(name: 'ServiceSubnets', description: 'Subnets to deploy service-elements to: select as many private-subnets as are available in VPC - selecting one from each Availability Zone')
        string(name: 'ShardBucketInventoryTracking', defaultValue: 'false', description: '(Optional) Whether to enable generic bucket inventory-tracking. Requires setting of the "ShardReportingBucket" parameter')
        string(name: 'ShardBucketName', description: '(Optional: will be randomly named if left un-set) Name to set for S3 Bucket used for hosting live Artifactory data')
        string(name: 'ShardReportingBucket', description: '(Optional) Destination for storing analytics data. Must be provided in ARN format')
        string(name: 'TargetVPC', description: 'ID of the VPC to deploy cluster nodes into')
        string(name: 'TierToGlacierDays', defaultValue: '5', description: 'Number of days to retain backups in standard storage tier')
        string(name: 'UserFacingSubnets', description: 'Subnets used by "public" to access service-elements:  select as many public-subnets as are available in VPC - selecting one from each Availability Zone')
    }

    stages {
        stage ('Prepare Agent Environment') {
            steps {
                deleteDir()
                git branch: "${GitProjBranch}",
                    credentialsId: "${GitCred}",
                    url: "${GitProjUrl}"
                writeFile file: 'InfraStack.parms.json',
                    text: /
                       [
                            {
                                "ParameterKey": "ArtifactoryListenPort",
                                "ParameterValue": "${env.ArtifactoryListenPort}"
                            },
                            {
                                "ParameterKey": "ArtifactoryListenerCert",
                                "ParameterValue": "${env.ArtifactoryListenerCert}"
                            },
                            {
                                "ParameterKey": "ArtifactoryServicePort",
                                "ParameterValue": "${env.ArtifactoryServicePort}"
                            },
                            {
                                "ParameterKey": "BackendTimeout",
                                "ParameterValue": "${env.BackendTimeout}"
                            },
                            {
                                "ParameterKey": "BackupBucketInventoryTracking",
                                "ParameterValue": "${env.BackupBucketInventoryTracking}"
                            },
                            {
                                "ParameterKey": "BackupBucketName",
                                "ParameterValue": "${env.BackupBucketName}"
                            },
                            {
                                "ParameterKey": "BackupReportingBucket",
                                "ParameterValue": "${env.BackupReportingBucket}"
                            },
                            {
                                "ParameterKey": "CloudwatchBucketName",
                                "ParameterValue": "${env.CloudwatchBucketName}"
                            },
                            {
                                "ParameterKey": "DbAdminName",
                                "ParameterValue": "${env.DbAdminName}"
                            },
                            {
                                "ParameterKey": "DbAdminPass",
                                "ParameterValue": "${env.DbAdminPass}"
                            },
                            {
                                "ParameterKey": "DbDataSize",
                                "ParameterValue": "${env.DbDataSize}"
                            },
                            {
                                "ParameterKey": "DbInstanceName",
                                "ParameterValue": "${env.DbInstanceName}"
                            },
                            {
                                "ParameterKey": "DbInstanceType",
                                "ParameterValue": "${env.DbInstanceType}"
                            },
                            {
                                "ParameterKey": "DbIsMultiAz",
                                "ParameterValue": "${env.DbIsMultiAz}"
                            },
                            {
                                "ParameterKey": "DbNodeName",
                                "ParameterValue": "${env.DbNodeName}"
                            },
                            {
                                "ParameterKey": "DbSnapshotId",
                                "ParameterValue": "${env.DbSnapshotId}"
                            },
                            {
                                "ParameterKey": "DbStorageIops",
                                "ParameterValue": "${env.DbStorageIops}"
                            },
                            {
                                "ParameterKey": "DbStorageType",
                                "ParameterValue": "${env.DbStorageType}"
                            },
                            {
                                "ParameterKey": "FinalExpirationDays",
                                "ParameterValue": "${env.FinalExpirationDays}"
                            },
                            {
                                "ParameterKey": "PgsqlVersion",
                                "ParameterValue": "${env.PgsqlVersion}"
                            },
                            {
                                "ParameterKey": "ProxyPrettyName",
                                "ParameterValue": "${env.ProxyPrettyName}"
                            },
                            {
                                "ParameterKey": "RetainIncompleteDays",
                                "ParameterValue": "${env.RetainIncompleteDays}"
                            },
                            {
                                "ParameterKey": "RolePrefix",
                                "ParameterValue": "${env.RolePrefix}"
                            },
                            {
                                "ParameterKey": "RootTemplateUrl",
                                "ParameterValue": "${env.RootTemplateUrl}"
                            },
                            {
                                "ParameterKey": "ServiceSubnets",
                                "ParameterValue": "${env.ServiceSubnets}"
                            },
                            {
                                "ParameterKey": "ShardBucketInventoryTracking",
                                "ParameterValue": "${env.ShardBucketInventoryTracking}"
                            },
                            {
                                "ParameterKey": "ShardBucketName",
                                "ParameterValue": "${env.ShardBucketName}"
                            },
                            {
                                "ParameterKey": "ShardReportingBucket",
                                "ParameterValue": "${env.ShardReportingBucket}"
                            },
                            {
                                "ParameterKey": "TargetVPC",
                                "ParameterValue": "${env.TargetVPC}"
                            },
                            {
                                "ParameterKey": "TierToGlacierDays",
                                "ParameterValue": "${env.TierToGlacierDays}"
                            },
                            {
                                "ParameterKey": "UserFacingSubnets",
                                "ParameterValue": "${env.UserFacingSubnets}"
                            }
                       ]
                   /
            }
        }
        stage ('Prepare AWS Environment') {
            options {
                timeout(time: 1, unit: 'HOURS')
            }
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to delete any active ${CfnStackRoot} stacks... "
                        aws --region "${AwsRegion}" cloudformation delete-stack --stack-name "${CfnStackRoot}" 

                        sleep 5

                        # Pause if delete is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot} \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q DELETE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot} to delete..."
                           sleep 30
                        done
                    '''
                }
            }
        }
        stage ('Launch SG Stack') {
            options {
                timeout(time: 1, unit: 'HOURS')
            }
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to create stack ${CfnStackRoot}..."
                        aws --region "${AwsRegion}" cloudformation create-stack --stack-name "${CfnStackRoot}" \
                          --disable-rollback --capabilities CAPABILITY_NAMED_IAM \
                          --template-body file://Templates/make_artifactory-EE_parent-EFSinfra.tmplt.json \
                          --parameters file://InfraStack.parms.json
 
                        sleep 15
 
                        # Pause if create is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot} \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q CREATE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot} to finish create process..."
                           sleep 30
                        done
 
                        if [[ $(
                                aws cloudformation describe-stacks \
                                  --stack-name ${CfnStackRoot} \
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

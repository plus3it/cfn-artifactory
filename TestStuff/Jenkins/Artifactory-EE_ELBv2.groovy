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
        timeout(time: 5, unit: 'MINUTES')
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
        string(name: 'BackendTimeout', description: 'How long - in seconds - back-end connection may be idle before attempting session-cleanup')
        string(name: 'HaSubnets', description: 'User-facing subnets: select three subnets - each from different Availability Zones')
        string(name: 'ProxyPrettyName', description: 'A short, human-friendly label to assign to the ELB (no capital letters)')
        string(name: 'SecurityGroupIds', description: 'List of security groups to apply to the ELB')
        string(name: 'ArtifactoryInstanceId', description: 'ID of the EC2-instance this template should create a proxy for')
        string(name: 'ArtifactoryListenerCert', description: 'Name/ID of the ACM-managed SSL Certificate to protect public listener')
        string(name: 'ArtifactoryListenPort', description: 'TCP Port number on which the Artifactory ELB listens for requests')
        string(name: 'ArtifactoryServicePort', description: 'TCP Port number that the Artifactory host listens to')
        string(name: 'TargetVPC', description: 'ID of the VPC to deploy cluster nodes into')
    }


    stages {
        stage ('Prepare Agent Environment') {
            steps {
                deleteDir()
                git branch: "${GitProjBranch}",
                    credentialsId: "${GitCred}",
                    url: "${GitProjUrl}"
                writeFile file: 'ELBv2.parms.json',
                    text: /
                         [
                             {
                                 "ParameterKey": "BackendTimeout",
                                 "ParameterValue": "${env.BackendTimeout}"
                             },
                             {
                                 "ParameterKey": "HaSubnets",
                                 "ParameterValue": "${env.HaSubnets}"
                             },
                             {
                                 "ParameterKey": "ProxyPrettyName",
                                 "ParameterValue": "${env.ProxyPrettyName}"
                             },
                             {
                                 "ParameterKey": "SecurityGroupIds",
                                 "ParameterValue": "${env.SecurityGroupIds}"
                             },
                             {
                                 "ParameterKey": "ArtifactoryInstanceId",
                                 "ParameterValue": "${env.ArtifactoryInstanceId}"
                             },
                             {
                                 "ParameterKey": "ArtifactoryListenerCert",
                                 "ParameterValue": "${env.ArtifactoryListenerCert}"
                             },
                             {
                                 "ParameterKey": "ArtifactoryListenPort",
                                 "ParameterValue": "${env.ArtifactoryListenPort}"
                             },
                             {
                                 "ParameterKey": "ArtifactoryServicePort",
                                 "ParameterValue": "${env.ArtifactoryServicePort}"
                             },
                             {
                                 "ParameterKey": "TargetVPC",
                                 "ParameterValue": "${env.TargetVPC}"
                             }
                         ]
                   /
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
                        echo "Attempting to delete any active ${CfnStackRoot}-ElbRes stacks... "
                        aws --region "${AwsRegion}" cloudformation delete-stack --stack-name "${CfnStackRoot}-ElbRes" 

                        sleep 5

                        # Pause if delete is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-ElbRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q DELETE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-ElbRes to delete..."
                           sleep 30
                        done
                    '''
                }
            }
        }
        stage ('Launch SG Stack') {
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to create stack ${CfnStackRoot}-ElbRes..."
                        aws --region "${AwsRegion}" cloudformation create-stack --stack-name "${CfnStackRoot}-ElbRes" \
                          --disable-rollback --capabilities CAPABILITY_NAMED_IAM \
                          --template-body file://Templates/make_artifactory-EE_ELBv2.tmplt.json \
                          --parameters file://ELBv2.parms.json
 
                        sleep 15
 
                        # Pause if create is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-ElbRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q CREATE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-ElbRes to finish create process..."
                           sleep 30
                        done
 
                        if [[ $(
                                aws cloudformation describe-stacks \
                                  --stack-name ${CfnStackRoot}-ElbRes \
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

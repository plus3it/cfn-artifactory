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
        timeout(time: 30, unit: 'MINUTES')
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
        string(name: 'AmiId', description: 'ID of the AMI from which to launch an instance')
        string(name: 'InstanceType', defaultValue: 't2.xlarge', description: 'Amazon EC2 instance type')
        string(name: 'KeyPairName', description: 'Logical name of instance-provisioner SSH key')
        string(name: 'SecurityGroupIds', description: 'List of security groups to apply to the instance')
        string(name: 'SubnetId', description: 'ID of the subnet to assign to the instance')
        string(name: 'CfnGetPipUrl', defaultValue: 'https://bootstrap.pypa.io/2.6/get-pip.py', description: 'URL from which to fetch "URL to get-pip.py" utility')
        string(name: 'InstanceRoleName', description: 'IAM instance role-name to use for signalling')
        string(name: 'InstanceRoleProfile', description: 'IAM instance profile-name to apply to the instance')
        string(name: 'CloudWatchAgentUrl', defaultValue: 's3://amazoncloudwatch-agent/linux/amd64/latest/AmazonCloudWatchAgent.zip', description: 'S3 URL to CloudWatch Agent installer')
        string(name: 'PypiIndexUrl', defaultValue: 'https://pypi.org/simple', description: 'URL to the PyPi Index')
        string(name: 'CfnBootstrapUtilsUrl', defaultValue: 'https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz', description: 'URL to aws-cfn-bootstrap-latest.tar.gz')
        string(name: 'WatchmakerEnvironment', defaultValue: 'dev', description: 'Environment in which the instance is being deployed')
        string(name: 'WatchmakerComputerName', defaultValue: 'host0.localdomain', description: 'Hostname to assign to node')
        string(name: 'ToggleCfnInitUpdate', description: 'Arbitrary value that forces and instance to be updated')
        string(name: 'AppScriptParams', defaultValue: '', description: 'Parameters to pass to application-script')
    }

    stages {
        stage ('Prepare Agent Environment') {
            steps {
                deleteDir()
                git branch: "${GitProjBranch}",
                    credentialsId: "${GitCred}",
                    url: "${GitProjUrl}"
                writeFile file: 'EC2-Wam.parms.json',
                    text: /
                        [
                            {
                                "ParameterKey": "AmiId",
                                "ParameterValue": "${env.AmiId}"
                            },
                            {
                                "ParameterKey": "InstanceType",
                                "ParameterValue": "${env.InstanceType}"
                            },
                            {
                                "ParameterKey": "KeyPairName",
                                "ParameterValue": "${env.KeyPairName}"
                            },
                            {
                                "ParameterKey": "SecurityGroupIds",
                                "ParameterValue": "${env.SecurityGroupIds}"
                            },
                            {
                                "ParameterKey": "SubnetId",
                                "ParameterValue": "${env.SubnetId}"
                            },
                            {
                                "ParameterKey": "CfnGetPipUrl",
                                "ParameterValue": "${env.CfnGetPipUrl}"
                            },
                            {
                                "ParameterKey": "InstanceRoleName",
                                "ParameterValue": "${env.InstanceRoleName}"
                            },
                            {
                                "ParameterKey": "InstanceRoleProfile",
                                "ParameterValue": "${env.InstanceRoleProfile}"
                            },
                            {
                                "ParameterKey": "CloudWatchAgentUrl",
                                "ParameterValue": "${env.CloudWatchAgentUrl}"
                            },
                            {
                                "ParameterKey": "PypiIndexUrl",
                                "ParameterValue": "${env.PypiIndexUrl}"
                            },
                            {
                                "ParameterKey": "CfnBootstrapUtilsUrl",
                                "ParameterValue": "${env.CfnBootstrapUtilsUrl}"
                            },
                            {
                                "ParameterKey": "WatchmakerEnvironment",
                                "ParameterValue": "${env.WatchmakerEnvironment}"
                            },
                            {
                                "ParameterKey": "WatchmakerComputerName",
                                "ParameterValue": "${env.WatchmakerComputerName}"
                            },
                            {
                                "ParameterKey": "ToggleCfnInitUpdate",
                                "ParameterValue": "${env.ToggleCfnInitUpdate}"
                            },
                            {
                                "ParameterKey": "AppScriptParams",
                                "ParameterValue": "${env.AppScriptParams}"
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
                        echo "Attempting to delete any active ${CfnStackRoot}-WamRes stacks... "
                        aws --region "${AwsRegion}" cloudformation delete-stack --stack-name "${CfnStackRoot}-WamRes" 

                        sleep 5

                        # Pause if delete is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-WamRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q DELETE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-WamRes to delete..."
                           sleep 30
                        done
                    '''
                }
            }
        }
        stage ('Launch Instance Stack') {
            steps {
                withCredentials(
                    [
                        [$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: "${AwsCred}", secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                        sshUserPrivateKey(credentialsId: "${GitCred}", keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: 'SSH_KEY_PASS', usernameVariable: 'SSH_KEY_USER')
                    ]
                ) {
                    sh '''#!/bin/bash
                        echo "Attempting to create stack ${CfnStackRoot}-WamRes..."
                        aws --region "${AwsRegion}" cloudformation create-stack --stack-name "${CfnStackRoot}-WamRes" \
                          --disable-rollback --capabilities CAPABILITY_NAMED_IAM \
                          --template-body file://Templates/make_artifactory-EE-EC2-node.tmplt.json \
                          --parameters file://EC2-Wam.parms.json
 
                        sleep 15
 
                        # Pause if create is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-WamRes \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q CREATE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-WamRes to finish create process..."
                           sleep 30
                        done
 
                        if [[ $(
                                aws cloudformation describe-stacks \
                                  --stack-name ${CfnStackRoot}-WamRes \
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

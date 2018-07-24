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
        string(name: 'TemplateUrl', description: 'S3-hosted location of EC2 CFn template')
        string(name: 'AkaList', defaultValue: '', description: '')
        string(name: 'AmiId', description: 'ID of the AMI from which to launch an instance')
        string(name: 'InstanceType', defaultValue: 't2.xlarge', description: 'Amazon EC2 instance type')
        string(name: 'KeyPairName', description: 'Logical name of instance-provisioner SSH key')
        string(name: 'SecurityGroupIds', description: 'List of security groups to apply to the instance')
        string(name: 'SubnetId', description: 'ID of the subnet to assign to the instance')
        string(name: 'ArtifactoryAppHome', description: 'Root-location of non-shared Artifactory components')
        string(name: 'ArtifactoryClusterHome', description: 'Root-location of cluster-shared Artifactory components')
        string(name: 'ArtifactoryClusterKey', description: 'A hexadecimal string used to secure intra-cluster communications (ignored if "ClusterHome" is null; use `openssl rand -hex 16` to generate)')
        string(name: 'ArtifactoryClusterMaster', description: 'Whether this node is a cluster master-node (ignored if "ClusterHome" is null)')
        string(name: 'ArtifactoryDbHostFqdn', description: 'Fully-qualified domain name of the (externalized) Artifactory configuration database-host/cluster')
        string(name: 'ArtifactoryDbInstance', description: 'Instance-name of the Artifactory configuration database')
        string(name: 'ArtifactoryDbAdminUser', description: 'Name of the privileged user account used to connect to the Artifactory configuration database')
        string(name: 'ArtifactoryDbAdminPasswd', description: 'Password of the privileged user account used to connect to the Artifactory configuration database')
        string(name: 'ArtifactoryRepoUrl', defaultValue: 'https://jfrog.bintray.com/artifactory-pro-rpms', description: 'URL/location of the repository definition-file that configures Artifactory RPM download capability')
        string(name: 'ArtifactoryRpmName', defaultValue: 'jfrog-artifactory-pro', description: 'Name of the Artifactory installation-RPM. Include release version if "other-than-latest" is desired. Example values would be: jfrog-artifactory-pro, jfrog-artifactory-pro-X.Y.Z')
        string(name: 'ArtifactoryS3BakupLocs', description: 'Name of the S3 bucket used as destination for automated backups')
        string(name: 'ArtifactoryS3ShardLocs', description: 'Name of the S3 bucket(s) used as destination for sharded artifact storage (use a colon-delimited list if more than one bucket will be used')
        string(name: 'ArtifactoryToolBucket', description: 'S3 bucket containing install tools, licenses, etc.')
        string(name: 'CfnBootstrapUtilsUrl', defaultValue: 'https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz', description: 'URL to aws-cfn-bootstrap-latest.tar.gz')
        string(name: 'CfnGetPipUrl', defaultValue: 'https://bootstrap.pypa.io/2.6/get-pip.py', description: 'URL from which to fetch "URL to get-pip.py" utility')
        string(name: 'CloudWatchAgentUrl', defaultValue: 's3://amazoncloudwatch-agent/linux/amd64/latest/AmazonCloudWatchAgent.zip', description: 'S3 URL to CloudWatch Agent installer')
        string(name: 'InstanceRoleName', description: 'IAM instance role-name to use for signalling')
        string(name: 'InstanceRoleProfile', description: 'IAM instance profile-name to apply to the instance')
        string(name: 'NoPublicIp', defaultValue: 'true', description: 'Controls whether to assign the instance a public IP. Recommended to leave at "true" unless launching in a public subnet')
        string(name: 'NoReboot', description: 'Controls whether to reboot the instance as the last step of cfn-init execution')
        string(name: 'NoUpdates', defaultValue: 'false', description: 'Controls whether to run yum update during a stack update (on the initial instance launch, Watchmaker usually installs updates)')
        string(name: 'PrivateIp', description: '(Optional) Set a static, primary private IP. Leave blank to auto-select a free IP')
        string(name: 'PypiIndexUrl', defaultValue: 'https://pypi.org/simple', description: 'URL to the PyPi Index')
        string(name: 'ProvisionUser', defaultValue: 'testuser', description: 'Name to use for provisioning-user account (instance default-account)')
        string(name: 'AdminGroupKeyfile', defaultValue: '', description: 'URL to public-key bundle to install into provisioning-user authorized_keys file')
        string(name: 'RootVolumeSize', description: 'Size in GB of the root EBS volume to create. If smaller than AMI default, create operation will fail; If larger, root device-volume partition size will be increased')
        string(name: 'ToggleCfnInitUpdate', description: 'Arbitrary value that forces and instance to be updated')
        string(name: 'WatchmakerAdminGroups', description: '(Optional) Colon-separated list of domain groups that should have admin permissions on the EC2 instance')
        string(name: 'WatchmakerAdminUsers', description: '(Optional) Colon-separated list of domain users that should have admin permissions on the EC2 instance')
        string(name: 'WatchmakerComputerName', defaultValue: 'host0.localdomain', description: 'Hostname to assign to node')
        string(name: 'WatchmakerConfig', description: '(Optional) Path to a Watchmaker config file.  The config file path can be a remote source (i.e. http[s]://, s3://) or local directory (i.e. file://)')
        string(name: 'WatchmakerEnvironment', defaultValue: 'dev', description: 'Environment in which the instance is being deployed')
        string(name: 'WatchmakerOuPath', description: '(Optional) DN of the OU to place the instance when joining a domain. If blank and "WatchmakerEnvironment" enforces a domain join, the instance will be placed in a default container. Leave blank if not joining a domain, or if "WatchmakerEnvironment" is "false"')
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
                                "ParameterKey": "AdminGroupKeyfile",
                                "ParameterValue": "${env.AdminGroupKeyfile}"
                            },
                            {
                                "ParameterKey": "AkaList",
                                "ParameterValue": "${env.AkaList}"
                            },
                            {
                                "ParameterKey": "AmiId",
                                "ParameterValue": "${env.AmiId}"
                            },
                            {
                                "ParameterKey": "ArtifactoryAppHome",
                                "ParameterValue": "${env.ArtifactoryAppHome}"
                            },
                            {
                                "ParameterKey": "ArtifactoryClusterHome",
                                "ParameterValue": "${env.ArtifactoryClusterHome}"
                            },
                            {
                                "ParameterKey":  "ArtifactoryClusterKey",
                                "ParameterValue":  "${env.ArtifactoryClusterKey}"
                            },
                            {
                                "ParameterKey":  "ArtifactoryClusterMaster",
                                "ParameterValue":  "${env.ArtifactoryClusterMaster}"
                            },
                            {
                                "ParameterKey": "ArtifactoryDbAdminPasswd",
                                "ParameterValue": "${env.ArtifactoryDbAdminPasswd}"
                            },
                            {
                                "ParameterKey": "ArtifactoryDbAdminUser",
                                "ParameterValue": "${env.ArtifactoryDbAdminUser}"
                            },
                            {
                                "ParameterKey": "ArtifactoryDbHostFqdn",
                                "ParameterValue": "${env.ArtifactoryDbHostFqdn}"
                            },
                            {
                                "ParameterKey": "ArtifactoryDbInstance",
                                "ParameterValue": "${env.ArtifactoryDbInstance}"
                            },
                            {
                                "ParameterKey": "ArtifactoryRepoUrl",
                                "ParameterValue": "${env.ArtifactoryRepoUrl}"
                            },
                            {
                                "ParameterKey": "ArtifactoryRpmName",
                                "ParameterValue": "${env.ArtifactoryRpmName}"
                            },
                            {
                                "ParameterKey": "ArtifactoryS3BakupLocs",
                                "ParameterValue": "${env.ArtifactoryS3BakupLocs}"
                            },
                            {
                                "ParameterKey": "ArtifactoryS3ShardLocs",
                                "ParameterValue": "${env.ArtifactoryS3ShardLocs}"
                            },
                            {
                                "ParameterKey": "ArtifactoryToolBucket",
                                "ParameterValue": "${env.ArtifactoryToolBucket}"
                            },
                            {
                                "ParameterKey": "CfnBootstrapUtilsUrl",
                                "ParameterValue": "${env.CfnBootstrapUtilsUrl}"
                            },
                            {
                                "ParameterKey": "CfnGetPipUrl",
                                "ParameterValue": "${env.CfnGetPipUrl}"
                            },
                            {
                                "ParameterKey": "CloudWatchAgentUrl",
                                "ParameterValue": "${env.CloudWatchAgentUrl}"
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
                                "ParameterKey": "InstanceType",
                                "ParameterValue": "${env.InstanceType}"
                            },
                            {
                                "ParameterKey": "KeyPairName",
                                "ParameterValue": "${env.KeyPairName}"
                            },
                            {
                                "ParameterKey": "NoPublicIp",
                                "ParameterValue": "${env.NoPublicIp}"
                            },
                            {
                                "ParameterKey": "NoReboot",
                                "ParameterValue": "${env.NoReboot}"
                            },
                            {
                                "ParameterKey": "NoUpdates",
                                "ParameterValue": "${env.NoUpdates}"
                            },
                            {
                                "ParameterKey": "PrivateIp",
                                "ParameterValue": "${env.PrivateIp}"
                            },
                            {
                                "ParameterKey": "ProvisionUser",
                                "ParameterValue": "${env.ProvisionUser}"
                            },
                            {
                                "ParameterKey": "PypiIndexUrl",
                                "ParameterValue": "${env.PypiIndexUrl}"
                            },
                            {
                                "ParameterKey": "RootVolumeSize",
                                "ParameterValue": "${env.RootVolumeSize}"
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
                                "ParameterKey": "ToggleCfnInitUpdate",
                                "ParameterValue": "${env.ToggleCfnInitUpdate}"
                            },
                            {
                                "ParameterKey": "WatchmakerAdminGroups",
                                "ParameterValue": "${env.WatchmakerAdminGroups}"
                            },
                            {
                                "ParameterKey": "WatchmakerAdminUsers",
                                "ParameterValue": "${env.WatchmakerAdminUsers}"
                            },
                            {
                                "ParameterKey": "WatchmakerComputerName",
                                "ParameterValue": "${env.WatchmakerComputerName}"
                            },
                            {
                                "ParameterKey": "WatchmakerConfig",
                                "ParameterValue": "${env.WatchmakerConfig}"
                            },
                            {
                                "ParameterKey": "WatchmakerEnvironment",
                                "ParameterValue": "${env.WatchmakerEnvironment}"
                            },
                            {
                                "ParameterKey": "WatchmakerOuPath",
                                "ParameterValue": "${env.WatchmakerOuPath}"
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
                        echo "Attempting to delete any active ${CfnStackRoot}-Ec2Res stacks... "
                        aws --region "${AwsRegion}" cloudformation delete-stack --stack-name "${CfnStackRoot}-Ec2Res" 

                        sleep 5

                        # Pause if delete is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-Ec2Res \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q DELETE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-Ec2Res to delete..."
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
                        echo "Attempting to create stack ${CfnStackRoot}-Ec2Res..."
                        aws --region "${AwsRegion}" cloudformation create-stack --stack-name "${CfnStackRoot}-Ec2Res" \
                          --disable-rollback --capabilities CAPABILITY_NAMED_IAM \
                          --template-url "${TemplateUrl}" \
                          --parameters file://EC2-Wam.parms.json
 
                        sleep 15
 
                        # Pause if create is slow
                        while [[ $(
                                    aws cloudformation describe-stacks \
                                      --stack-name ${CfnStackRoot}-Ec2Res \
                                      --query 'Stacks[].{Status:StackStatus}' \
                                      --out text 2> /dev/null | \
                                    grep -q CREATE_IN_PROGRESS
                                   )$? -eq 0 ]]
                        do
                           echo "Waiting for stack ${CfnStackRoot}-Ec2Res to finish create process..."
                           sleep 30
                        done
 
                        if [[ $(
                                aws cloudformation describe-stacks \
                                  --stack-name ${CfnStackRoot}-Ec2Res \
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

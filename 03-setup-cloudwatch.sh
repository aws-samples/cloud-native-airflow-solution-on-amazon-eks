#! /bin/bash

. ./99-set-env.sh

#CloudWatch Agent Configuration: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Observability-EKS-addon.html

ClusterName=${CLUSTER_NAME}
RegionName=${AWS_REGION}

aws iam attach-role-policy \
--role-name ${NODE_ROLE_NAME} \
--policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy  \ 
--policy-arn arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess

aws eks create-addon --addon-name amazon-cloudwatch-observability --cluster-name ${CLUSTER_NAME}
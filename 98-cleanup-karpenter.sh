#! /bin/bash

. ./99-set-env.sh

export KARPENTER_VERSION=v0.16.1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_DEFAULT_REGION=$AWS_REGION
echo $KARPENTER_VERSION $CLUSTER_NAME $AWS_DEFAULT_REGION $AWS_ACCOUNT_ID

eksctl delete iamserviceaccount \
  --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --namespace=karpenter \
  --name=karpenter

helm uninstall karpenter --namespace karpenter
#aws iam detach-role-policy --role-name="${CLUSTER_NAME}-karpenter" --policy-arn="arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}"
aws iam detach-role-policy --role-name="KarpenterNodeRole-${CLUSTER_NAME}" --policy-arn="arn:aws-cn:iam::aws:policy/CloudWatchAgentServerPolicy"
#aws iam delete-policy --policy-arn="arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}"
#aws iam delete-role --role-name="KarpenterNodeRole-${CLUSTER_NAME}"
aws cloudformation delete-stack --stack-name "Karpenter-${CLUSTER_NAME}"
aws ec2 describe-launch-templates \
    | jq -r ".LaunchTemplates[].LaunchTemplateName" \
    | grep -i "Karpenter-${CLUSTER_NAME}" \
    | xargs -I{} aws ec2 delete-launch-template --launch-template-name {}

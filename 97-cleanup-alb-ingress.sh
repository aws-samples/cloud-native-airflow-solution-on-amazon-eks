#! /bin/bash

. ./99-set-env.sh

helm uninstall aws-load-balancer-controller -n kube-system

eksctl delete iamserviceaccount \
  --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller-${CLUSTER_NAME}

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
sleep 30
aws iam delete-policy \
    --region $AWS_REGION \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}

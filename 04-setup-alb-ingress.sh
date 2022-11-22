#! /bin/bash

. ./99-set-env.sh

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME} \
    --policy-document file://resources/alb_iam_policy-cn.json

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
eksctl create iamserviceaccount \
  --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller-${CLUSTER_NAME} \
  --role-name "AmazonEKSLoadBalancerControllerRole-${CLUSTER_NAME}" \
  --attach-policy-arn=arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME} \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller-${CLUSTER_NAME} \
  --set image.repository=918309763551.dkr.ecr.cn-north-1.amazonaws.com.cn/amazon/aws-load-balancer-controller

#! /bin/bash

. ./99-set-env.sh

export KARPENTER_VERSION=v0.32.6
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_DEFAULT_REGION=$AWS_REGION

echo $KARPENTER_VERSION $CLUSTER_NAME $AWS_DEFAULT_REGION $AWS_ACCOUNT_ID

TEMPOUT=$(mktemp)

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

eksctl create iamidentitymapping \
  --username system:node:{{EC2PrivateDNSName}} \
  --cluster "${CLUSTER_NAME}" \
  --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --group system:bootstrappers \
  --group system:nodes


eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace karpenter \
  --role-name "${CLUSTER_NAME}-karpenter" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
  --role-only \
  --approve

export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"

helm repo add karpenter https://charts.karpenter.sh/
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Logout of helm registry to perform an unauthenticated pull against the public ECR
helm registry logout public.ecr.aws

# Installation of Karpenter (https://github.com/aws/karpenter-provider-aws/blob/main/charts/karpenter/README.md)

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace karpenter --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --set controller.resources.limits.memory=1Gi \
  --wait

# Installation of AWS Node Termination Handler (https://github.com/aws/aws-node-termination-handler)

helm upgrade --install --namespace aws-node-termination-handler --create-namespace \
  aws-node-termination-handler eks/aws-node-termination-handler \
    --set enableSpotInterruptionDraining="true" \
    --set enableRebalanceMonitoring="true" \
    --set enableRebalanceDraining="true" \
    --set enableScheduledEventDraining="true" \
    --set nodeSelector."karpenter\.sh/capacity-type"=spot

export NODE_SECURITY_GROUP=$(aws eks describe-cluster --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' \
    --output text)

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        name: default
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h # 30 * 24h = 720h
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
        Name: "eksctl-${CLUSTER_NAME}-cluster/SubnetPrivate*"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
        Name: "eks-cluster-sg-${CLUSTER_NAME}-*"
EOF


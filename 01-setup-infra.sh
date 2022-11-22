#! /bin/bash

#### Script Variables ########

CLUSTER_NAME=airflow
AWS_REGION=cn-north-1
NODEGROUP_NAME=ng-arm64-airflow
VPC_CIDR="10.1.0.0/16"


##############################
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
DB_PRIVATE_CIDR1="$(echo $VPC_CIDR | cut -d"." -f1-2).201.0/24"
DB_PRIVATE_CIDR2="$(echo $VPC_CIDR | cut -d"." -f1-2).202.0/24"

## create cluster

eksctl create cluster --name ${CLUSTER_NAME} \
  --region ${AWS_REGION}  --with-oidc \
  --version 1.23 --node-type m6g.xlarge \
  --alb-ingress-access --node-private-networking \
  --nodegroup-name ${NODEGROUP_NAME} --vpc-cidr ${VPC_CIDR} \
  --vpc-nat-mode HighlyAvailable

## add new private subnet for DB&EFS

vpc_id=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

DB_PRIVATE_SUBNET1=$(aws ec2 create-subnet \
    --vpc-id $vpc_id \
    --cidr-block $DB_PRIVATE_CIDR1 \
    --tag-specifications ResourceType=subnet,Tags="[{Key=Name,Value=${CLUSTER_NAME}-private-db-subnet1}]" \
    --availability-zone ${AWS_REGION}a \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)


DB_PRIVATE_SUBNET2=$(aws ec2 create-subnet \
    --vpc-id $vpc_id \
    --cidr-block $DB_PRIVATE_CIDR2 \
    --tag-specifications ResourceType=subnet,Tags="[{Key=Name,Value=${CLUSTER_NAME}-private-db-subnet2}]" \
    --availability-zone ${AWS_REGION}b \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)

## add CloudWach agent IAM policy

NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --nodegroup-name ${NODEGROUP_NAME} --query "nodegroup.nodeRole" --output text)
NODE_ROLE_NAME=$(echo $NODE_ROLE_ARN | sed -e 's/\//\n/g' | sed -e '2q;d')

aws iam attach-role-policy --role-name $NODE_ROLE_NAME \
  --policy-arn arn:aws-cn:iam::aws:policy/CloudWatchAgentServerPolicy

## ebs add-on aws-ebs-csi-driver

eksctl create addon --name aws-ebs-csi-driver --cluster ${CLUSTER_NAME} \
  --service-account-role-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole --force

## apply EFS CSI driver

aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://resources/efs-iam-policy-example.json

eksctl create iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --region ${AWS_REGION}

kubectl apply -f resources/efs-csi-driver.yaml


security_group_id=$(aws ec2 create-security-group \
    --group-name ${CLUSTER_NAME}EfsSecurityGroup \
    --description "${CLUSTER_NAME} EFS security group" \
    --region $AWS_REGION \
    --vpc-id $vpc_id \
    --output text)

aws ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $VPC_CIDR

file_system_id=$(aws efs create-file-system \
    --region $AWS_REGION \
    --encrypted \
    --performance-mode generalPurpose \
    --query 'FileSystemId' \
    --output text)

## create RDS Aurora PGSQL

db_security_group_id=$(aws ec2 create-security-group \
    --group-name ${CLUSTER_NAME}DbSecurityGroup \
    --description "${CLUSTER_NAME} DB security group" \
    --region $AWS_REGION \
    --vpc-id $vpc_id \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $db_security_group_id \
    --region $AWS_REGION \
    --protocol tcp \
    --port 5432 \
    --cidr $VPC_CIDR

aws rds create-db-subnet-group \
  --region $AWS_REGION \
  --db-subnet-group-name ${CLUSTER_NAME}-db-subnet-group \
  --db-subnet-group-description ${CLUSTER_NAME}-db-subnet-group \
  --subnet-ids ${DB_PRIVATE_SUBNET1} ${DB_PRIVATE_SUBNET2}

db_endpoint=$(aws rds create-db-cluster --region $AWS_REGION \
  --db-cluster-identifier ${CLUSTER_NAME}-db-cluster \
  --db-subnet-group-name ${CLUSTER_NAME}-db-subnet-group \
  --engine aurora-postgresql \
  --engine-version 14.3 \
  --master-username postgres \
  --master-user-password <YOUR_DATABASE_PASSWORD> \
  --storage-encrypted \
  --vpc-security-group-ids $db_security_group_id \
  --query 'DBCluster.Endpoint' --output text)

aws rds create-db-instance --region $AWS_REGION \
  --db-instance-identifier ${CLUSTER_NAME}-db-writer \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.xlarge \
  --db-cluster-identifier ${CLUSTER_NAME}-db-cluster

aws rds create-db-instance --region $AWS_REGION \
  --db-instance-identifier ${CLUSTER_NAME}-db-read01 \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.xlarge \
  --db-cluster-identifier ${CLUSTER_NAME}-db-cluster

## create elasticache redis

redis_security_group_id=$(aws ec2 create-security-group \
    --group-name ${CLUSTER_NAME}RedisSecurityGroup \
    --description "${CLUSTER_NAME} Redis security group" \
    --region $AWS_REGION \
    --vpc-id $vpc_id \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $redis_security_group_id \
    --region $AWS_REGION \
    --protocol tcp \
    --port 6379 \
    --cidr $VPC_CIDR

aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name "${CLUSTER_NAME}-redis-subnet-group" \
  --cache-subnet-group-description "${CLUSTER_NAME} subnet group" \
  --region $AWS_REGION \
  --subnet-ids ${DB_PRIVATE_SUBNET1} ${DB_PRIVATE_SUBNET2}

aws elasticache create-replication-group \
    --replication-group-id ${CLUSTER_NAME}-cache \
    --replication-group-description "${CLUSTER_NAME} group" \
    --region $AWS_REGION \
    --engine redis \
    --engine-version 6.2 \
    --cache-node-type cache.r6g.large \
    --multi-az-enabled \
    --replicas-per-node-group 1 \
    --security-group-ids $redis_security_group_id \
    --cache-subnet-group-name ${CLUSTER_NAME}-redis-subnet-group \
    --at-rest-encryption-enabled

aws elasticache wait replication-group-available \
  --region $AWS_REGION \
  --replication-group-id ${CLUSTER_NAME}-cache

elasti_endpoint=$(aws elasticache describe-replication-groups \
  --region $AWS_REGION \
  --replication-group-id ${CLUSTER_NAME}-cache \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' \
  --output text)

## create EFS mount target after DB creation avoid the FS not ready

aws efs create-mount-target \
  --file-system-id $file_system_id \
  --subnet-id $DB_PRIVATE_SUBNET1 \
  --security-groups $security_group_id \
  --region $AWS_REGION

aws efs create-mount-target \
  --file-system-id $file_system_id \
  --subnet-id $DB_PRIVATE_SUBNET2 \
  --security-groups $security_group_id \
  --region $AWS_REGION

file_access_id=$(aws efs create-access-point \
  --region $AWS_REGION \
  --file-system-id $file_system_id \
  --posix-user Uid=65533,Gid=65533 \
  --query 'AccessPointId' \
  --output text \
  --root-directory '{
        "Path": "/efs-dags",
        "CreationInfo": {
          "OwnerUid": 65533,
          "OwnerGid": 65533,
          "Permissions": "755"
        }
      }')


cat <<EOF > 99-set-env.sh
export CLUSTER_NAME=$CLUSTER_NAME
export AWS_REGION=$AWS_REGION
export NODEGROUP_NAME=$NODEGROUP_NAME
export VPC_CIDR=$VPC_CIDR
export EFS_FILESYSTEM_ID=$file_system_id
export NODE_ROLE_NAME=$NODE_ROLE_NAME
export DB_ENDPOINT=$db_endpoint
export ELASTI_ENDPOINT=$elasti_endpoint
export DB_PRIVATE_SUBNET1=$DB_PRIVATE_SUBNET1
export DB_PRIVATE_SUBNET2=$DB_PRIVATE_SUBNET2
export EFS_SECURITY_GROUP=$security_group_id
export DB_SECURITY_GROUP=$db_security_group_id
export ELASTI_SECURITY_GROUP=$redis_security_group_id
export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
export FILE_ACCESS_ID=$file_access_id
EOF

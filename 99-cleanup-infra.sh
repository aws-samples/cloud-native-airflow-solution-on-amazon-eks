#! /bin/bash

#### Script Variables ########
. 99-set-env.sh
##############################

aws efs delete-access-point --access-point-id $(aws efs describe-access-points --file-system-id $EFS_FILESYSTEM_ID --region $AWS_REGION --query 'AccessPoints[0].AccessPointId' --output text) --region $AWS_REGION
for mount_target in $(aws efs describe-mount-targets \
	    --file-system-id $EFS_FILESYSTEM_ID --region $AWS_REGION \
	    --query 'MountTargets[].MountTargetId' --output text)
do 
	aws efs delete-mount-target --mount-target-id $mount_target --region $AWS_REGION
done
aws rds delete-db-instance --db-instance-identifier ${CLUSTER_NAME}-db-read01 --delete-automated-backups --skip-final-snapshot --region $AWS_REGION
aws rds delete-db-instance --db-instance-identifier ${CLUSTER_NAME}-db-writer --delete-automated-backups --skip-final-snapshot --region $AWS_REGION
aws rds delete-db-cluster --db-cluster-identifier ${CLUSTER_NAME}-db-cluster --skip-final-snapshot --region $AWS_REGION

aws elasticache delete-replication-group --replication-group-id ${CLUSTER_NAME}-cache --region $AWS_REGION

aws rds wait db-cluster-deleted --db-cluster-identifier ${CLUSTER_NAME}-db-cluster --region $AWS_REGION
aws elasticache wait replication-group-deleted --replication-group-id ${CLUSTER_NAME}-cache --region $AWS_REGION
for s in $EFS_SECURITY_GROUP $DB_SECURITY_GROUP $ELASTI_SECURITY_GROUP
do
    aws ec2 delete-security-group --group-id $s --region $AWS_REGION
done

aws ec2 delete-subnet --subnet-id $DB_PRIVATE_SUBNET1 --region $AWS_REGION
aws ec2 delete-subnet --subnet-id $DB_PRIVATE_SUBNET2 --region $AWS_REGION
aws efs delete-file-system --file-system-id $EFS_FILESYSTEM_ID --region $AWS_REGION

aws rds delete-db-subnet-group --db-subnet-group-name ${CLUSTER_NAME}-db-subnet-group --region $AWS_REGION
aws elasticache delete-cache-subnet-group --cache-subnet-group-name "${CLUSTER_NAME}-redis-subnet-group" --region $AWS_REGION
aws iam detach-role-policy --role-name $NODE_ROLE_NAME --region $AWS_REGION --policy-arn arn:aws-cn:iam::aws:policy/CloudWatchAgentServerPolicy

eksctl delete cluster --name=$CLUSTER_NAME --region $AWS_REGION

rm -f 99-set-env.sh

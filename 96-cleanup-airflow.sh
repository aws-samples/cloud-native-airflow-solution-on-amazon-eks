#! /bin/bash

. ./99-set-env.sh

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

helm uninstall airflow -n airflow 
helm uninstall keda -n keda
kubectl delete sc efs-sc
kubectl delete pv efs-pv
kubectl delete namespace airflow
kubectl delete namespace keda

aws codecommit delete-repository \
  --region $AWS_REGION \
  --repository-name ${CLUSTER_NAME}-dags

aws logs delete-log-group --log-group-name /apache/airflow-logs --region $AWS_REGION

## CodeCommit cred should be 0, if have two will be 1
crd_id=$(aws iam list-service-specific-credentials \
  --region $AWS_REGION \
  --query 'ServiceSpecificCredentials[1].ServiceSpecificCredentialId' \
  --output text)

aws iam delete-service-specific-credential \
  --region $AWS_REGION \
  --service-specific-credential-id $crd_id

eksctl delete iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-scheduler

eksctl delete iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-webserver

eksctl delete iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-worker

eksctl delete iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-triggerer
sleep 30
aws iam delete-policy --policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AirflowConnectionPolicy-${CLUSTER_NAME} \
  --region $AWS_REGION

#! /bin/bash

. ./99-set-env.sh

## create IAM user CodeCommit cred
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws codecommit create-repository --repository-name ${CLUSTER_NAME}-dags --region $AWS_REGION
aws codecommit create-commit \
  --region $AWS_REGION \
  --author-name user \
  --email "user@abc.com" \
  --repository-name ${CLUSTER_NAME}-dags \
  --branch-name master \
  --put-files "filePath=readme.md,fileContent='Welcome to Airflow DAGs repository.'"

AWS_IAM_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
output=$(aws iam create-service-specific-credential --user-name $AWS_IAM_USER \
  --service-name codecommit.amazonaws.com \
  --query 'ServiceSpecificCredential.{user:ServiceUserName,password:ServicePassword}' \
  --output text)

export GIT_USER=$(echo $output | cut -d" " -f2)
export GIT_PASS=$(echo $output | cut -d" " -f1)


## create cloudwatch log group for Airflow
aws logs create-log-group --log-group-name /apache/airflow-logs --region $AWS_REGION

## create CRD for Airflow

kubectl create namespace airflow

cat <<EOF | kubectl apply -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_FILESYSTEM_ID}::${FILE_ACCESS_ID}
EOF

kubectl create secret generic airflow-db \
   -n airflow \
   --from-literal=connection=postgresql://postgres:<YOUR_DATABASE_PASSWORD>@${DB_ENDPOINT}:5432/postgres

kubectl create secret generic airflow-result-db \
   -n airflow \
   --from-literal=connection=db+postgresql://postgres:<YOUR_DATABASE_PASSWORD>@${DB_ENDPOINT}:5432/postgres

kubectl create secret generic git-credentials \
  -n airflow \
  --from-literal=GIT_SYNC_USERNAME="${GIT_USER}" \
  --from-literal=GIT_SYNC_PASSWORD="${GIT_PASS}"

kubectl create secret generic webserver-secret \
  -n airflow \
  --from-literal="webserver-secret-key=$(python3 -c 'import secrets; print(secrets.token_hex(16))')"

helm repo add apache-airflow https://airflow.apache.org
helm repo add kedacore https://kedacore.github.io/charts

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --version "v2.0.0" \
  --set image.keda.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn/kedacore/keda \
  --set image.keda.tag=v2.0.0-arm \
  --set image.metricsApiServer.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn/kedacore/keda-metrics-apiserver \
  --set image.metricsApiServer.tag=v2.0.0-arm64 --timeout 1m0s

cat resources/values.yaml.tpl | envsubst \
  | helm upgrade --install airflow apache-airflow/airflow \
    --version "1.6.0" --namespace airflow -f -

aws iam create-policy --policy-name AirflowConnectionPolicy-${CLUSTER_NAME} \
  --policy-document file://resources/airflow-iam-policy-example.json

eksctl create iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --role-name airflow-worker-${CLUSTER_NAME} \
    --name airflow-worker \
    --override-existing-serviceaccounts \
    --attach-policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AirflowConnectionPolicy-${CLUSTER_NAME} \
    --approve


eksctl create iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-scheduler \
    --role-name airflow-scheduler-${CLUSTER_NAME} \
    --override-existing-serviceaccounts \
    --attach-policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AirflowConnectionPolicy-${CLUSTER_NAME} \
    --approve

eksctl create iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-webserver \
    --role-name airflow-webserver-${CLUSTER_NAME} \
    --override-existing-serviceaccounts \
    --attach-policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AirflowConnectionPolicy-${CLUSTER_NAME} \
    --approve

eksctl create iamserviceaccount \
    --cluster ${CLUSTER_NAME} \
    --namespace airflow \
    --name airflow-triggerer \
    --role-name airflow-triggerer-${CLUSTER_NAME} \
    --override-existing-serviceaccounts \
    --attach-policy-arn arn:aws-cn:iam::${AWS_ACCOUNT_ID}:policy/AirflowConnectionPolicy-${CLUSTER_NAME} \
    --approve

## patch the pgbouncer deploy to ddelete no use exporter container
INDEX=$(kubectl get deploy/airflow-pgbouncer \
  -n airflow \
  -o=jsonpath="{.spec.template.spec.containers}" \
  | jq '. | map(.name=="metrics-exporter") | index(true)')

kubectl patch deploy/airflow-pgbouncer \
   -n airflow \
   --type json \
   -p="[{'op': 'remove', 'path': '/spec/template/spec/containers/$INDEX'}]"

## patch the worker image to hive and hadoop bin
# INDEX=$(kubectl get deploy/airflow-worker \
#   -n airflow \
#   -o=jsonpath="{.spec.template.spec.containers}" \
#   | jq '. | map(.name=="worker") | index(true)')

# kubectl patch deploy/airflow-worker \
#    -n airflow \
#    --type json \
#    -p="[{'op': 'replace', 
#         'path': '/spec/template/spec/containers/$INDEX/image',
#         'value': '${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn/apache/airflow:2.3.4-amazon-hadoop-hive-celery-statsd-slim-arm64'}]"

kubectl rollout restart -n airflow deploy/airflow-scheduler
kubectl rollout restart -n airflow deploy/airflow-webserver
kubectl rollout restart -n airflow deploy/airflow-triggerer

kubectl get pod -n airflow -w

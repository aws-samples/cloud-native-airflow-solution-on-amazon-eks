#! /bin/bash

export AWS_REGION=cn-north-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

docker build . -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn/apache/airflow:2.3.4-amazon-hive-celery-statsd-arm64

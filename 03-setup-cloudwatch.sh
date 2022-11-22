#! /bin/bash

. ./99-set-env.sh

#Cloud Watch Logs - Fluent Bit https://docs.aws.amazon.com/zh_cn/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html#Container-Insights-FluentBit-setup
#Cloud Watch Metrics https://docs.aws.amazon.com/zh_cn/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-metrics.html 

cat <<EOF | kubectl apply -f -
# create amazon-cloudwatch namespace
apiVersion: v1
kind: Namespace
metadata:
  name: amazon-cloudwatch
  labels:
    name: amazon-cloudwatch
EOF

cat <<EOF | kubectl apply -f -
# create configmap for cwagent config
apiVersion: v1
data:
  # Configuration is in Json format. No matter what configure change you make,
  # please keep the Json blob valid.
  cwagentconfig.json: |
    {
        "agent": {
            "region": "${AWS_REGION}"
        },
        "logs": {
            "metrics_collected": {
                "kubernetes": {
                    "cluster_name": "${CLUSTER_NAME}",
                    "metrics_collection_interval": 60
                }
            },
            "force_flush_interval": 5
        },
        "metrics": {
        	"namespace": "${CLUSTER_NAME}",
            "metrics_collected": {
                "statsd": {
                    "service_address": ":8125"
                }
            }
        }
    }
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
EOF

ClusterName=${CLUSTER_NAME}
RegionName=${AWS_REGION}
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
kubectl create configmap fluent-bit-cluster-info \
--from-literal=cluster.name=${ClusterName} \
--from-literal=http.server=${FluentBitHttpServer} \
--from-literal=http.port=${FluentBitHttpPort} \
--from-literal=read.head=${FluentBitReadFromHead} \
--from-literal=read.tail=${FluentBitReadFromTail} \
--from-literal=logs.region=${RegionName} -n amazon-cloudwatch


kubectl apply -f \
https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml


eksctl create iamserviceaccount \
    --cluster ${ClusterName} \
    --namespace amazon-cloudwatch \
    --name fluent-bit \
    --override-existing-serviceaccounts \
    --attach-policy-arn arn:aws-cn:iam::aws:policy/CloudWatchAgentServerPolicy \
    --approve

kubectl rollout restart -n amazon-cloudwatch daemonset.apps/fluent-bit

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml

kubectl apply -f resources/cwagent-daemonset.yaml
kubectl apply -f resources/cwagent-svc.yaml

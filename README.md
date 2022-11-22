# Cloud Native Airflow Solution on Amazon EKS

The solution is for deploying high reliable Apache Airflow(https://airflow.apache.org/) solution on AWS. And, the whole stack is based on Graviton2. 

##  Target Audience
Who needs 
- A One-Click Airflow Solution on Amazon EKS
- A High Available and Cloud Native Soltuion
- A Less Operation Effort solution via AWS managed service

## Technical Details

### The Airflow Components

In this solution, we deploy the following Airflow components:
- Web UI
- Scheduler(Celery)
- Worker
- KEDA, for Airflow AutoScaling(https://airflow.apache.org/docs/helm-chart/stable/keda.html)

Relevant Technical points used in the Airflow components:
- PgBouncer. If you are using PostgreSQL as your database, you will likely want to enable PgBouncer as well. Airflow can open a lot of database connections due to its distributed nature and using a connection pooler can significantly reduce the number of open connections on the database.(https://github.com/pgbouncer/pgbouncer)

- Git-Sync. Git-Sync is a simple command that pulls a git repository into a local directory. It is a perfect "sidecar" container in Kubernetes - it can periodically pull files down from a repository so that an application can consume them. (https://github.com/kubernetes/git-sync)


### Solution Architecture on AWS 


![](./images/architecture.png)

The architecture details:

1. To ensure high availability, this solution supports deployment in two availability zones.

2. Amazon VPC: Build a reliable and secure virtual network, and deploy the resources in the public subnet and private subnet in the VPC.

3. Amazon EKS: Use EKS to deploy the main components of Airflow, such as Web UI, Scheduler, Worker, etc. The underlying computing resources all use Graviton2 based EC2, and all the image sources of EKS are Amazon ECR. Karpenter automatically launches just the right EC2 resources to handle your Airflow applications.

4. Amazon Aurora for PostgreSQL: Use PostgreSQL as the metadata storage backend of Airflow, and choose the managed service Amazon Aurora for PostgreSQL as a database service, which reduces the time of daily operation and maintenance, and enhances availability and reliability.

5. Amazon ElastiCache for Redis: Use Redis as the Airflow message queue middleware, choose Amazon ElastiCache for Redis in this solution.

6. Amazon CodeCommit: Stores the code of the Airflow DAG.

7. Amazon EFS: DAG code sharing is realized through EFS, which also serves as the persistent storage of EKS.

8. Amazon CloudWatch: Two functions here, 1) Amazon CloudWatch Logs, collect Airflow logs through FluentBit, in addition to the Airflow UI, you can directly see the logs through Cloudwatch. 2) Container Insight collects relevant monitoring indicators.



## How to deploy
### Prerequisites

First, preparing ARM-based Docker images. You can start a Graviton2 EC2 instance as a bastion host. This instance has two functions, building your ARM images and deploying the following scripts. We have prepared the docker image's built scripts in the docker path. 
  
• Airflow, version 2.3.4  
• KEDA, version 2.0.0  
• PgBouncer, version 1.14.0  

For the Git-Sync, we donot prepare this, you can use the official Arm-Based image.If you are using MacOX, you can use the following command to check the image 
```
docker buildx imagetools inspect k8s.gcr.io/git-sync/git-sync:v3.4.0
```

Secondly, the solution is deployed in the China partition, so that we prepared some Kubernates resource files and replace the ARN or service endpoint in advance. The files are in the resources path, please use these files.

Finally, please install the following software on the bastion host:
• kubectl
• eksctl
• helm
• python3
• jq
• pip3


### Steps to set up Airflow cluster

We have prepared 6 bash scripts to deploy the Airflow environment:  

• 00-check-requirements.sh, checks the system environment  
• 01-setup-infra.sh, deploy the infrastructure in this solution, such as VPC, Amazon EKS Cluster, Amazon Aurora for PostgreSQL, Amazon ElastiCache for Redis, etc  
• 02-setup-karpenter.sh, deploy Karpenter on Amazon EKS, and dynamically expand new EC2 resources through Karpenter  
• 03-setup-cloudwatch.sh, deploy Amazon CloudWatch related resources, Airflow logs to CloudWatch, and metrics to Container Insight  
• 04-setup-alb-ingress.sh, which deploys an Amazon Application Load Balancer as an Apache Airflow web ingress  
• 05-setup-airflow.sh, deploy Apache Airflow on Amazon EKS  

Please follow the follwing steps to set up Airflow Cluster.

1. Set up an Graviton2 EC2 bastion host, this instance has two function.
    - Build your ARM images
    - Deploy the following Airflow stack 

2. Check your system requirement, prepare the relevant tools.
    - kubectl
    - eksctl 
    - helm 
    - python3  
    
   Run the bash script,  
   
     ```
        bash 00-check-requirements.sh
     ```     
     
3. Preapre the AWS infrastracture, including VPC, EKS, Aurora, ElastiCache and etc. This step takes around 40 minutes. Before running this script, please change Aurora password in line 132.  
      
    ```   
        bash 01-setup-infra.sh
    ```    
4. Set up Karpenter, Karpenter automatically launches just the right compute nodes to handle your EKS cluster's applications.  
      
    ```   
        bash 02-setup-karpenter.sh
    ```    
5. Set up CloudWatch for Airflow logs and metrics.  
    
    ```   
        bash 03-setup-cloudwatch.sh  
    ```    
6. Set up ALB ingress, Application Load Balancer (ALB) is provisioned that load balances traffic for Airflow Web UI.   
    ``` 
        bash 04-setup-alb-ingress.sh
    ```

7. Set up Airflow, before running this script, please change Aurora password in line 60 and 64 of 05-setup-airflow.sh. In the resources/values.yaml.custom, please change Airflow web console's password in line 892.  
      
    ``` 
        bash 05-setup-airflow.shh
    ```
    
After the above deployment, you can see the Airflow's components.  
![](./images/airflow-component.png)

### Use Apache Airflow

1. After the above deployment is completed, we go to EC2 ---> Load Balancers to find the entrance of the Airflow web interface.  

![](./images/airflow-ui-loadbalancer.png)

2. Enter the ALB's DNS address in the browser, and log in with the Airflow username and password you set during deployment.  

![](./images/airflow-ui.png)

3. Now there is no executable Dag file in our Airflow, we can upload dags/example_dag.py in our code to CodeCommit. For how to upload, please refer to Uploading files to Amazon CodeCommit(https://docs.aws.amazon.com/codecommit/latest/userguide/how-to-create-file.html). After uploading, we will see the Dag file in Airflow, click Trigger Dags to run.  

![](./images/airflow-dags.png)


## Limitations
1. The solution now supports Beijing Region 
2. The Airflow Cluster is created in the new VPC

# 📦 Commands Reference — Packages, Helm Charts & Configs Deployed

A complete record of every package installed, Helm chart deployed, kubectl config applied, and CLI command used throughout the MLOps pipeline build. Organized by phase for easy reference and reproduction.

---

## 📋 Table of Contents

1. [Local Development Setup](#1-local-development-setup)
2. [Phase 1 — DVC + S3](#2-phase-1--dvc--s3)
3. [Phase 2 — MLflow Infrastructure](#3-phase-2--mlflow-infrastructure)
4. [Phase 5 — CI/CD Tools](#4-phase-5--cicd-tools)
5. [Phase 6 — EKS Cluster](#5-phase-6--eks-cluster)
6. [Phase 7 — Prometheus + Grafana](#6-phase-7--prometheus--grafana)
7. [Phase 9.2 — IRSA Setup](#7-phase-92--irsa-setup)
8. [Phase 9.3 — Secrets Store CSI Driver](#8-phase-93--secrets-store-csi-driver)
9. [Phase 9.5 — OPA Gatekeeper](#9-phase-95--opa-gatekeeper)
10. [Phase 10 — Kafka + Redis](#10-phase-10--kafka--redis)
11. [Phase 12 — EBS CSI Driver + Airflow](#11-phase-12--ebs-csi-driver--airflow)
12. [Application Helm Deployments](#12-application-helm-deployments)
13. [Python Packages by Image](#13-python-packages-by-image)

---

## 1. Local Development Setup

### Homebrew Tools

```bash
brew install eksctl
brew install kubectl
brew install helm
brew install awscli
brew install colima
brew install docker
brew install docker-buildx

# Docker buildx plugin setup
mkdir -p ~/.docker/cli-plugins
ln -sf $(brew --prefix)/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx

# Start Colima (Docker runtime on Mac)
colima start

# Docker socket
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

### Python Virtual Environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip

# Install all dev dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### `requirements.txt` (full dev)

```
mlflow==2.22.0
scikit-learn==1.8.0
pandas==2.2.3
numpy==1.26.4
boto3==1.37.1
dvc[s3]==3.59.1
feast[redis,aws]==0.40.1
s3fs==2024.2.0
pyarrow==15.0.2
redis==5.0.1
confluent-kafka==2.3.0
requests==2.32.3
```

### `requirements-api.txt` (production API image)

```
fastapi==0.136.1
uvicorn==0.34.3
pydantic==2.11.4
mlflow-skinny==2.22.0
scikit-learn==1.8.0
numpy==1.26.4
pandas==2.2.3
boto3==1.37.1
prometheus-fastapi-instrumentator==7.1.0
prometheus-client==0.25.0
```

### `requirements-dev.txt` (CI/CD tests)

```
pytest==9.0.3
pytest-asyncio==1.3.0
httpx==0.28.1
prometheus-fastapi-instrumentator==7.1.0
prometheus-client==0.25.0
```

### `requirements-streaming.txt` (stream processor)

```
confluent-kafka==2.3.0
redis==5.0.1
requests==2.32.3
```

---

## 2. Phase 1 — DVC + S3

### DVC Installation & Setup

```bash
pip install dvc[s3]==3.59.1

# Initialize DVC in repo
dvc init

# Add S3 remote
dvc remote add -d myremote s3://churn-mlops-dvc-store
cat .dvc/config    # verify

# Track data
dvc add data/raw/churn.csv
git add data/raw/churn.csv.dvc .dvc/config .dvc/.gitignore
git commit -m "data: initialize DVC with S3 remote and track dataset"
git push origin main
dvc push    # upload data to S3

# Pull data on fresh machine
dvc pull
```

### S3 Bucket Created

```bash
aws s3 mb s3://churn-mlops-dvc-store --region us-east-1
aws s3 mb s3://churn-mlops-artifacts --region us-east-1
```

---

## 3. Phase 2 — MLflow Infrastructure

### EC2 + RDS + S3 (via setup-mlflow-infra.sh)

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16

# Create Security Groups
aws ec2 create-security-group --group-name mlflow-sg ...
aws ec2 create-security-group --group-name rds-sg ...

# Create RDS PostgreSQL
aws rds create-db-instance \
  --db-instance-identifier mlflow-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username mlflow \
  --master-user-password MLflow1234! \
  --allocated-storage 20 \
  --db-subnet-group-name mlflow-subnet-group

# Launch EC2 t3.small
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.small \
  --key-name mlflow-key

# Allocate and Associate Elastic IP
aws ec2 allocate-address --domain vpc
aws ec2 associate-address --instance-id i-0d3ebb196f1ed53b8 --allocation-id eipalloc-xxx
# Result: 98.86.0.163
```

### MLflow Server on EC2

```bash
# SSH into EC2
ssh -i mlflow-key.pem ec2-user@98.86.0.163

# Install on EC2
pip3 install mlflow boto3 psycopg2-binary --user

# Start MLflow server
mlflow server \
  --host 0.0.0.0 \
  --port 5000 \
  --backend-store-uri postgresql://mlflow:MLflow1234!@mlflow-db.c3o84wgsio2m.us-east-1.rds.amazonaws.com:5432/mlflow \
  --default-artifact-root s3://churn-mlops-artifacts \
  --gunicorn-opts "--timeout 120 -w 2" \
  --serve-artifacts
```

---

## 4. Phase 5 — CI/CD Tools

### ECR Repository Created

```bash
aws ecr create-repository \
  --repository-name churn-prediction-api \
  --region us-east-1

aws ecr create-repository \
  --repository-name churn-stream-processor \
  --region us-east-1

aws ecr create-repository \
  --repository-name churn-materialize \
  --region us-east-1
```

### Docker Build & Push (manual / CI does this automatically)

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  011528270076.dkr.ecr.us-east-1.amazonaws.com

# Build and push API image
docker buildx build \
  --platform linux/amd64 \
  -t 011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest \
  --push .

# Build and push stream processor
docker buildx build \
  --platform linux/amd64 \
  -f streaming/Dockerfile.streaming \
  -t 011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-stream-processor:latest \
  --push .

# Build and push materialize image
docker buildx build \
  --platform linux/amd64 \
  -f streaming/Dockerfile.materialize \
  -t 011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-materialize:latest \
  --push .
```

### GitHub Actions Secrets Set

```
AWS_ACCESS_KEY_ID     → set via GitHub UI
AWS_SECRET_ACCESS_KEY → set via GitHub UI
```

### `.trivyignore` file committed to repo

```
# OS CVEs with no available fix — accepted risk
# Add CVE IDs here as they are reviewed and accepted
```

---

## 5. Phase 6 — EKS Cluster

### eksctl Cluster Creation

```bash
# cluster.yaml committed to repo
eksctl create cluster -f cluster.yaml
# Creates: EKS 1.34, 3x t3.medium, managed nodegroup, us-east-1
# Takes: ~15 minutes
```

### `cluster.yaml` key config

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: churn-mlops
  region: us-east-1
  version: "1.34"
managedNodeGroups:
  - name: standard-workers
    instanceType: t3.medium
    desiredCapacity: 3
    minSize: 3
    maxSize: 3
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### VPC Peering (via setup-networking.sh)

```bash
# Create peering between churn-mlops-vpc and EKS VPC
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-0c08813ed92e2b022 \
  --peer-vpc-id $EKS_VPC_ID \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID

# Add routes in both VPCs
aws ec2 create-route \
  --route-table-id rtb-0aa03046d2eddd459 \
  --destination-cidr-block $EKS_CIDR \
  --vpc-peering-connection-id $PEERING_ID

aws ec2 create-route \
  --route-table-id $EKS_RT_ID \
  --destination-cidr-block 10.0.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID
```

### AWS Load Balancer Controller (for ALB)

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=churn-mlops \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 6. Phase 7 — Prometheus + Grafana

### Helm Repo Added

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### kube-prometheus-stack Installation

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --version 45.7.1
```

### Chart Details

| Property | Value |
|----------|-------|
| Chart | `prometheus-community/kube-prometheus-stack` |
| Version | 45.7.1 |
| Namespace | `monitoring` |
| Grafana password | `admin123` |
| Grafana service | `LoadBalancer` |

### ServiceMonitor Applied

```bash
# Applied via Helm chart template
# helm/churn-mlops/templates/servicemonitor.yaml
# Namespace: monitoring
# Port: http (named port — required by ServiceMonitor)
```

---

## 7. Phase 9.2 — IRSA Setup

### One-time IAM Setup (setup-iam.sh)

```bash
# Create S3 policy
aws iam create-policy \
  --policy-name churn-mlops-s3-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::churn-mlops-artifacts",
        "arn:aws:s3:::churn-mlops-artifacts/*",
        "arn:aws:s3:::churn-mlops-dvc-store",
        "arn:aws:s3:::churn-mlops-dvc-store/*"
      ]
    }]
  }'

# Create Secrets Manager policy
aws iam create-policy \
  --policy-name churn-mlops-secrets-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
      "Resource": "arn:aws:iam::011528270076:secret:churn-mlops/*"
    }]
  }'

# Create IAM role (trust policy updated daily with new OIDC ID)
aws iam create-role \
  --role-name churn-mlops-irsa-role \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-arn arn:aws:iam::011528270076:policy/churn-mlops-s3-policy

aws iam attach-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-arn arn:aws:iam::011528270076:policy/churn-mlops-secrets-policy

# Store MLflow URI in Secrets Manager
aws secretsmanager create-secret \
  --name churn-mlops/mlflow-tracking-uri \
  --secret-string '{"MLFLOW_TRACKING_URI":"http://10.0.1.225:5000"}'
```

### Daily OIDC Association (setup-networking.sh Step 1.5)

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster churn-mlops \
  --approve \
  --region us-east-1

# Get new OIDC ID and update trust policy
OIDC_ID=$(aws eks describe-cluster \
  --name churn-mlops --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's/.*\///')

aws iam update-assume-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-document "{ ...trust policy with new $OIDC_ID... }"
```

### VPC CNI Network Policy Controller (setup-networking.sh Step 1.6)

```bash
aws eks update-addon \
  --cluster-name churn-mlops \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}' \
  --region us-east-1
```

---

## 8. Phase 9.3 — Secrets Store CSI Driver

### Helm Installation

```bash
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true
```

### AWS Provider Installation

```bash
# Applied via kubectl (not Helm)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

### CSIDriver Patch (CRITICAL — required for IRSA)

```bash
kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
```

### Versions

| Component | Version |
|-----------|---------|
| secrets-store-csi-driver | latest (Helm) |
| aws-provider-installer | latest (kubectl) |

---

## 9. Phase 9.5 — OPA Gatekeeper

### Helm Installation

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace
```

### ConstraintTemplates Applied (kubectl — in repo)

```bash
kubectl apply -f k8s/gatekeeper/constraint-templates.yaml
# Templates: K8sNoRoot, K8sRequireLimits, K8sNoPrivileged

# WAIT for CRDs before applying Constraints
kubectl wait --for=condition=established --timeout=60s \
  crd/k8snorootcontainers.constraints.gatekeeper.sh \
  crd/k8srequirelimits.constraints.gatekeeper.sh \
  crd/k8snoprivileged.constraints.gatekeeper.sh

kubectl apply -f k8s/gatekeeper/constraints.yaml
# Constraints scoped to namespace: churn-mlops
```

| Component | Chart | Version |
|-----------|-------|---------|
| OPA Gatekeeper | `gatekeeper/gatekeeper` | latest |
| Namespace | `gatekeeper-system` | — |

---

## 10. Phase 10 — Kafka + Redis

### Strimzi Operator (Kafka)

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update

helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace \
  --version 1.0.0 \
  --set watchNamespaces="{kafka}"
```

### Kafka Cluster Applied (kubectl — in repo)

```bash
# Kafka 4.1.0 KRaft mode (no Zookeeper)
kubectl apply -f k8s/kafka/kafka-cluster.yaml
# KafkaNodePool: 1 replica, combined controller+broker roles

kubectl apply -f k8s/kafka/kafka-topics.yaml
# Topics: customer-events, churn-alerts (3 partitions, replicas:1, retention 24h)

# Wait for Kafka to be ready
kubectl wait kafka/churn-kafka \
  --for=condition=Ready \
  --timeout=300s \
  -n kafka
```

### Redis (Bitnami)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install redis bitnami/redis \
  --namespace redis \
  --create-namespace \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0
```

### Stream Processor Deployment (kubectl — in repo)

```bash
kubectl apply -f k8s/stream-processor-deployment.yaml
# Namespace: churn-mlops
# Image: churn-stream-processor:latest
# ServiceAccount: churn-prediction-sa (IRSA)
# Uses ALB URL (not ClusterIP — VPC CNI eBPF workaround)
```

| Component | Chart | Version |
|-----------|-------|---------|
| Strimzi Operator | `strimzi/strimzi-kafka-operator` | 1.0.0 |
| Kafka | Strimzi CRD (KRaft) | 4.1.0 |
| Redis | `bitnami/redis` | latest |

---

## 11. Phase 12 — EBS CSI Driver + Airflow

### EBS CSI Driver

```bash
# Install EBS CSI addon
aws eks create-addon \
  --cluster-name churn-mlops \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1

# Wait until active
aws eks wait addon-active \
  --cluster-name churn-mlops \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1

# Attach EBS policy to node role
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`) && contains(RoleName, `churn-mlops`)].RoleName' \
  --output text)

aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

### StorageClass Applied (kubectl)

```bash
kubectl apply -f - << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate
parameters:
  type: gp2
EOF
```

### Airflow

```bash
helm repo add apache-airflow https://airflow.apache.org
helm repo update

kubectl create namespace airflow --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --set executor=KubernetesExecutor \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.username=admin \
  --set webserver.defaultUser.password=admin123 \
  --set webserver.defaultUser.email=admin@example.com \
  --set webserver.defaultUser.firstName=Admin \
  --set webserver.defaultUser.lastName=User \
  --set webserver.defaultUser.role=Admin \
  --set dags.persistence.enabled=false \
  --set dags.gitSync.enabled=true \
  --set dags.gitSync.repo=https://github.com/Himanshu9001/MLOps-Projects.git \
  --set dags.gitSync.branch=main \
  --set dags.gitSync.subPath=dags \
  --set dags.gitSync.wait=60 \
  --set postgresql.primary.persistence.storageClass=ebs-sc \
  --set triggerer.persistence.storageClassName=ebs-sc \
  --timeout 10m
```

### Airflow RBAC (kubectl)

```bash
kubectl apply -f - << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: airflow-pod-launcher
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: airflow-pod-launcher-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: airflow-pod-launcher
subjects:
  - kind: ServiceAccount
    name: airflow-scheduler
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-worker
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-triggerer
    namespace: airflow
EOF
```

| Component | Chart | Version |
|-----------|-------|---------|
| Airflow | `apache-airflow/airflow` | 3.2.0 |
| EBS CSI Driver | EKS Addon | latest |
| Namespace | `airflow` | — |

---

## 12. Application Helm Deployments

### Churn Prediction API (custom Helm chart in repo)

```bash
helm upgrade --install churn-mlops helm/churn-mlops/ \
  --namespace churn-mlops \
  --create-namespace \
  --values helm/churn-mlops/values.yaml \
  --set image.repository=011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api \
  --set image.tag=latest \
  --set irsa.roleArn=arn:aws:iam::011528270076:role/churn-mlops-irsa-role
```

### Helm Chart Templates in Repo (`helm/churn-mlops/templates/`)

| Template | What it creates |
|----------|----------------|
| `namespace.yaml` | `churn-mlops` namespace |
| `serviceaccount.yaml` | `churn-prediction-sa` with IRSA annotation |
| `deployment.yaml` | FastAPI deployment (HPA-aware replica logic) |
| `service.yaml` | LoadBalancer service (named port `http`) |
| `hpa.yaml` | HPA: min 1, max 3, CPU 70%, Memory 80% |
| `secretproviderclass.yaml` | AWS Secrets Manager CSI mapping |
| `servicemonitor.yaml` | Prometheus scrape config (namespace: monitoring) |
| `networkpolicies.yaml` | 5 network policies (default-deny + allow rules) |

---

## 13. Python Packages by Image

### `churn-prediction-api` — FastAPI serving

```
fastapi==0.136.1
uvicorn==0.34.3
pydantic==2.11.4
mlflow-skinny==2.22.0
scikit-learn==1.8.0
numpy==1.26.4
pandas==2.2.3
boto3==1.37.1
prometheus-fastapi-instrumentator==7.1.0
prometheus-client==0.25.0
```

### `churn-stream-processor` — Kafka consumer

```
confluent-kafka==2.3.0
redis==5.0.1
requests==2.32.3
```

### `churn-materialize` — Feature materialization (Airflow task)

```
numpy==1.26.4      # MUST be first — pins ABI for pyarrow
boto3==1.37.1
pandas==2.2.3
redis==5.0.1
pyarrow==15.0.2    # compatible with numpy 1.26.x
```

---

## 14. All Helm Repos Added

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add eks https://aws.github.io/eks-charts
helm repo add apache-airflow https://airflow.apache.org
helm repo update
```

---

## 15. All Namespaces Created

```bash
kubectl create namespace churn-mlops    # prediction API, stream processor
kubectl create namespace monitoring     # Prometheus, Grafana
kubectl create namespace kafka          # Strimzi operator, Kafka cluster
kubectl create namespace redis          # Bitnami Redis
kubectl create namespace gatekeeper-system  # OPA Gatekeeper
kubectl create namespace airflow        # Airflow components
```

---

## 16. Quick Reference — Helm List

```bash
helm list -A
# EXPECTED OUTPUT:
# NAME                    NAMESPACE          CHART
# churn-mlops             churn-mlops        churn-mlops-0.1.0
# prometheus              monitoring         kube-prometheus-stack-45.7.1
# csi-secrets-store       kube-system        secrets-store-csi-driver-x.x.x
# gatekeeper              gatekeeper-system  gatekeeper-x.x.x
# strimzi-kafka-operator  kafka              strimzi-kafka-operator-1.0.0
# redis                   redis              redis-x.x.x
# airflow                 airflow            airflow-3.2.0
```

---

*This document records every package, version, and command used to build the full MLOps pipeline. Use this as a reproduction guide for setting up the project from scratch.*
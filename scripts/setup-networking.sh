#!/bin/bash
set -e

echo "🚀 Setting up VPC Peering and networking..."

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
OUR_VPC_ID="vpc-0c08813ed92e2b022"
OUR_PUBLIC_RT="rtb-0aa03046d2eddd459"
MLFLOW_SG="sg-074ac7bb25004abe5"
REGION="us-east-1"
CLUSTER_NAME="churn-mlops"

# ─────────────────────────────────────────
# Step 1 — Get EKS VPC ID
# ─────────────────────────────────────────
echo "📡 Getting EKS VPC ID..."
EKS_VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)
echo "✅ EKS VPC: $EKS_VPC_ID"

# ─────────────────────────────────────────
# Step 1.5 — Associate OIDC provider + update IRSA trust policy
# ─────────────────────────────────────────
echo "🔗 Associating OIDC provider with cluster..."
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

OIDC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d'/' -f5)
echo "✅ OIDC ID: $OIDC_ID"

echo "🔄 Updating IRSA trust policy with new OIDC ID..."
cat > /tmp/churn-mlops-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::011528270076:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:churn-mlops:churn-prediction-sa",
          "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
aws iam update-assume-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-document file:///tmp/churn-mlops-trust-policy.json
echo "✅ IRSA trust policy updated!"

# ─────────────────────────────────────────
# Step 1.6 — Enable VPC CNI Network Policy Controller
# ─────────────────────────────────────────
echo "🔒 Enabling VPC CNI Network Policy Controller..."
aws eks update-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}' \
  --region $REGION > /dev/null
aws eks wait addon-active \
  --cluster-name $CLUSTER_NAME \
  --addon-name vpc-cni \
  --region $REGION
echo "✅ Network Policy Controller enabled!"

# ─────────────────────────────────────────
# Step 2 — Get EKS VPC CIDR and route tables
# ─────────────────────────────────────────
EKS_CIDR=$(aws ec2 describe-vpcs \
  --vpc-ids $EKS_VPC_ID \
  --query 'Vpcs[0].CidrBlock' \
  --output text \
  --region $REGION)
echo "✅ EKS CIDR: $EKS_CIDR"

EKS_ROUTE_TABLES=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$EKS_VPC_ID" \
  --query 'RouteTables[*].RouteTableId' \
  --output text \
  --region $REGION)
echo "✅ EKS Route Tables: $EKS_ROUTE_TABLES"

# ─────────────────────────────────────────
# Step 3 — Create VPC Peering
# ─────────────────────────────────────────
echo "🔗 Creating VPC Peering..."
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $OUR_VPC_ID \
  --peer-vpc-id $EKS_VPC_ID \
  --region $REGION \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=churn-mlops-peering}]' \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)
echo "✅ Peering ID: $PEERING_ID"

sleep 5

# ─────────────────────────────────────────
# Step 4 — Accept VPC Peering
# ─────────────────────────────────────────
echo "✅ Accepting VPC Peering..."
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id $PEERING_ID \
  --region $REGION > /dev/null
echo "✅ Peering accepted!"

sleep 10

# ─────────────────────────────────────────
# Step 5 — Add route our VPC → EKS VPC
# ─────────────────────────────────────────
echo "🛣️  Adding route our VPC → EKS VPC..."
aws ec2 create-route \
  --route-table-id $OUR_PUBLIC_RT \
  --destination-cidr-block $EKS_CIDR \
  --vpc-peering-connection-id $PEERING_ID \
  --region $REGION > /dev/null 2>&1 || \
aws ec2 replace-route \
  --route-table-id $OUR_PUBLIC_RT \
  --destination-cidr-block $EKS_CIDR \
  --vpc-peering-connection-id $PEERING_ID \
  --region $REGION > /dev/null
echo "✅ Route added/updated in our VPC!"

# ─────────────────────────────────────────
# Step 6 — Add routes EKS VPC → our VPC
# ─────────────────────────────────────────
echo "🛣️  Adding routes in EKS VPC → our VPC..."
for rtb in $EKS_ROUTE_TABLES; do
  aws ec2 create-route \
    --route-table-id $rtb \
    --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PEERING_ID \
    --region $REGION > /dev/null 2>&1 && \
  echo "  ✅ Route added to $rtb" || \
  aws ec2 replace-route \
    --route-table-id $rtb \
    --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PEERING_ID \
    --region $REGION > /dev/null 2>&1 && \
  echo "  ✅ Route replaced in $rtb" || \
  echo "  ℹ️  Route already up to date in $rtb"
done

# ─────────────────────────────────────────
# Step 7 — Update MLflow security group
# ─────────────────────────────────────────
echo "🔒 Updating MLflow security group..."
aws ec2 authorize-security-group-ingress \
  --group-id $MLFLOW_SG \
  --protocol tcp \
  --port 5000 \
  --cidr $EKS_CIDR \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  Rule already exists - skipping"
echo "✅ MLflow SG updated!"

# ─────────────────────────────────────────
# Step 8 — Attach S3 policy to EKS node role
# ─────────────────────────────────────────
echo "🔑 Attaching S3 policy to EKS node role..."
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`) && contains(RoleName, `churn-mlops`)].RoleName' \
  --output text)
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
echo "✅ S3 policy attached to $NODE_ROLE!"

# ─────────────────────────────────────────
# Step 9 — Update kubeconfig
# ─────────────────────────────────────────
echo "⚙️  Updating kubeconfig..."
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION
echo "✅ kubeconfig updated!"

# ─────────────────────────────────────────
# Step 10 — Deploy to Kubernetes via Helm
# ─────────────────────────────────────────
echo "🚢 Deploying to Kubernetes via Helm..."
helm upgrade --install churn-mlops helm/churn-mlops/ \
  --values helm/churn-mlops/values.yaml \
  --wait \
  --timeout 5m
echo "✅ Deployed to Kubernetes!"

# ─────────────────────────────────────────
# Step 11 — Install Prometheus + Grafana
# ─────────────────────────────────────────
echo "📊 Installing Prometheus + Grafana..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null 2>&1 || true
helm repo update > /dev/null
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/monitoring/values.yaml
echo "✅ Prometheus + Grafana installed!"

# ─────────────────────────────────────────
# Step 11.5 — Install Secrets Store CSI Driver + AWS Provider
# ─────────────────────────────────────────
echo "🔐 Installing Secrets Store CSI Driver..."
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts > /dev/null 2>&1 || true
helm repo update > /dev/null
helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --wait

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
echo "✅ Secrets Store CSI Driver installed!"

# ─────────────────────────────────────────
# Step 11.6 — Install OPA Gatekeeper
# ─────────────────────────────────────────
echo "🔒 Installing OPA Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts > /dev/null 2>&1 || true
helm repo update > /dev/null
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --wait \
  --timeout 5m

kubectl apply -f k8s/gatekeeper/constraint-templates.yaml
kubectl wait --for=condition=established \
  crd/k8snoroot.constraints.gatekeeper.sh \
  crd/k8srequirelimits.constraints.gatekeeper.sh \
  crd/k8snoprivileged.constraints.gatekeeper.sh \
  --timeout=60s
kubectl apply -f k8s/gatekeeper/constraints.yaml
echo "✅ OPA Gatekeeper installed!"

# ─────────────────────────────────────────
# Step 11.7 — Install Kafka (Strimzi)
# ─────────────────────────────────────────
echo "📨 Installing Kafka via Strimzi..."
helm repo add strimzi https://strimzi.io/charts/ > /dev/null 2>&1 || true
helm repo update > /dev/null
helm upgrade --install strimzi strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace \
  --wait \
  --timeout 5m

echo "⏳ Waiting for Strimzi CRDs to register..."
kubectl wait --for=condition=established \
  crd/kafkas.kafka.strimzi.io \
  --timeout=60s

kubectl apply -f k8s/kafka/kafka-cluster.yaml
kubectl wait kafka/churn-kafka \
  --for=condition=Ready \
  --timeout=5m \
  -n kafka

kubectl apply -f k8s/kafka/kafka-topics.yaml
echo "✅ Kafka installed!"

# ─────────────────────────────────────────
# Step 11.8 — Install Redis
# ─────────────────────────────────────────
echo "📦 Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami > /dev/null 2>&1 || true
helm repo update > /dev/null
helm upgrade --install redis bitnami/redis \
  --namespace redis \
  --create-namespace \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0 \
  --wait \
  --timeout 5m
echo "✅ Redis installed!"

# ─────────────────────────────────────────
# Step 11.9 — Deploy stream processor
# ─────────────────────────────────────────
echo "🌊 Deploying stream processor..."
kubectl apply -f k8s/stream-processor-deployment.yaml
echo "✅ Stream processor deployed!"

# ─────────────────────────────────────────
# Step 11.10 — Install EBS CSI Driver + StorageClass
# ─────────────────────────────────────────
echo "💾 Installing EBS CSI Driver..."
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION > /dev/null 2>&1 || echo "  ℹ️  EBS CSI addon already exists"

aws eks wait addon-active \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION

# Attach EBS policy to node role
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`) && contains(RoleName, `churn-mlops`)].RoleName' \
  --output text)
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true

kubectl apply -f - << 'SCEOF'
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
SCEOF
echo "✅ EBS CSI Driver installed!"

# ─────────────────────────────────────────
# Step 11.11 — Install Airflow
# ─────────────────────────────────────────
echo "🌬️  Installing Airflow..."
helm repo add apache-airflow https://airflow.apache.org > /dev/null 2>&1 || true
helm repo update > /dev/null
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

# Apply RBAC for airflow-worker to spawn pods
kubectl apply -f - << 'RBACEOF'
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
RBACEOF
echo "✅ Airflow installed!"

# ─────────────────────────────────────────
# Step 12 — Apply ServiceMonitor
# ─────────────────────────────────────────
echo "📡 Applying ServiceMonitor..."
kubectl apply -f k8s/servicemonitor.yaml
echo "✅ ServiceMonitor applied!"

echo ""
echo "✅ All done! Networking setup complete."
echo "📝 EKS VPC: $EKS_VPC_ID"
echo "📝 Peering: $PEERING_ID"
echo "📝 EKS CIDR: $EKS_CIDR"
echo ""
echo "⏳ Wait 2-3 minutes for LoadBalancer DNS to propagate..."
echo "Then run: kubectl get svc -n churn-mlops"
echo "Then run: kubectl get svc -n monitoring | grep grafana"

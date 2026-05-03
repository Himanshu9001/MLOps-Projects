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

# Patch CSIDriver to enable service account token projection for IRSA
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

# Apply ConstraintTemplates and wait for CRDs before applying Constraints
kubectl apply -f k8s/gatekeeper/constraint-templates.yaml
kubectl wait --for=condition=established \
  crd/k8snoroot.constraints.gatekeeper.sh \
  crd/k8srequirelimits.constraints.gatekeeper.sh \
  crd/k8snoprivileged.constraints.gatekeeper.sh \
  --timeout=60s
kubectl apply -f k8s/gatekeeper/constraints.yaml
echo "✅ OPA Gatekeeper installed!"

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


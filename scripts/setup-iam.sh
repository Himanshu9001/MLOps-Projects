#!/bin/bash
set -e

echo "🔐 Setting up IAM resources for IRSA + Secrets Manager (one-time setup)..."

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
REGION="us-east-1"
ACCOUNT_ID="011528270076"
CLUSTER_NAME="churn-mlops"

# ─────────────────────────────────────────
# Step 1 — Create S3 policy
# ─────────────────────────────────────────
echo "📋 Creating S3 policy..."
cat > /tmp/churn-mlops-s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ChurnMLOpsS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::churn-mlops-artifacts",
        "arn:aws:s3:::churn-mlops-artifacts/*",
        "arn:aws:s3:::churn-mlops-dvc-store",
        "arn:aws:s3:::churn-mlops-dvc-store/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name churn-mlops-s3-policy \
  --policy-document file:///tmp/churn-mlops-s3-policy.json \
  --description "Least-privilege S3 access for churn-mlops EKS pods via IRSA" \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  S3 policy already exists - skipping"
echo "✅ S3 policy ready!"

# ─────────────────────────────────────────
# Step 2 — Create Secrets Manager policy
# ─────────────────────────────────────────
echo "📋 Creating Secrets Manager policy..."
cat > /tmp/churn-mlops-secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ChurnMLOpsSecretsAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:011528270076:secret:churn-mlops/*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name churn-mlops-secrets-policy \
  --policy-document file:///tmp/churn-mlops-secrets-policy.json \
  --description "Secrets Manager access for churn-mlops EKS pods" \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  Secrets policy already exists - skipping"
echo "✅ Secrets Manager policy ready!"

# ─────────────────────────────────────────
# Step 3 — Store secret in Secrets Manager
# ─────────────────────────────────────────
echo "🔑 Storing MLflow URI in Secrets Manager..."
aws secretsmanager create-secret \
  --name churn-mlops/mlflow-tracking-uri \
  --description "MLflow tracking server URI for churn-mlops EKS pods" \
  --secret-string '{"MLFLOW_TRACKING_URI":"http://10.0.1.225:5000"}' \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  Secret already exists - skipping"
echo "✅ Secret stored in Secrets Manager!"

# ─────────────────────────────────────────
# Step 4 — Get OIDC ID and create IAM role
# ─────────────────────────────────────────
echo "🔗 Fetching OIDC ID from cluster..."
OIDC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d'/' -f5)
echo "  OIDC ID: $OIDC_ID"

echo "📋 Creating IRSA trust policy..."
cat > /tmp/churn-mlops-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:churn-mlops:churn-prediction-sa",
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

echo "🔑 Creating IRSA role..."
aws iam create-role \
  --role-name churn-mlops-irsa-role \
  --assume-role-policy-document file:///tmp/churn-mlops-trust-policy.json \
  --description "IRSA role for churn-mlops EKS pods - scoped to churn-prediction-sa ServiceAccount" \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  IRSA role already exists - skipping"

# ─────────────────────────────────────────
# Step 5 — Attach policies to role
# ─────────────────────────────────────────
echo "📎 Attaching policies to IRSA role..."
aws iam attach-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/churn-mlops-s3-policy 2>/dev/null || true

aws iam attach-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/churn-mlops-secrets-policy 2>/dev/null || true
echo "✅ Policies attached!"

echo ""
echo "✅ IAM setup complete!"
echo "📝 IRSA Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/churn-mlops-irsa-role"
echo "📝 Run this script once per AWS account - IAM resources persist across cluster recreations"

# ─────────────────────────────────────────
# Step 6 — Harden node role (run after cluster creation)
# Removes broad policies, attaches minimal scoped policies
# ─────────────────────────────────────────
harden_node_role() {
  echo "🔒 Hardening EKS node role..."
  NODE_ROLE=$(aws iam list-roles \
    --query 'Roles[?contains(RoleName, `NodeInstanceRole`) && contains(RoleName, `churn-mlops`)].RoleName' \
    --output text)

  echo "  Node role: $NODE_ROLE"

  # Remove overly broad policies
  aws iam detach-role-policy \
    --role-name $NODE_ROLE \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

  aws iam detach-role-policy \
    --role-name $NODE_ROLE \
    --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess 2>/dev/null || true

  # Create minimal autoscaler policy if not exists
  aws iam create-policy \
    --policy-name churn-mlops-cluster-autoscaler-policy \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ],
        "Resource": "*"
      }]
    }' 2>/dev/null || echo "  ℹ️  Autoscaler policy already exists"

  # Attach minimal autoscaler policy
  aws iam attach-role-policy \
    --role-name $NODE_ROLE \
    --policy-arn arn:aws:iam::011528270076:policy/churn-mlops-cluster-autoscaler-policy 2>/dev/null || true

  echo "✅ Node role hardened!"
}

harden_node_role

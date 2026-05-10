#!/bin/bash
set -e

echo "🧹 Tearing down networking before cluster deletion..."

REGION="us-east-1"
MLFLOW_SG="sg-074ac7bb25004abe5"

# Delete VPC Peering connections
echo "🔗 Deleting VPC Peering connections..."
PEERING_IDS=$(aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=active" \
            "Name=tag:Name,Values=churn-mlops-peering" \
  --query 'VpcPeeringConnections[*].VpcPeeringConnectionId' \
  --output text \
  --region $REGION)

for pcx in $PEERING_IDS; do
  aws ec2 delete-vpc-peering-connection \
    --vpc-peering-connection-id $pcx \
    --region $REGION > /dev/null
  echo "  ✅ Deleted peering $pcx"
done

echo "✅ Networking teardown complete!"
echo "Now safe to run: eksctl delete cluster --name churn-mlops --region us-east-1"

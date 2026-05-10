#!/bin/bash
set -e

echo "🛑 Stopping MLflow Infrastructure (preserving data)..."

REGION="us-east-1"
RDS_IDENTIFIER="mlflow-db"

# Stop EC2
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=mlflow-server" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region $REGION)

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
  echo "🛑 Stopping EC2 instance..."
  aws ec2 stop-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION > /dev/null
  echo "✅ EC2 stopped!"
fi

# Stop RDS
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_IDENTIFIER \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region $REGION 2>/dev/null || echo "not-found")

if [ "$RDS_STATUS" == "available" ]; then
  echo "🛑 Stopping RDS instance..."
  aws rds stop-db-instance \
    --db-instance-identifier $RDS_IDENTIFIER \
    --region $REGION > /dev/null
  echo "✅ RDS stopped!"
fi

echo ""
echo "✅ MLflow infrastructure stopped. Data preserved in S3 and RDS."
echo "Run ./scripts/setup-mlflow-infra.sh to start again."

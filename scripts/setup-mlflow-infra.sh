#!/bin/bash
set -e

echo "🚀 Setting up MLflow Infrastructure (EC2 + RDS + S3)..."

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
REGION="us-east-1"
VPC_ID="vpc-0c08813ed92e2b022"
PUBLIC_SUBNET="subnet-08394271e54785340"
PRIVATE_SUBNET_1="subnet-095a2844b2809bf7d"
PRIVATE_SUBNET_2="subnet-0cf890022b3095da4"
MLFLOW_SG="sg-074ac7bb25004abe5"
RDS_SG="sg-0739203d5a0bf9426"
ARTIFACTS_BUCKET="churn-mlops-artifacts"
RDS_IDENTIFIER="mlflow-db"
EC2_INSTANCE_NAME="mlflow-server"
KEY_NAME="mlflow-key"

# ─────────────────────────────────────────
# Step 1 — Create S3 bucket for artifacts
# ─────────────────────────────────────────
echo "🪣 Creating S3 artifacts bucket..."
aws s3 mb s3://$ARTIFACTS_BUCKET --region $REGION 2>/dev/null || \
  echo "  ℹ️  Bucket already exists - skipping"
echo "✅ S3 bucket ready: $ARTIFACTS_BUCKET"

# ─────────────────────────────────────────
# Step 2 — Create RDS subnet group
# ─────────────────────────────────────────
echo "🗄️  Creating RDS subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name mlflow-subnet-group \
  --db-subnet-group-description "MLflow RDS subnet group" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --region $REGION > /dev/null 2>&1 || \
  echo "  ℹ️  Subnet group already exists - skipping"
echo "✅ RDS subnet group ready!"

# ─────────────────────────────────────────
# Step 3 — Create RDS PostgreSQL
# ─────────────────────────────────────────
echo "🗄️  Checking RDS instance..."
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_IDENTIFIER \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region $REGION 2>/dev/null || echo "not-found")

if [ "$RDS_STATUS" == "not-found" ]; then
  echo "  Creating RDS PostgreSQL..."
  aws rds create-db-instance \
    --db-instance-identifier $RDS_IDENTIFIER \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 15 \
    --master-username mlflow \
    --master-user-password MLflow1234! \
    --allocated-storage 20 \
    --db-name mlflow \
    --db-subnet-group-name mlflow-subnet-group \
    --vpc-security-group-ids $RDS_SG \
    --no-multi-az \
    --no-publicly-accessible \
    --region $REGION > /dev/null
  echo "  ⏳ Waiting for RDS to be available (5-10 min)..."
  aws rds wait db-instance-available \
    --db-instance-identifier $RDS_IDENTIFIER \
    --region $REGION
elif [ "$RDS_STATUS" == "stopped" ]; then
  echo "  Starting existing RDS instance..."
  aws rds start-db-instance \
    --db-instance-identifier $RDS_IDENTIFIER \
    --region $REGION > /dev/null
  echo "  ⏳ Waiting for RDS to be available..."
  aws rds wait db-instance-available \
    --db-instance-identifier $RDS_IDENTIFIER \
    --region $REGION
else
  echo "  ℹ️  RDS already running (status: $RDS_STATUS)"
fi

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_IDENTIFIER \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $REGION)
echo "✅ RDS ready: $RDS_ENDPOINT"

# ─────────────────────────────────────────
# Step 4 — Create IAM role for EC2
# ─────────────────────────────────────────
echo "🔑 Setting up IAM role for EC2..."
aws iam create-role \
  --role-name mlflow-ec2-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' > /dev/null 2>&1 || echo "  ℹ️  IAM role already exists"

aws iam attach-role-policy \
  --role-name mlflow-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

aws iam create-instance-profile \
  --instance-profile-name mlflow-ec2-profile > /dev/null 2>&1 || \
  echo "  ℹ️  Instance profile already exists"

aws iam add-role-to-instance-profile \
  --instance-profile-name mlflow-ec2-profile \
  --role-name mlflow-ec2-role 2>/dev/null || true

echo "✅ IAM role ready!"
sleep 10

# ─────────────────────────────────────────
# Step 5 — Create EC2 key pair
# ─────────────────────────────────────────
echo "🔐 Setting up EC2 key pair..."
if [ ! -f ~/.ssh/$KEY_NAME.pem ]; then
  aws ec2 create-key-pair \
    --key-name $KEY_NAME \
    --region $REGION \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/$KEY_NAME.pem
  chmod 400 ~/.ssh/$KEY_NAME.pem
  echo "✅ Key pair created: ~/.ssh/$KEY_NAME.pem"
else
  echo "  ℹ️  Key pair already exists locally"
fi

# ─────────────────────────────────────────
# Step 6 — Check/Create EC2 instance
# ─────────────────────────────────────────
echo "🖥️  Checking EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region $REGION 2>/dev/null)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
  echo "  Creating EC2 instance..."

  # Get latest Amazon Linux 2023 AMI
  AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region $REGION)

  # Create user data script
  cat > /tmp/mlflow-userdata.sh << USERDATA
#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install mlflow boto3 psycopg2-binary --user
mkdir -p /opt/mlflow
chmod 777 /opt/mlflow
cat > /opt/mlflow/start.sh << 'SCRIPT'
#!/bin/bash
export PATH=\$PATH:/home/ec2-user/.local/bin
mlflow server --backend-store-uri postgresql://mlflow:MLflow1234!@${RDS_ENDPOINT}:5432/mlflow --default-artifact-root s3://${ARTIFACTS_BUCKET} --host 0.0.0.0 --port 5000 --gunicorn-opts "--timeout 120 -w 2"
SCRIPT
chmod +x /opt/mlflow/start.sh
cat > /etc/systemd/system/mlflow.service << 'SERVICE'
[Unit]
Description=MLflow Tracking Server
After=network.target
[Service]
Type=simple
User=ec2-user
ExecStart=/opt/mlflow/start.sh
Restart=always
RestartSec=10
Environment=HOME=/home/ec2-user
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable mlflow
systemctl start mlflow
USERDATA

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.small \
    --key-name $KEY_NAME \
    --security-group-ids $MLFLOW_SG \
    --subnet-id $PUBLIC_SUBNET \
    --user-data file:///tmp/mlflow-userdata.sh \
    --iam-instance-profile Name=mlflow-ec2-profile \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_INSTANCE_NAME}]" \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

  echo "  ⏳ Waiting for EC2 to be running..."
  aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $REGION
else
  # Start if stopped
  EC2_STATE=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text \
    --region $REGION)

  if [ "$EC2_STATE" == "stopped" ]; then
    echo "  Starting stopped EC2 instance..."
    aws ec2 start-instances \
      --instance-ids $INSTANCE_ID \
      --region $REGION > /dev/null
    aws ec2 wait instance-running \
      --instance-ids $INSTANCE_ID \
      --region $REGION
  else
    echo "  ℹ️  EC2 already running"
  fi
fi

# ─────────────────────────────────────────
# Step 7 — Attach Elastic IP
# ─────────────────────────────────────────
echo "🌐 Setting up Elastic IP..."
EIP=$(aws ec2 describe-addresses \
  --filters "Name=instance-id,Values=$INSTANCE_ID" \
  --query 'Addresses[0].PublicIp' \
  --output text \
  --region $REGION 2>/dev/null)

if [ "$EIP" == "None" ] || [ -z "$EIP" ]; then
  ALLOC_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --region $REGION \
    --query 'AllocationId' \
    --output text)
  aws ec2 associate-address \
    --instance-id $INSTANCE_ID \
    --allocation-id $ALLOC_ID \
    --region $REGION > /dev/null
  EIP=$(aws ec2 describe-addresses \
    --allocation-ids $ALLOC_ID \
    --query 'Addresses[0].PublicIp' \
    --output text \
    --region $REGION)
  echo "✅ New Elastic IP allocated: $EIP"
else
  echo "  ℹ️  Elastic IP already attached: $EIP"
fi

echo ""
echo "✅ MLflow Infrastructure ready!"
echo "📝 RDS Endpoint:  $RDS_ENDPOINT"
echo "📝 EC2 Public IP: $EIP"
echo "📝 MLflow URL:    http://$EIP:5000"
echo "📝 S3 Bucket:     s3://$ARTIFACTS_BUCKET"
echo ""
echo "⏳ Wait 2-3 minutes for MLflow to start on EC2..."
echo "Then check: curl http://$EIP:5000/health"
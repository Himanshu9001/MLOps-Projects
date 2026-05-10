#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# userdata.sh.tpl - MLflow EC2 first-boot provisioning script
#
# Rendered by templatefile() in main.tf with actual values substituted.
# Variables: ${mlflow_port}, ${rds_endpoint}, ${artifacts_bucket},
#            ${region}, ${db_secret_arn}
#
# SECURITY UPGRADE (Phase 20 cleanup):
#   Before: RDS password hardcoded in connection string
#           → password visible in EC2 userdata (stored in instance metadata)
#           → password visible in AWS Console userdata view
#
#   After:  Password fetched from Secrets Manager at MLflow startup
#           → userdata contains only the secret ARN (not the value)
#           → MLflow startup script fetches password at runtime
#           → automatic resilience to AWS 7-day password rotation
#           → no plaintext password anywhere in EC2 configuration
#
# Runs as root on first boot only.
# ─────────────────────────────────────────────────────────────────────────────
set -euxo pipefail

# ── System update + Python setup ──────────────────────────────────────────────
dnf update -y
dnf install -y python3 python3-pip jq

# Install MLflow and dependencies as ec2-user (not root).
# psycopg2-binary: PostgreSQL adapter — required for RDS backend store.
# boto3: AWS SDK — required for S3 artifact store + Secrets Manager reads.
sudo -u ec2-user pip3 install --user \
  mlflow==2.22.0 \
  boto3 \
  psycopg2-binary

# ── MLflow startup script ─────────────────────────────────────────────────────
mkdir -p /opt/mlflow

# UPGRADED: fetch password from Secrets Manager at startup
# Before: password hardcoded → breaks on AWS 7-day rotation
# After:  fetched fresh on every MLflow restart → resilient to rotation
#
# Secret format from manage_master_user_password:
#   {"username":"mlflow","password":"<generated>","engine":"postgres",...}
cat > /opt/mlflow/start.sh << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/home/ec2-user/.local/bin
export AWS_DEFAULT_REGION=${region}

# Fetch current password from Secrets Manager
# This runs on every MLflow start — picks up rotated passwords automatically
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --region "${region}" \
  --query SecretString \
  --output text)

DB_PASSWORD=$(echo "$DB_SECRET" | jq -r '.password')
DB_USERNAME=$(echo "$DB_SECRET" | jq -r '.username')

mlflow server \
  --backend-store-uri "postgresql://$${DB_USERNAME}:$${DB_PASSWORD}@${rds_endpoint}:5432/mlflow" \
  --default-artifact-root "s3://${artifacts_bucket}" \
  --host 0.0.0.0 \
  --port ${mlflow_port} \
  --gunicorn-opts "--timeout 120 -w 2"
SCRIPT

chmod +x /opt/mlflow/start.sh

# ── Systemd service ───────────────────────────────────────────────────────────
# Restart=always ensures MLflow restarts after password rotation events.
# Each restart fetches the latest password from Secrets Manager.
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

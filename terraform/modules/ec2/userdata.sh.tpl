#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# userdata.sh.tpl - MLflow EC2 first-boot provisioning script
#
# Rendered by templatefile() in main.tf with actual values substituted.
# Variables: ${mlflow_port}, ${rds_endpoint}, ${rds_password},
#            ${artifacts_bucket}, ${region}
#
# Runs as root on first boot only.
# Installs MLflow, configures systemd service, starts MLflow server.
# ─────────────────────────────────────────────────────────────────────────────
set -euxo pipefail

# ── System update + Python setup ──────────────────────────────────────────────
dnf update -y
dnf install -y python3 python3-pip

# Install MLflow and dependencies as ec2-user (not root).
# psycopg2-binary: PostgreSQL adapter for Python - required for RDS backend store.
# boto3: AWS SDK - required for S3 artifact store reads/writes.
sudo -u ec2-user pip3 install --user \
  mlflow==2.22.0 \
  boto3 \
  psycopg2-binary

# ── MLflow startup script ─────────────────────────────────────────────────────
mkdir -p /opt/mlflow

cat > /opt/mlflow/start.sh << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/home/ec2-user/.local/bin
export AWS_DEFAULT_REGION=${region}

mlflow server \
  --backend-store-uri postgresql://mlflow:${rds_password}@${rds_endpoint}:5432/mlflow \
  --default-artifact-root s3://${artifacts_bucket} \
  --host 0.0.0.0 \
  --port ${mlflow_port} \
  --gunicorn-opts "--timeout 120 -w 2"
SCRIPT

chmod +x /opt/mlflow/start.sh

# ── Systemd service ───────────────────────────────────────────────────────────
# Systemd ensures MLflow restarts automatically:
#   - After EC2 stop/start (Restart=always)
#   - After process crash (RestartSec=10 avoids tight restart loops)
#   - On instance reboot (WantedBy=multi-user.target)
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

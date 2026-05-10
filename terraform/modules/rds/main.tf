# ─────────────────────────────────────────────────────────────────────────────
# modules/rds/main.tf
#
# SECURITY UPGRADE (Phase 20 cleanup):
#   Before: password = var.db_password
#           → plaintext password written to Terraform state file in S3
#           → anyone with s3:GetObject on state bucket reads the password
#
#   After:  manage_master_user_password = true
#           → AWS generates password and stores it in Secrets Manager
#           → Terraform state contains only the secret ARN, never the value
#           → AWS rotates password automatically every 7 days
#           → MLflow reads password from Secrets Manager at startup
#
# NOTE: Applying this change to an existing RDS instance requires:
#   1. terraform apply → RDS switches to Secrets Manager-managed password
#   2. Update MLflow EC2 userdata to read password from Secrets Manager
#      instead of hardcoded connection string
#   3. Restart MLflow service on EC2
#
# The old var.db_password variable is kept for reference but no longer
# used by the RDS resource. It is kept in variables.tf with a deprecation
# comment so CI/CD does not break (TF_VAR_DB_PASSWORD still set in GitHub).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "rds"
    },
    var.additional_tags
  )

  identifier = "${var.project}-${var.environment}-mlflow-db"
}

resource "aws_db_subnet_group" "mlflow" {
  name        = "${var.project}-${var.environment}-mlflow-subnet-group"
  description = "MLflow RDS subnet group - private subnets"
  subnet_ids  = var.subnet_ids

  tags = merge(local.base_tags, {
    Name = "${var.project}-${var.environment}-mlflow-subnet-group"
  })
}

resource "aws_db_instance" "mlflow" {
  identifier = local.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username

  # UPGRADED: manage_master_user_password = true
  # AWS generates a strong random password and stores it in Secrets Manager
  # at: arn:aws:secretsmanager:<region>:<account>:secret:rds!db-<identifier>
  # Terraform state contains only the secret ARN — never the password value.
  # AWS rotates the password automatically every 7 days.
  #
  # BEFORE (insecure):
  #   password = var.db_password
  #   → plaintext written to terraform.tfstate → readable by anyone with s3:GetObject
  #
  # AFTER (secure):
  #   manage_master_user_password = true
  #   → password lives only in Secrets Manager → requires secretsmanager:GetSecretValue
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 5

  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = var.security_group_ids

  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days

  backup_window      = "03:00-04:00"
  maintenance_window = "Mon:04:00-Mon:05:00"

  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  performance_insights_enabled = true

  tags = merge(local.base_tags, {
    Name = local.identifier
  })

  lifecycle {
    # Password managed by AWS — ignore any drift on this attribute
    ignore_changes = [password]
  }
}

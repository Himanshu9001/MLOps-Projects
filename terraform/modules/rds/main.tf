# ─────────────────────────────────────────────────────────────────────────────
# modules/rds/main.tf
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
  password = var.db_password

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
    ignore_changes = [password]
  }
}

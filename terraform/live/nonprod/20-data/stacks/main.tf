# ─────────────────────────────────────────────────────────────────────────────
# 20-data/stacks/main.tf
#
# Creates: S3 buckets, RDS PostgreSQL, ElastiCache Redis.
# Reads networking outputs from 10-network remote state.
#
# Apply command:
#   terraform init -backend-config=../backends/backend.hcl
#   terraform apply -var-file=../params/main.tfvars
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  backend "s3" {}

  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── Read networking outputs from 10-network ───────────────────────────────────

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/10-network/terraform.tfstate"
    region = var.region
  }
}

# ── S3 ────────────────────────────────────────────────────────────────────────

module "s3" {
  source = "../../../../modules/s3"

  environment                    = var.environment
  project                        = var.project
  region                         = var.region
  enable_versioning              = var.enable_versioning
  noncurrent_version_expiry_days = var.noncurrent_version_expiry_days
  force_destroy                  = var.force_destroy
}

# ── RDS ───────────────────────────────────────────────────────────────────────

module "rds" {
  source = "../../../../modules/rds"

  environment         = var.environment
  project             = var.project
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password
  instance_class      = var.rds_instance_class
  engine_version      = "15"
  allocated_storage   = 20
  multi_az            = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention
  skip_final_snapshot = var.rds_skip_final_snapshot
  deletion_protection = var.rds_deletion_protection

  # From 10-network remote state
  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [data.terraform_remote_state.network.outputs.rds_sg_id]
}

# ── ElastiCache ───────────────────────────────────────────────────────────────

module "elasticache" {
  source = "../../../../modules/elasticache"

  environment              = var.environment
  project                  = var.project
  node_type                = var.redis_node_type
  engine_version           = var.redis_engine_version
  snapshot_retention_limit = var.redis_snapshot_retention
  port                     = 6379

  # From 10-network remote state
  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids = [data.terraform_remote_state.network.outputs.elasticache_sg_id]
}

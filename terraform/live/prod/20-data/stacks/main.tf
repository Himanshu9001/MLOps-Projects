# ─────────────────────────────────────────────────────────────────────────────
# prod/20-data/stacks/main.tf
#
# Prod differences from nonprod:
#   - RDS: db.t3.small, multi_az=true, backup_retention=7, deletion_protection=true
#   - ElastiCache: cache.t3.small, snapshot_retention=1
#   - S3: noncurrent_version_expiry_days=90
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

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/10-network/terraform.tfstate"
    region = var.region
  }
}

module "s3" {
  source = "../../../../modules/s3"

  environment                    = var.environment
  project                        = var.project
  region                         = var.region
  enable_versioning              = var.enable_versioning
  noncurrent_version_expiry_days = var.noncurrent_version_expiry_days
  force_destroy                  = var.force_destroy
}

module "rds" {
  source = "../../../../modules/rds"

  environment           = var.environment
  project               = var.project
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  instance_class        = var.rds_instance_class
  engine_version        = "15"
  allocated_storage     = 20
  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention
  skip_final_snapshot   = var.rds_skip_final_snapshot
  deletion_protection   = var.rds_deletion_protection
  subnet_ids            = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids    = [data.terraform_remote_state.network.outputs.rds_sg_id]
}

module "elasticache" {
  source = "../../../../modules/elasticache"

  environment              = var.environment
  project                  = var.project
  node_type                = var.redis_node_type
  engine_version           = var.redis_engine_version
  snapshot_retention_limit = var.redis_snapshot_retention
  port                     = 6379
  subnet_ids               = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids       = [data.terraform_remote_state.network.outputs.elasticache_sg_id]
}

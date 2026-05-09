# ─────────────────────────────────────────────────────────────────────────────
# 00-s3-backend/stacks/main.tf
#
# Creates the Terraform remote state infrastructure:
#   1. S3 bucket for state files (one prefix per stack)
#   2. DynamoDB table for state locking (prevents concurrent applies)
#
# Uses LOCAL backend - state stored in terraform.tfstate in this directory.
# All other stacks use S3 backend pointing at the bucket created here.
#
# Apply command (from this directory):
#   terraform init
#   terraform apply -var-file=../params/main.tfvars
#
# S3 state key structure after all stacks are applied:
#   churn-mlops-nonprod-terraform-state/
#     nonprod/10-network/terraform.tfstate
#     nonprod/20-data/terraform.tfstate
#     nonprod/30-compute/terraform.tfstate
#     nonprod/40-kubernetes/terraform.tfstate
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  # LOCAL backend for bootstrap stack only.
  # No backend block = defaults to local.
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  # Dedicated state bucket - separate from MLflow artifacts bucket.
  # Keeps Terraform state isolated from application data.
  state_bucket_name = "${var.project}-${var.environment}-terraform-state"
  lock_table_name   = "${var.project}-${var.environment}-terraform-locks"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "terraform-state"
  }
}

# ─────────────────────────────────────────
# S3 State Bucket
# ─────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  # force_destroy false - never accidentally destroy state bucket.
  # If you need to delete it, manually empty it first.
  force_destroy = false

  tags = merge(local.tags, {
    Name = local.state_bucket_name
  })
}

# State files contain sensitive data: resource IDs, IPs, passwords.
# Block all public access unconditionally.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning on state bucket - critical.
# If a bad apply corrupts state, you can roll back to previous state version.
# Without versioning a corrupted state file means manual state surgery.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ─────────────────────────────────────────
# DynamoDB Lock Table
#
# Prevents two engineers (or two CI jobs) from running terraform apply
# against the same stack simultaneously - which causes state corruption.
# Terraform writes a lock entry before apply, deletes it after.
# If apply crashes, lock stays - use terraform force-unlock to clear.
# ─────────────────────────────────────────

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  # LockID is the required partition key name - Terraform hardcodes this.
  # Do not change.
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-time recovery - allows restoring lock table to any point in
  # last 35 days. Protects against accidental table deletion.
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.tags, {
    Name = local.lock_table_name
  })
}

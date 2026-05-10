# ─────────────────────────────────────────────────────────────────────────────
# 00-s3-backend/stacks/main.tf
#
# Creates the Terraform remote state infrastructure:
#   1. KMS key for state file encryption (upgraded from AES256)
#   2. S3 bucket for state files (one prefix per stack)
#   3. DynamoDB table for state locking (prevents concurrent applies)
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
#
# SECURITY UPGRADE (Phase 20 cleanup):
#   AES256 (S3-managed keys) → SSE-KMS (customer-managed key)
#   Before: s3:GetObject alone is sufficient to read state + plaintext secrets
#   After:  requires BOTH s3:GetObject AND kms:Decrypt — two separate IAM
#           permissions needed, different principals can hold each
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
# KMS Key for State Encryption
#
# WHY KMS over AES256:
#   AES256 = AWS holds the key, anyone with s3:GetObject reads plaintext state
#   KMS    = you control the key, reader needs BOTH s3:GetObject + kms:Decrypt
#
# Two separate IAM permissions = two separate blast radius boundaries:
#   - Compromised S3 policy alone → cannot decrypt state
#   - Compromised KMS policy alone → cannot access S3 objects
#   - Both required simultaneously → attacker needs deeper access
#
# enable_key_rotation = true: AWS rotates the key material annually.
# Old ciphertext remains decryptable (AWS retains old key versions).
# New data encrypted with new key material automatically.
# ─────────────────────────────────────────

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for ${var.project}-${var.environment} Terraform state encryption"
  deletion_window_in_days = 10   # minimum allowed by AWS
  enable_key_rotation     = true # annual auto-rotation, best practice

  # Key policy: allows the account root full control.
  # Restrict further by adding specific IAM role ARNs here in production.
  # Default policy = account root can manage, all IAM policies apply normally.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-terraform-state-key"
  })
}

# Human-readable alias — easier to identify in AWS console than key ID
resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project}-${var.environment}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# Required for KMS key policy — get current account ID dynamically
data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────
# S3 State Bucket
# ─────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name
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
# If a bad apply corrupts state, roll back to previous state version.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# UPGRADED: AES256 → SSE-KMS
# Before: sse_algorithm = "AES256" — S3-managed key, no separate access control
# After:  sse_algorithm = "aws:kms" — customer-managed key, separate IAM boundary
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    # bucket_key_enabled reduces KMS API calls by ~99% by caching the
    # data encryption key at the bucket level — significant cost saving
    # at scale, no security trade-off
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
  hash_key = "LockID"

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

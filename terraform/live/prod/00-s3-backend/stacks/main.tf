# ─────────────────────────────────────────────────────────────────────────────
# prod/00-s3-backend/stacks/main.tf
#
# Identical logic to nonprod - creates prod-scoped state bucket + lock table.
# Prod state is completely isolated from nonprod state.
# A corrupted nonprod state never affects prod apply operations.
#
# SECURITY: SSE-KMS encryption (same as nonprod upgrade)
#
# Apply command (from this directory):
#   terraform init
#   terraform apply -var-file=../params/main.tfvars
# ─────────────────────────────────────────────────────────────────────────────

terraform {
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
}

locals {
  state_bucket_name = "${var.project}-${var.environment}-terraform-state"
  lock_table_name   = "${var.project}-${var.environment}-terraform-locks"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "terraform-state"
  }
}

data "aws_caller_identity" "current" {}

# KMS key for prod state — separate from nonprod key
# Prod and nonprod state buckets use different KMS keys:
# compromising one environment's key does not affect the other
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for ${var.project}-${var.environment} Terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

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

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project}-${var.environment}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  force_destroy = false

  tags = merge(local.tags, { Name = local.state_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

# SSE-KMS — upgraded from AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery { enabled = true }

  tags = merge(local.tags, { Name = local.lock_table_name })
}

# ─────────────────────────────────────────────────────────────────────────────
# modules/s3/main.tf
#
# Creates two new S3 buckets:
#   1. artifacts bucket - MLflow models, plots, SHAP outputs,
#                         Great Expectations reports, Feast registry + parquet
#   2. dvc bucket       - DVC content-addressable data cache
#
# Both buckets are brand new - no import.
# Naming includes environment to avoid collision with existing buckets.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "s3"
    },
    var.additional_tags
  )

  # churn-mlops-nonprod-artifacts, churn-mlops-prod-artifacts
  artifacts_bucket_name = "${var.project}-${var.environment}-artifacts"

  # churn-mlops-nonprod-dvc-store, churn-mlops-prod-dvc-store
  dvc_bucket_name = "${var.project}-${var.environment}-dvc-store"
}

# ─────────────────────────────────────────
# MLflow Artifacts Bucket
# ─────────────────────────────────────────

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifacts_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.base_tags, {
    Name    = local.artifacts_bucket_name
    Purpose = "mlflow-artifacts"
  })
}

# Block all public access.
# MLflow artifacts contain model weights, training data, PII-adjacent features.
# No legitimate use case for public access to this bucket.
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# AES256 server-side encryption at rest.
# Required for any bucket holding ML artifacts or data with potential PII.
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # Enables S3 bucket keys - reduces KMS API calls by 99% if you later
    # upgrade to SSE-KMS. No cost, no downside, enable now.
    bucket_key_enabled = true
  }
}

# Lifecycle: expire old object versions to control storage cost.
# Without this, every model version uploaded stays forever.
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  # depends_on required - AWS requires versioning to be fully enabled
  # before a lifecycle config that references noncurrent versions is applied.
  depends_on = [aws_s3_bucket_versioning.artifacts]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    # Empty filter = applies to all objects in bucket.
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiry_days
    }

    # Clean up delete markers left behind after versioned object deletions.
    # Without this, delete markers accumulate and inflate object count.
    expiration {
      expired_object_delete_marker = true
    }
  }
}

# ─────────────────────────────────────────
# DVC Data Store Bucket
# ─────────────────────────────────────────

resource "aws_s3_bucket" "dvc" {
  bucket        = local.dvc_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.base_tags, {
    Name    = local.dvc_bucket_name
    Purpose = "dvc-data-store"
  })
}

resource "aws_s3_bucket_public_access_block" "dvc" {
  bucket = aws_s3_bucket.dvc.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "dvc" {
  bucket = aws_s3_bucket.dvc.id

  versioning_configuration {
    # DVC handles its own versioning via content-addressable .dvc pointer files.
    # S3 versioning here is an additional recovery layer on top of DVC - if a
    # dvc push accidentally overwrites a cached file, S3 version history saves it.
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dvc" {
  bucket = aws_s3_bucket.dvc.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dvc" {
  bucket = aws_s3_bucket.dvc.id

  depends_on = [aws_s3_bucket_versioning.dvc]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiry_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# modules/s3/variables.tf
#
# Creates NEW S3 buckets for parallel infrastructure.
# Naming: ${project}-${environment}-artifacts, ${project}-${environment}-dvc-store
# Example: churn-mlops-nonprod-artifacts, churn-mlops-nonprod-dvc-store
#
# Existing buckets (churn-mlops-artifacts, churn-mlops-dvc-store) are NOT
# touched. After blue-green cutover and sanity testing, existing bucket data
# will be synced to new buckets via aws s3 sync before DNS/config cutover.
#
# Called by: live/nonprod/20-data and live/prod/20-data
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Deployment environment. Included in bucket names."

  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be 'nonprod' or 'prod'."
  }
}

variable "project" {
  type        = string
  description = "Project name prefix. Example: churn-mlops"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project))
    error_message = "project must be lowercase alphanumeric + hyphens."
  }
}

variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "force_destroy" {
  # true  = terraform destroy deletes all objects before destroying bucket.
  # false = destroy fails if bucket non-empty - safe default.
  # Set true in nonprod only - allows clean teardown during development.
  # NEVER true in prod - would destroy all MLflow artifacts.
  type        = bool
  description = "Allow bucket destruction when non-empty. Never set true in prod."
  default     = false
}

variable "enable_versioning" {
  # Keeps all previous object versions.
  # Enables recovery if a bad model overwrites a good one.
  # Increases storage cost - offset by lifecycle expiry below.
  type        = bool
  description = "Enable S3 object versioning. Recommended true."
  default     = true
}

variable "noncurrent_version_expiry_days" {
  # How many days to retain old object versions before deleting them.
  # 30 days = enough window to catch a bad model deploy and roll back.
  # After 30 days, old versions are permanently deleted to control cost.
  type        = number
  description = "Days to retain non-current object versions before expiry."
  default     = 30
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all S3 resources."
  default     = {}
}

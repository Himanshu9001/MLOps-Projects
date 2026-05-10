# ─────────────────────────────────────────────────────────────────────────────
# modules/iam/variables.tf
#
# Creates ALL IAM resources for this project:
#   1. MLflow EC2 instance role + profile
#      - allows S3 read/write for artifact store
#   2. IRSA role for EKS pods (churn-prediction-sa ServiceAccount)
#      - scoped S3 access (2 buckets only) + Secrets Manager read
#   3. EKS node role
#      - minimal policies: EKS worker, CNI, ECR read, EBS CSI, autoscaler
#   4. Scoped IAM policies for all above
#
# IAM resources are GLOBAL (not regional) and persist across cluster
# recreations - created ONCE, reused every time cluster is rebuilt.
# This matches your existing setup-iam.sh one-time script.
#
# Called by: live/nonprod/30-compute and live/prod/30-compute
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Deployment environment."

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

variable "account_id" {
  # Used to build ARNs for IAM policy resource statements.
  # Example: arn:aws:s3:::churn-mlops-nonprod-artifacts
  # Avoids hardcoding 011528270076 throughout policy documents.
  type        = string
  description = "AWS account ID. Used to build ARNs in IAM policy documents."
}

variable "artifacts_bucket_arn" {
  # From s3 module output: module.s3.artifacts_bucket_arn
  # Used in IRSA S3 policy - scopes access to this specific bucket only.
  type        = string
  description = "ARN of the MLflow artifacts S3 bucket. Used in scoped S3 IAM policy."
}

variable "dvc_bucket_arn" {
  # From s3 module output: module.s3.dvc_bucket_arn
  type        = string
  description = "ARN of the DVC data store S3 bucket. Used in scoped S3 IAM policy."
}

variable "eks_oidc_provider_arn" {
  # From eks module output: module.eks.oidc_provider_arn
  # Format: arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<oidc_id>
  # Required for IRSA trust policy - tells IAM which OIDC provider to trust.
  # Empty string = EKS not deployed yet, skip IRSA role creation.
  type        = string
  description = "OIDC provider ARN of the EKS cluster. From eks module output. Leave empty if EKS not deployed yet."
  default     = ""
}

variable "eks_oidc_provider_url" {
  # From eks module output: module.eks.oidc_provider_url
  # Format: oidc.eks.<region>.amazonaws.com/id/<oidc_id>
  # Used as the key in IRSA trust policy StringEquals condition.
  type        = string
  description = "OIDC provider URL (without https://). From eks module output."
  default     = ""
}

variable "k8s_namespace" {
  # The Kubernetes namespace where the ServiceAccount lives.
  # IRSA trust policy scopes to: system:serviceaccount:<namespace>:<sa_name>
  # Changing this requires updating the trust policy and restarting pods.
  type        = string
  description = "Kubernetes namespace of the ServiceAccount for IRSA scoping."
  default     = "churn-mlops"
}

variable "k8s_service_account_name" {
  # ServiceAccount name that pods use.
  # Must match serviceaccount.yaml annotation in Helm chart.
  type        = string
  description = "Kubernetes ServiceAccount name for IRSA scoping."
  default     = "churn-prediction-sa"
}

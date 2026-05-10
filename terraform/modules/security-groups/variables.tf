# ─────────────────────────────────────────────────────────────────────────────
# modules/security-groups/variables.tf
#
# All security groups for this project live in one module:
#   - MLflow EC2 SG   → allows SSH (optional), MLflow port 5000 from EKS VPC
#   - RDS SG          → allows 5432 from MLflow EC2 SG only
#   - ElastiCache SG  → allows 6379 from EKS VPC CIDR only
#   - EKS nodes SG    → allows all internal cluster traffic
#
# Called by: live/nonprod/10-network and live/prod/10-network
# (Security groups are network resources - they live in the network stack,
#  not in the compute or data stacks. This avoids circular dependencies:
#  RDS needs the SG ID, SG needs the VPC ID, VPC is in 10-network.)
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Deployment environment. Used in SG names and tags."

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

variable "vpc_id" {
  # Passed from vpc module output: module.vpc.vpc_id
  # Every SG must be attached to a VPC - no cross-VPC SG references allowed.
  type        = string
  description = "VPC ID to create security groups in. From vpc module output."
}

variable "vpc_cidr" {
  # Used for intra-VPC ingress rules.
  # Example: MLflow SG allows 5000/tcp from vpc_cidr so any resource in the
  # VPC can reach MLflow - not just EKS pods.
  type        = string
  description = "CIDR of the VPC. Used for intra-VPC ingress rules."
}

variable "eks_vpc_cidr" {
  # EKS creates its own VPC (eksctl default: 192.168.0.0/16).
  # MLflow SG needs to allow port 5000 from this CIDR so EKS pods can reach MLflow.
  # ElastiCache SG needs to allow 6379 from this CIDR.
  # Empty string = EKS stack not deployed yet, skip EKS-specific rules.
  type        = string
  description = "CIDR of the EKS-managed VPC. Used for cross-VPC ingress rules. Leave empty if EKS not deployed yet."
  default     = ""
}

variable "allowed_ssh_cidrs" {
  # Restricts SSH access to MLflow EC2.
  # Default empty = SSH disabled (port 22 not opened).
  # Set to your office IP or VPN CIDR in nonprod only.
  # Never open 0.0.0.0/0 for SSH - covered by OPA Gatekeeper equivalent at infra level.
  type        = list(string)
  description = "CIDRs allowed to SSH into MLflow EC2. Empty list disables SSH. Never use 0.0.0.0/0."
  default     = []
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all security groups."
  default     = {}
}

# ─────────────────────────────────────────────────────────────────────────────
# modules/ec2/variables.tf
#
# Creates NEW EC2 instance for MLflow tracking server.
# Naming: ${project}-${environment}-mlflow-server
# Example: churn-mlops-nonprod-mlflow-server
#
# Existing instance (i-0d3ebb196f1ed53b8) is NOT touched.
# New instance gets its own Elastic IP.
#
# Blue-green cutover for EC2:
#   1. New EC2 starts, MLflow connects to new RDS + new S3 bucket
#   2. Sanity test: run drift_detection.py pointing to new MLflow URI
#   3. Update MLFLOW_TRACKING_URI in AWS Secrets Manager to new EC2 IP
#   4. Kubernetes pods pick up new secret on next restart
#   5. Old EC2 stopped → terminated after validation period
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

variable "instance_type" {
  # t3.small: 2 vCPU, 2 GB RAM - matches existing mlflow-server instance.
  # MLflow server is lightweight: gunicorn with 2 workers, handles metadata
  # reads/writes only. Model artifacts go directly to S3, not through EC2.
  type        = string
  description = "EC2 instance type. Example: t3.small"
  default     = "t3.small"
}

variable "subnet_id" {
  # Public subnet - MLflow EC2 needs a public IP for:
  #   1. MLflow UI access during development
  #   2. Elastic IP attachment
  # In hardened prod, this moves to private subnet behind a bastion.
  # From vpc module: module.vpc.public_subnet_ids[0]
  type        = string
  description = "Subnet ID to launch EC2 into. Use public subnet for MLflow UI access."
}

variable "security_group_ids" {
  # From security-groups module: [module.security_groups.mlflow_sg_id]
  type        = list(string)
  description = "Security group IDs to attach to the EC2 instance."
}

variable "iam_instance_profile_name" {
  # From iam module: module.iam.mlflow_instance_profile_name
  # Profile must have S3 access for artifact store reads/writes.
  type        = string
  description = "IAM instance profile name to attach. Must allow S3 access for artifact store."
}

variable "rds_endpoint" {
  # From rds module output: module.rds.address
  # Injected into EC2 userdata to build the MLflow --backend-store-uri flag.
  type        = string
  description = "RDS PostgreSQL hostname. Injected into MLflow startup script."
}

variable "rds_password" {
  # Same password used in rds module.
  # Sensitive - Terraform redacts from output.
  # Used only in EC2 userdata to build the connection string.
  type        = string
  description = "RDS master password. Used in MLflow backend-store-uri."
  sensitive   = true
}

variable "artifacts_bucket_name" {
  # From s3 module output: module.s3.artifacts_bucket_name
  # Injected into userdata: --default-artifact-root s3://<bucket>
  type        = string
  description = "S3 artifacts bucket name. Used in MLflow --default-artifact-root."
}

variable "mlflow_port" {
  # Port MLflow gunicorn listens on inside the EC2.
  # Security group allows this port from VPC CIDR and EKS VPC CIDR.
  type        = number
  description = "Port MLflow server listens on."
  default     = 5000
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all EC2 resources."
  default     = {}
}

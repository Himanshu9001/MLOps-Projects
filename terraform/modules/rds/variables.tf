# ─────────────────────────────────────────────────────────────────────────────
# modules/rds/variables.tf
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
}

variable "db_name" {
  type        = string
  description = "Database name inside PostgreSQL."
  default     = "mlflow"
}

variable "db_username" {
  type        = string
  description = "Master username for PostgreSQL."
  default     = "mlflow"
}

variable "db_password" {
  type        = string
  description = "Master password. Pass via TF_VAR_db_password env var."
  sensitive   = true
}

variable "instance_class" {
  type        = string
  description = "RDS instance class. Example: db.t3.micro"
  default     = "db.t3.micro"
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL engine version. Example: 15"
  default     = "15"
}

variable "allocated_storage" {
  type        = number
  description = "Initial storage in GB."
  default     = 20
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ standby. Set true in prod."
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "Days to retain automated backups. 0 disables backups."
  default     = 1
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot on destroy. Set false in prod."
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection. Set true in prod."
  default     = false
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for RDS subnet group. Minimum 2 in different AZs."
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to attach to RDS instance."
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all RDS resources."
  default     = {}
}

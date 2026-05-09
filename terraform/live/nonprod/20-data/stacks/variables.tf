variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "rds_instance_class" {
  type = string
}

variable "rds_multi_az" {
  type = bool
}

variable "rds_backup_retention" {
  type = number
}

variable "rds_skip_final_snapshot" {
  type = bool
}

variable "rds_deletion_protection" {
  type = bool
}

variable "redis_node_type" {
  type = string
}

variable "redis_engine_version" {
  type = string
}

variable "redis_snapshot_retention" {
  type = number
}

variable "enable_versioning" {
  type = bool
}

variable "noncurrent_version_expiry_days" {
  type = number
}

variable "force_destroy" {
  type = bool
}

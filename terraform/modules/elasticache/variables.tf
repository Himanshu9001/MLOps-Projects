# ─────────────────────────────────────────────────────────────────────────────
# modules/elasticache/variables.tf
#
# Creates a NEW ElastiCache Redis cluster - parallel to existing churn-mlops-redis.
# Naming: ${project}-${environment}-redis
# Example: churn-mlops-nonprod-redis
#
# Existing cluster is NOT touched.
# Blue-green cutover: stream processor and Feast REDIS_HOST env var updated
# in k8s/stream-processor-deployment.yaml and feature_store.yaml at cutover.
#
# Called by: live/nonprod/20-data and live/prod/20-data
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

variable "node_type" {
  # cache.t3.micro: 0.5 GB RAM - sufficient for:
  #   5634 customer feature hashes (~50 MB)
  #   prediction cache with 1hr TTL
  # cache.t3.small: 1.37 GB RAM - use if Feast materialization causes OOM
  type        = string
  description = "ElastiCache node type."
  default     = "cache.t3.micro"
}

variable "engine_version" {
  type        = string
  description = "Redis engine version."
  default     = "7.1"
}

variable "subnet_ids" {
  # From vpc module: module.vpc.private_subnet_ids
  # ElastiCache subnet group requires minimum 2 subnets in different AZs.
  type        = list(string)
  description = "Private subnet IDs for ElastiCache subnet group."
}

variable "security_group_ids" {
  # From security-groups module: [module.security_groups.elasticache_sg_id]
  type        = list(string)
  description = "Security group IDs to attach to the ElastiCache cluster."
}

variable "port" {
  type        = number
  description = "Redis port."
  default     = 6379
}

variable "snapshot_retention_limit" {
  # 0 = no snapshots - Redis used as cache only, data is ephemeral by design.
  # For prod where Redis is used as Feast online store with long TTLs,
  # set to 1 to allow recovery if cluster is accidentally deleted.
  type        = number
  description = "Days to retain Redis snapshots. 0 disables snapshots."
  default     = 0
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all ElastiCache resources."
  default     = {}
}
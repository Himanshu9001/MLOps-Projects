# ─────────────────────────────────────────────────────────────────────────────
# modules/elasticache/main.tf
# ─────────────────────────────────────────────────────────────────────────────

locals {
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "elasticache"
    },
    var.additional_tags
  )

  cluster_id = "${var.project}-${var.environment}-redis"
}

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-elasticache-subnet"
  description = "ElastiCache subnet group - private subnets"
  subnet_ids  = var.subnet_ids

  tags = merge(local.base_tags, {
    Name = "${var.project}-${var.environment}-elasticache-subnet"
  })
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = local.cluster_id
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  port                 = var.port
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.security_group_ids

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "02:00-03:00"
  maintenance_window       = "sun:03:00-sun:04:00"

  apply_immediately = var.environment == "nonprod" ? true : false

  tags = merge(local.base_tags, {
    Name = local.cluster_id
  })
}

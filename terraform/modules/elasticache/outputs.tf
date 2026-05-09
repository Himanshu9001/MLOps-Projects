# ─────────────────────────────────────────────────────────────────────────────
# modules/elasticache/outputs.tf
#
# Consumed by:
#   40-kubernetes stack → redis_endpoint, redis_port, redis_connection_string
#     Used to template:
#       - k8s/stream-processor-deployment.yaml REDIS_HOST env var
#       - feature_store/churn_feature_repo/feature_repo/feature_store.yaml
#       - dags/feature_materialization.py REDIS_HOST env var
# ─────────────────────────────────────────────────────────────────────────────

output "redis_endpoint" {
  description = "Redis cluster hostname. Used as REDIS_HOST in stream processor and Feast."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port. Default 6379."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

output "redis_connection_string" {
  description = "Full host:port string. Used in Feast feature_store.yaml connection_string."
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "cluster_id" {
  description = "ElastiCache cluster ID."
  value       = aws_elasticache_cluster.redis.cluster_id
}

output "subnet_group_name" {
  description = "Subnet group name. Used as reference if adding replicas later."
  value       = aws_elasticache_subnet_group.main.name
}
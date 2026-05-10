# ─────────────────────────────────────────────────────────────────────────────
# modules/security-groups/outputs.tf
#
# Consumed by:
#   30-compute  → mlflow_sg_id  (attach to EC2 instance)
#   20-data     → rds_sg_id     (attach to RDS instance)
#   20-data     → elasticache_sg_id (attach to ElastiCache cluster)
#   40-kubernetes → eks_nodes_sg_id (attach to EKS nodegroup)
# ─────────────────────────────────────────────────────────────────────────────

output "mlflow_sg_id" {
  description = "Security Group ID for MLflow EC2. Attach to EC2 instance in 30-compute stack."
  value       = aws_security_group.mlflow.id
}

output "rds_sg_id" {
  description = "Security Group ID for RDS PostgreSQL. Attach to RDS instance in 20-data stack."
  value       = aws_security_group.rds.id
}

output "elasticache_sg_id" {
  description = "Security Group ID for ElastiCache Redis. Attach to cluster in 20-data stack."
  value       = aws_security_group.elasticache.id
}

output "eks_nodes_sg_id" {
  description = "Security Group ID for EKS worker nodes. Attach to nodegroup in 40-kubernetes stack."
  value       = aws_security_group.eks_nodes.id
}

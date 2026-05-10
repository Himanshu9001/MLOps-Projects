# ─────────────────────────────────────────────────────────────────────────────
# modules/iam/outputs.tf
#
# Consumed by:
#   30-compute stack   → mlflow_instance_profile_name (attach to EC2)
#   40-kubernetes stack → eks_node_role_arn (EKS nodegroup)
#                         irsa_role_arn (ServiceAccount annotation)
# ─────────────────────────────────────────────────────────────────────────────

output "mlflow_instance_profile_name" {
  description = "IAM instance profile name for MLflow EC2. Pass to ec2 module."
  value       = aws_iam_instance_profile.mlflow.name
}

output "mlflow_ec2_role_arn" {
  description = "IAM role ARN for MLflow EC2."
  value       = aws_iam_role.mlflow_ec2.arn
}

output "eks_node_role_arn" {
  description = "IAM role ARN for EKS worker nodes. Used in EKS nodegroup configuration."
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_instance_profile_name" {
  description = "IAM instance profile name for EKS nodes."
  value       = aws_iam_instance_profile.eks_node.name
}

output "irsa_role_arn" {
  description = "IRSA role ARN for EKS pods. Used in ServiceAccount eks.amazonaws.com/role-arn annotation."
  value       = local.create_irsa ? aws_iam_role.irsa[0].arn : ""
}

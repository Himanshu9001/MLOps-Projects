# ─────────────────────────────────────────────────────────────────────────────
# modules/eks/outputs.tf
#
# Consumed by:
#   30-compute stack (iam module second pass):
#     oidc_provider_arn, oidc_provider_url → create IRSA role
#
#   40-kubernetes stack:
#     cluster_name, cluster_endpoint, cluster_ca → configure K8s/Helm providers
#
#   10-network stack (second pass):
#     node_vpc_id → VPC peering peer_vpc_id
# ─────────────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name. Used in aws eks update-kubeconfig and kubectl contexts."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint. Used to configure Kubernetes and Helm providers."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate. Used in Kubernetes provider configuration."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN. Pass to iam module for IRSA role trust policy."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL without https://. Pass to iam module for IRSA trust policy conditions."
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "node_group_id" {
  description = "Managed node group ID."
  value       = aws_eks_node_group.main.id
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID. Used to add ingress rules for VPC peering."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "kubeconfig_command" {
  description = "Run this command to update kubeconfig after apply."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

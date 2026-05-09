output "cluster_name"           { value = module.eks.cluster_name }
output "cluster_endpoint"       { value = module.eks.cluster_endpoint }
output "cluster_ca_certificate" { value = module.eks.cluster_ca_certificate }
output "oidc_provider_arn"      { value = module.eks.oidc_provider_arn }
output "oidc_provider_url"      { value = module.eks.oidc_provider_url }
output "kubeconfig_command"     { value = module.eks.kubeconfig_command }

output "eks_vpc_id" {
  description = "EKS VPC ID. Copy to prod/10-network peer_vpc_id after this apply."
  value       = module.eks.cluster_security_group_id
}

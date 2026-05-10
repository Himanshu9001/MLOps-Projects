output "irsa_role_arn" {
  description = "IRSA role ARN for churn-prediction-sa. Annotate ServiceAccount with this."
  value       = aws_iam_role.irsa.arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for ebs-csi-controller-sa. Wire into EKS addon."
  value       = aws_iam_role.ebs_csi.arn
}

output "image_updater_role_arn" {
  description = "IRSA role ARN for argocd-image-updater. Annotate ServiceAccount with this."
  value       = aws_iam_role.image_updater.arn
}

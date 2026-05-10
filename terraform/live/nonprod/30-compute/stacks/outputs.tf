output "mlflow_public_ip"         { value = module.ec2.public_ip }
output "mlflow_private_ip"        { value = module.ec2.private_ip }
output "mlflow_tracking_uri"      { value = module.ec2.mlflow_tracking_uri }
output "mlflow_instance_id"       { value = module.ec2.instance_id }
output "irsa_role_arn"            { value = module.iam.irsa_role_arn }
output "eks_node_role_arn"        { value = module.iam.eks_node_role_arn }

output "ssh_private_key" {
  value     = module.ec2.ssh_private_key
  sensitive = true
}

output "image_updater_role_arn" {
  value = aws_iam_role.image_updater.arn
}

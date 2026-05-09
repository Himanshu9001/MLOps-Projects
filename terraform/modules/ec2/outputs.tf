output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.mlflow.id
}

output "public_ip" {
  description = "Elastic IP of MLflow EC2. Stable across stop/start cycles."
  value       = aws_eip.mlflow.public_ip
}

output "private_ip" {
  description = "Private IP of MLflow EC2. Used in NetworkPolicy and VPC peering routes."
  value       = aws_instance.mlflow.private_ip
}

output "mlflow_tracking_uri" {
  description = "Full MLflow tracking URI. Update Secrets Manager with this after cutover."
  value       = "http://${aws_eip.mlflow.public_ip}:5000"
}

output "ssh_private_key" {
  description = "PEM private key for SSH access to MLflow EC2."
  value       = tls_private_key.mlflow.private_key_pem
  sensitive   = true
}

output "ami_id" {
  description = "AMI ID used for this instance."
  value       = data.aws_ami.amazon_linux_2023.id
}

output "repository_urls" {
  description = "Map of repo name to full ECR URL."
  value       = { for k, v in aws_ecr_repository.main : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repo name to ARN."
  value       = { for k, v in aws_ecr_repository.main : k => v.arn }
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)."
  value       = values(aws_ecr_repository.main)[0].registry_id
}

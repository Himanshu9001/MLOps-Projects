# ─────────────────────────────────────────────────────────────────────────────
# Outputs used in backend.hcl files of all other stacks.
# After apply, run: terraform output
# Copy bucket and table name into each stack's backend.hcl.
# ─────────────────────────────────────────────────────────────────────────────

output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state. Use in all other stacks backend.hcl."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking. Use in all other stacks backend.hcl."
  value       = aws_dynamodb_table.terraform_locks.id
}

output "lock_table_arn" {
  description = "DynamoDB table ARN."
  value       = aws_dynamodb_table.terraform_locks.arn
}

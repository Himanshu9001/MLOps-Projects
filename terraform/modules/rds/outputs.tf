# ─────────────────────────────────────────────────────────────────────────────
# modules/rds/outputs.tf
#
# Consumed by:
#   30-compute stack → endpoint, address
#     Used in MLflow EC2 userdata script:
#     --backend-store-uri postgresql://mlflow:<pass>@<address>:5432/mlflow
# ─────────────────────────────────────────────────────────────────────────────

output "endpoint" {
  description = "RDS endpoint as host:port. Example: churn-mlops-nonprod-mlflow-db.xyz.us-east-1.rds.amazonaws.com:5432"
  value       = aws_db_instance.mlflow.endpoint
}

output "address" {
  description = "RDS hostname only, no port. Used in MLflow backend-store-uri."
  value       = aws_db_instance.mlflow.address
}

output "port" {
  description = "RDS port. Always 5432 for PostgreSQL."
  value       = aws_db_instance.mlflow.port
}

output "db_name" {
  description = "Database name inside PostgreSQL."
  value       = aws_db_instance.mlflow.db_name
}

output "instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.mlflow.identifier
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for RDS master password. Pass to EC2 module as db_secret_arn."
  # try() returns "" if master_user_secret is empty (before first apply with
  # manage_master_user_password=true). After apply the secret ARN is populated.
  value = try(aws_db_instance.mlflow.master_user_secret[0].secret_arn, "")
}

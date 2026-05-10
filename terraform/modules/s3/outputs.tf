# ─────────────────────────────────────────────────────────────────────────────
# modules/s3/outputs.tf
#
# Consumed by:
#   modules/iam        → artifacts_bucket_arn, dvc_bucket_arn
#                        (scoped IRSA S3 policy resource statements)
#   30-compute stack   → artifacts_bucket_name
#                        (MLflow EC2 --default-artifact-root s3://<name>)
#   40-kubernetes stack → artifacts_bucket_name
#                        (Feast feature_store.yaml, Airflow DAG env vars)
# ─────────────────────────────────────────────────────────────────────────────

output "artifacts_bucket_name" {
  description = "Artifacts bucket name. Used in MLflow --default-artifact-root."
  value       = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  description = "Artifacts bucket ARN. Used in IRSA IAM policy resource statements."
  value       = aws_s3_bucket.artifacts.arn
}

output "dvc_bucket_name" {
  description = "DVC bucket name. Used in dvc remote add command during cutover."
  value       = aws_s3_bucket.dvc.id
}

output "dvc_bucket_arn" {
  description = "DVC bucket ARN. Used in IRSA IAM policy resource statements."
  value       = aws_s3_bucket.dvc.arn
}

output "artifacts_bucket_region" {
  description = "Region of the artifacts bucket. Used to construct S3 endpoint URLs."
  value       = aws_s3_bucket.artifacts.region
}

output "artifacts_bucket_name"   { value = module.s3.artifacts_bucket_name }
output "artifacts_bucket_arn"    { value = module.s3.artifacts_bucket_arn }
output "dvc_bucket_name"         { value = module.s3.dvc_bucket_name }
output "dvc_bucket_arn"          { value = module.s3.dvc_bucket_arn }
output "rds_address"             { value = module.rds.address }
output "rds_endpoint"            { value = module.rds.endpoint }
output "rds_port"                { value = module.rds.port }
output "rds_db_name"             { value = module.rds.db_name }
output "redis_endpoint"          { value = module.elasticache.redis_endpoint }
output "redis_port"              { value = module.elasticache.redis_port }
output "redis_connection_string" { value = module.elasticache.redis_connection_string }

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecr_registry_id" {
  value = module.ecr.registry_id
}

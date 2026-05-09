environment              = "prod"
project                  = "churn-mlops"
region                   = "us-east-1"

# RDS - prod: multi-AZ, deletion protection, 7 day backup retention
db_name                  = "mlflow"
db_username              = "mlflow"
# db_password via: export TF_VAR_db_password=<password>
rds_instance_class       = "db.t3.small"
rds_multi_az             = true
rds_backup_retention     = 7
rds_skip_final_snapshot  = false
rds_deletion_protection  = true

# ElastiCache - prod: larger node, snapshot enabled
redis_node_type          = "cache.t3.small"
redis_engine_version     = "7.1"
redis_snapshot_retention = 1

# S3 - prod: versioning on, longer retention window
enable_versioning              = true
noncurrent_version_expiry_days = 90
force_destroy                  = false

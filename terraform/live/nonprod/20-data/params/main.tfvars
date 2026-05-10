environment = "nonprod"
project     = "churn-mlops"
region      = "us-east-1"

# RDS
db_name     = "mlflow"
db_username = "mlflow"
# db_password passed via: export TF_VAR_db_password=<password>
# Never hardcode here.
rds_instance_class      = "db.t3.micro"
rds_multi_az            = false
rds_backup_retention    = 1
rds_skip_final_snapshot = true
rds_deletion_protection = false

# ElastiCache
redis_node_type          = "cache.t3.micro"
redis_engine_version     = "7.1"
redis_snapshot_retention = 0

# S3
enable_versioning              = true
noncurrent_version_expiry_days = 30
force_destroy                  = false

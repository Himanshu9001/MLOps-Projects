environment = "prod"
project     = "churn-mlops"
region      = "us-east-1"
account_id  = "011528270076"

# t3.medium for prod - more connections to RDS and S3 under load
ec2_instance_type = "t3.medium"
mlflow_port       = 5000

# db_password via: export TF_VAR_db_password=<password>

# Fill these after 40-kubernetes apply, then re-apply this stack.
eks_oidc_provider_arn = ""
eks_oidc_provider_url = ""

bucket         = "churn-mlops-nonprod-terraform-state"
key            = "nonprod/50-iam/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "churn-mlops-nonprod-terraform-locks"
encrypt        = true

bucket         = "churn-mlops-nonprod-terraform-state"
key            = "nonprod/40-kubernetes/terraform.tfstate"
region         = "us-east-1"
# use_lockfile = true
# Supported in newer Terraform versions locally,
# but GitHub Actions runner (v1.9.8) does not support it.

dynamodb_table = "churn-mlops-nonprod-terraform-locks"
encrypt        = true
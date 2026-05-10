bucket         = "churn-mlops-nonprod-terraform-state"
key            = "nonprod/10-network/terraform.tfstate"
region         = "us-east-1"

# use_lockfile = true
# Supported in newer Terraform versions locally,
# but GitHub Actions runner (v1.9.8) does not support it.

dynamodb_table = "churn-mlops-nonprod-terraform-locks"
encrypt        = true

# GitHub Actions CI/CD role: github-actions-terraform
# Policy: churn-mlops-terraform-ci-policy (replaces AdministratorAccess)
# ARN: arn:aws:iam::011528270076:policy/churn-mlops-terraform-ci-policy

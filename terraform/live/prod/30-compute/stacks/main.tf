# ─────────────────────────────────────────────────────────────────────────────
# prod/30-compute/stacks/main.tf
#
# Prod differences from nonprod:
#   - EC2: t3.medium instead of t3.small
#   - IAM: same structure, scoped to prod buckets
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  backend "s3" {}

  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/10-network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/20-data/terraform.tfstate"
    region = var.region
  }
}

module "iam" {
  source = "../../../../modules/iam"

  environment           = var.environment
  project               = var.project
  region                = var.region
  account_id            = var.account_id
  artifacts_bucket_arn  = data.terraform_remote_state.data.outputs.artifacts_bucket_arn
  dvc_bucket_arn        = data.terraform_remote_state.data.outputs.dvc_bucket_arn
  eks_oidc_provider_arn = var.eks_oidc_provider_arn
  eks_oidc_provider_url = var.eks_oidc_provider_url
}

module "ec2" {
  source = "../../../../modules/ec2"

  environment               = var.environment
  project                   = var.project
  region                    = var.region
  instance_type             = var.ec2_instance_type
  mlflow_port               = var.mlflow_port
  subnet_id                 = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  security_group_ids        = [data.terraform_remote_state.network.outputs.mlflow_sg_id]
  iam_instance_profile_name = module.iam.mlflow_instance_profile_name
  rds_endpoint              = data.terraform_remote_state.data.outputs.rds_address
  rds_password              = var.db_password
  artifacts_bucket_name     = data.terraform_remote_state.data.outputs.artifacts_bucket_name
}

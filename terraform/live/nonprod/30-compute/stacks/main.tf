# ─────────────────────────────────────────────────────────────────────────────
# 30-compute/stacks/main.tf
#
# Creates: IAM roles/policies, MLflow EC2.
# Reads from: 10-network, 20-data remote state.
#
# Two-pass apply:
#   Pass 1: eks_oidc_provider_arn = "" → IAM created without IRSA role
#   Pass 2: after 40-kubernetes apply, fill OIDC values → IRSA role created
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

# ── Read remote state ─────────────────────────────────────────────────────────

data "terraform_remote_state" "kubernetes" {
  backend = "s3"
  config = {
    bucket = "churn-mlops-nonprod-terraform-state"
    key    = "nonprod/40-kubernetes/terraform.tfstate"
    region = "us-east-1"
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

# ── IAM ───────────────────────────────────────────────────────────────────────

module "iam" {
  source = "../../../../modules/iam"

  environment          = var.environment
  project              = var.project
  region               = var.region
  account_id           = var.account_id
  artifacts_bucket_arn = data.terraform_remote_state.data.outputs.artifacts_bucket_arn
  dvc_bucket_arn       = data.terraform_remote_state.data.outputs.dvc_bucket_arn
  eks_oidc_provider_arn = var.eks_oidc_provider_arn
  eks_oidc_provider_url = var.eks_oidc_provider_url
}

# ── EC2 MLflow ────────────────────────────────────────────────────────────────

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

# ── ArgoCD Image Updater IRSA ─────────────────────────────────────────────────
# Gives Image Updater pod ECR read access to detect new image tags.
# Scoped to argocd namespace service account.

data "aws_iam_policy_document" "image_updater_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.kubernetes.outputs.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.kubernetes.outputs.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:argocd:argocd-image-updater"]
    }
  }
}

resource "aws_iam_role" "image_updater" {
  name               = "${var.project}-${var.environment}-image-updater-role"
  assume_role_policy = data.aws_iam_policy_document.image_updater_assume.json
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "image_updater_ecr" {
  name = "ecr-read"
  role = aws_iam_role.image_updater.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ]
      Resource = "*"
    }]
  })
}

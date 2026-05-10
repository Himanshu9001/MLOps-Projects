# ─────────────────────────────────────────────────────────────────────────────
# 50-iam/stacks/main.tf
#
# WHY THIS STACK EXISTS — eliminating the two-pass apply problem:
#
# BEFORE (two-pass required):
#   30-compute creates IRSA roles but needs OIDC from 40-kubernetes
#   40-kubernetes creates OIDC but needs node role ARN from 30-compute
#   → circular dependency → two-pass apply required every cluster rebuild
#
# AFTER (single pass):
#   30-compute: creates node role + EC2 only (no IRSA, no OIDC dependency)
#   40-kubernetes: creates EKS cluster + OIDC provider
#   50-iam: runs AFTER both, reads OIDC from 40-kubernetes remote state,
#           creates all IRSA roles in one clean pass
#
# Apply order: 00 → 10 → 20 → 30 → 40 → 50 (single pass, no re-apply)
#
# Resources managed here:
#   - IRSA role for churn-prediction-sa (S3 + Secrets Manager access)
#   - IRSA role for ebs-csi-controller-sa (EBS provisioning)
#   - IRSA role for argocd-image-updater (ECR read access)
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

# ── Read remote state from upstream stacks ────────────────────────────────────

# 40-kubernetes: provides OIDC provider ARN + URL (created after EKS cluster)
data "terraform_remote_state" "kubernetes" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/40-kubernetes/terraform.tfstate"
    region = var.region
  }
}

# 20-data: provides S3 bucket ARNs for IRSA S3 policy scoping
data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/20-data/terraform.tfstate"
    region = var.region
  }
}

locals {
  name_prefix       = "${var.project}-${var.environment}"
  oidc_provider_arn = data.terraform_remote_state.kubernetes.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.kubernetes.outputs.oidc_provider_url
}

# ── IRSA role — churn-prediction-sa ──────────────────────────────────────────
# Scoped to churn-prediction-sa ServiceAccount in churn-mlops namespace.
# Grants: S3 access (artifacts + DVC buckets) + Secrets Manager read.

data "aws_iam_policy_document" "irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:churn-mlops:churn-prediction-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  name               = "${local.name_prefix}-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume.json

  tags = {
    Name      = "${local.name_prefix}-irsa-role"
    ManagedBy = "Terraform"
    Stack     = "50-iam"
  }
}

resource "aws_iam_role_policy" "irsa_s3" {
  name = "s3-access"
  role = aws_iam_role.irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PodS3Access"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      Resource = [
        data.terraform_remote_state.data.outputs.artifacts_bucket_arn,
        "${data.terraform_remote_state.data.outputs.artifacts_bucket_arn}/*",
        data.terraform_remote_state.data.outputs.dvc_bucket_arn,
        "${data.terraform_remote_state.data.outputs.dvc_bucket_arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "irsa_secrets" {
  name = "secrets-access"
  role = aws_iam_role.irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PodSecretsAccess"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project}/*"
    }]
  })
}

# ── IRSA role — ebs-csi-controller-sa ────────────────────────────────────────
# Scoped to ebs-csi-controller-sa ServiceAccount in kube-system namespace.
# Grants: AmazonEBSCSIDriverPolicy for dynamic EBS volume provisioning.

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json

  tags = {
    Name      = "${local.name_prefix}-ebs-csi-role"
    ManagedBy = "Terraform"
    Stack     = "50-iam"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── IRSA role — argocd-image-updater ─────────────────────────────────────────
# Scoped to argocd-image-updater ServiceAccount in argocd namespace.
# Grants: ECR read access to detect new image tags.

data "aws_iam_policy_document" "image_updater_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:argocd:argocd-image-updater"]
    }
  }
}

resource "aws_iam_role" "image_updater" {
  name               = "${local.name_prefix}-image-updater-role"
  assume_role_policy = data.aws_iam_policy_document.image_updater_assume.json

  tags = {
    Name      = "${local.name_prefix}-image-updater-role"
    ManagedBy = "Terraform"
    Stack     = "50-iam"
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
        "ecr:ListImages",
      ]
      Resource = "*"
    }]
  })
}

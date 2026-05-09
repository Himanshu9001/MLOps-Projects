# ─────────────────────────────────────────────────────────────────────────────
# terraform/versions.tf
#
# Pins Terraform CLI version and all provider versions at the root level.
# Every live stack inherits these constraints.
#
# WHY PIN WITH ~> (pessimistic constraint):
#   ~> 5.80 allows 5.81, 5.82 but blocks 6.0.
#   Using >= would silently pull a future breaking major version on next
#   terraform init - the AWS provider broke EKS and IAM resources between 4.x
#   and 5.x. Never use >= for providers in production.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    # Generates EC2 key pair inline - no manual aws ec2 create-key-pair needed
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Used in 00-s3-backend to generate unique DynamoDB lock table name
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
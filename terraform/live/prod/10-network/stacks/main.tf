# ─────────────────────────────────────────────────────────────────────────────
# prod/10-network/stacks/main.tf
#
# Prod differences from nonprod:
#   - NAT Gateway enabled (nodes in private subnets)
#   - single_nat_gateway = false (one per AZ for HA)
#   - VPC CIDR: 10.2.0.0/16
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

module "vpc" {
  source = "../../../../modules/vpc"

  environment          = var.environment
  project              = var.project
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  eks_cluster_name     = var.eks_cluster_name
  peer_vpc_id          = var.peer_vpc_id
  peer_vpc_cidr        = var.peer_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "security_groups" {
  source = "../../../../modules/security-groups"

  environment       = var.environment
  project           = var.project
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  eks_vpc_cidr      = var.peer_vpc_cidr
}

# ─────────────────────────────────────────────────────────────────────────────
# 10-network/stacks/main.tf
#
# Wires vpc module + security-groups module together.
# Security groups need vpc_id and vpc_cidr from vpc module - both in same stack
# to avoid a cross-stack dependency for basic networking resources.
#
# Two-pass apply for VPC peering:
#   Pass 1: peer_vpc_id = "" → VPC + SGs created, no peering
#   Pass 2: after 40-kubernetes apply, set peer_vpc_id + peer_vpc_cidr
#           in main.tfvars → re-apply → peering connection created
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

# ── VPC ───────────────────────────────────────────────────────────────────────

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

# ── Security Groups ───────────────────────────────────────────────────────────

module "security_groups" {
  source = "../../../../modules/security-groups"

  environment       = var.environment
  project           = var.project
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  # eks_vpc_cidr empty on first pass - SG rules for EKS traffic added on
  # second pass after EKS VPC CIDR is known.
  eks_vpc_cidr = var.peer_vpc_cidr
}

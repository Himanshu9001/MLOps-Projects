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

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "${var.environment}/30-compute/terraform.tfstate"
    region = var.region
  }
}

# REMOVED: manual data source for EBS CSI role
# Role is now fully managed by modules/iam — read via remote state.
# Before: data "aws_iam_role" "ebs_csi" { name = "..." } ← manual lookup
# After:  data.terraform_remote_state.compute.outputs.ebs_csi_role_arn ← Terraform-managed
# data "aws_iam_role" "ebs_csi" { ... } ← removed

module "eks" {
  source = "../../../../modules/eks"

  environment                  = var.environment
  project                      = var.project
  region                       = var.region
  cluster_version              = var.cluster_version
  node_instance_type           = var.node_instance_type
  node_desired_count           = var.node_desired_count
  node_min_count               = var.node_min_count
  node_max_count               = var.node_max_count
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  enable_cluster_creator_admin = true
  private_subnet_ids           = data.terraform_remote_state.network.outputs.private_subnet_ids
  node_security_group_ids      = [data.terraform_remote_state.network.outputs.eks_nodes_sg_id]
  node_role_arn                = data.terraform_remote_state.compute.outputs.eks_node_role_arn
  ebs_csi_role_arn             = data.terraform_remote_state.compute.outputs.ebs_csi_role_arn
}

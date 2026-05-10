# ─────────────────────────────────────────────────────────────────────────────
# modules/vpc/variables.tf
#
# All inputs this module accepts.
# Called by: live/nonprod/10-network and live/prod/10-network
#
# Variables without defaults = required (caller must provide)
# Variables with defaults    = optional (caller may override)
# validation blocks          = fail at plan time, not mid-apply
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Deployment environment. Used in all resource names and tags."

  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be 'nonprod' or 'prod'."
  }
}

variable "project" {
  # Prefix for all resource names: churn-mlops-nonprod-vpc, churn-mlops-prod-vpc
  type        = string
  description = "Project name prefix. Example: churn-mlops"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project))
    error_message = "project must be lowercase alphanumeric + hyphens, no leading/trailing hyphens."
  }
}

variable "region" {
  type        = string
  description = "AWS region. Example: us-east-1"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  # /16 = 65,536 IPs - required for EKS VPC CNI which allocates 1 IP per pod.
  # nonprod: 10.1.0.0/16, prod: 10.2.0.0/16 - no overlap enables future peering.
  type        = string
  description = "Primary CIDR block for the VPC. Use /16 for EKS. Example: 10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block. Example: 10.1.0.0/16"
  }
}

variable "public_subnet_cidrs" {
  # ALB lives here. In the hardened arch (Phase 19) EKS nodes move to private -
  # only the ALB stays public.
  type        = list(string)
  description = "CIDRs for public subnets, one per AZ. Example: [\"10.1.1.0/24\"]"

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "At least one public subnet CIDR is required."
  }
}

variable "private_subnet_cidrs" {
  # EKS nodes, RDS, ElastiCache live here.
  # Minimum 2 - AWS hard requirement for RDS subnet groups (must span 2 AZs).
  type        = list(string)
  description = "CIDRs for private subnets, one per AZ. Minimum 2 required for RDS subnet group."

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnet CIDRs required. RDS subnet group needs 2 AZs."
  }
}

variable "availability_zones" {
  # Must align 1:1 with private_subnet_cidrs by index.
  # AZ[0] → public_subnet[0] + private_subnet[0], AZ[1] → private_subnet[1], etc.
  type        = list(string)
  description = "AZs for subnets. Must match length of private_subnet_cidrs. Example: [\"us-east-1a\", \"us-east-1b\"]"

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required."
  }
}

variable "enable_nat_gateway" {
  # Phase 19: EKS nodes in private subnets need outbound internet for ECR pulls.
  # Disabled by default in nonprod to save ~$0.045/hr during dev.
  # Must be true in prod.
  type        = bool
  description = "Create a NAT Gateway for private subnet outbound internet. Required in prod."
  default     = false
}

variable "single_nat_gateway" {
  # true  → one NAT GW serves all AZs (cheaper, single point of failure)
  # false → one NAT GW per AZ (HA, 2–3x cost) - use in prod
  type        = bool
  description = "Use a single NAT Gateway for all AZs. Set false in prod for HA."
  default     = true
}

variable "peer_vpc_id" {
  # The EKS-managed VPC to peer with so pods can reach MLflow at 10.0.1.225:5000.
  # Empty string = skip peering (used on first apply before EKS stack exists).
  # After 40-kubernetes apply, pass its VPC ID here via terraform_remote_state.
  type        = string
  description = "VPC ID to peer with. Leave empty to skip. Used to peer MLflow VPC with EKS VPC."
  default     = ""
}

variable "peer_vpc_cidr" {
  # Needed to create the return route in this VPC's route tables.
  # EKS VPCs created by eksctl default to 192.168.0.0/16.
  type        = string
  description = "CIDR of the peer VPC. Required when peer_vpc_id is set. Example: 192.168.0.0/16"
  default     = ""
}

variable "eks_cluster_name" {
  # AWS Load Balancer Controller requires these subnet tags to discover subnets:
  #   Public:  kubernetes.io/role/elb = 1
  #   Private: kubernetes.io/role/internal-elb = 1
  #   Both:    kubernetes.io/cluster/<name> = shared
  # Without these, ALB creation fails with "no subnets found" error.
  # Leave empty for non-EKS VPCs.
  type        = string
  description = "EKS cluster name for ALB Controller subnet tagging. Leave empty if not hosting EKS."
  default     = ""
}

variable "enable_dns_hostnames" {
  # Required true for EKS API server endpoint resolution and RDS endpoint DNS.
  type        = bool
  description = "Enable DNS hostnames. Must be true for EKS and RDS."
  default     = true
}

variable "enable_dns_support" {
  # Enables AmazonProvidedDNS - required for EKS service discovery, RDS, Secrets Manager.
  type        = bool
  description = "Enable DNS support (AmazonProvidedDNS). Required for EKS service discovery."
  default     = true
}

variable "additional_tags" {
  # Merged onto every resource. Use for cost center, team, owner tags.
  # Base tags (Name, Environment, Project, ManagedBy=Terraform) always applied by module.
  type        = map(string)
  description = "Extra tags to merge onto all resources."
  default     = {}
}

environment          = "nonprod"
project              = "churn-mlops"
region               = "us-east-1"
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24"]
private_subnet_cidrs = ["10.1.2.0/24", "10.1.3.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]
enable_nat_gateway   = true
single_nat_gateway   = true
eks_cluster_name     = "churn-mlops-nonprod"

# VPC PEERING — not needed for this setup.
# EKS managed node group was placed inside the nonprod VPC (vpc-0da4e83c946d24180)
# because we passed nonprod private subnet IDs to the EKS node group.
# MLflow EC2 (10.1.1.233) and EKS nodes (10.1.x.x) are in the same VPC.
# Pod-to-MLflow connectivity verified: kubectl run curl-test -> http://10.1.1.233:5000/health -> OK
#
# WHEN WOULD YOU NEED PEERING:
# If EKS were created with eksctl (creates its own VPC: 192.168.0.0/16 by default),
# you would need to peer that VPC with the nonprod VPC and add return routes.
# To enable peering in future, set these values and re-apply 10-network:
#   peer_vpc_id   = "vpc-xxxxxxxxxxxxxxxxx"  # EKS VPC ID
#   peer_vpc_cidr = "192.168.0.0/16"         # EKS VPC CIDR
peer_vpc_id   = ""
peer_vpc_cidr = ""

# SSH access — restricted to specific IP only.
# Update this if your public IP changes (dynamic IP from ISP).
# Get current IP: curl -s https://api.ipify.org
# To disable SSH entirely: allowed_ssh_cidrs = []
allowed_ssh_cidrs = ["223.233.84.235/32"]

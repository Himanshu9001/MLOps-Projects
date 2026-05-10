# ─────────────────────────────────────────────────────────────────────────────
# prod/10-network/params/main.tfvars
#
# prod VPC: 10.2.0.0/16
# No overlap with:
#   existing MLflow VPC:  10.0.0.0/16
#   nonprod VPC:          10.1.0.0/16
#   EKS managed VPC:      192.168.0.0/16
# ─────────────────────────────────────────────────────────────────────────────

environment = "prod"
project     = "churn-mlops"
region      = "us-east-1"

vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24"]
private_subnet_cidrs = ["10.2.2.0/24", "10.2.3.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# NAT Gateway enabled in prod - nodes in private subnets need outbound
# internet for ECR image pulls and AWS API calls.
enable_nat_gateway = true
# false = one NAT GW per AZ - AZ failure does not affect other AZs.
single_nat_gateway = false

eks_cluster_name = "churn-mlops-prod"

# Fill these in after 40-kubernetes apply, then re-apply this stack.
peer_vpc_id   = ""
peer_vpc_cidr = ""

# SSH disabled in prod - SSM Session Manager only.
allowed_ssh_cidrs = []

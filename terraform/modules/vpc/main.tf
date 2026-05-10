# ─────────────────────────────────────────────────────────────────────────────
# modules/vpc/main.tf
#
# Creates: VPC, public subnets, private subnets, IGW, public route table,
#          NAT Gateway (optional), private route table, VPC peering (optional).
#
# Resource naming convention: ${var.project}-${var.environment}-<resource>
# Example: churn-mlops-nonprod-vpc, churn-mlops-prod-public-subnet-0
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Base tags applied to every resource in this module.
  # Merged with caller-provided additional_tags - caller tags take precedence
  # on conflict (merge() keeps the last key wins).
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "vpc"
    },
    var.additional_tags
  )

  name_prefix = "${var.project}-${var.environment}"

  # Boolean: should we create NAT Gateway resources at all?
  # Drives count on EIP and NAT GW resources.
  create_nat = var.enable_nat_gateway

  # How many NAT Gateways to create:
  #   single_nat_gateway = true  → 1 (sits in first public subnet)
  #   single_nat_gateway = false → one per AZ = length of private subnets
  nat_gw_count = local.create_nat ? (var.single_nat_gateway ? 1 : length(var.private_subnet_cidrs)) : 0

  # Boolean: should we create VPC peering resources?
  create_peering = var.peer_vpc_id != ""
}

# ─────────────────────────────────────────
# VPC
# ─────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ─────────────────────────────────────────
# Internet Gateway - public subnet outbound
# ─────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ─────────────────────────────────────────
# Public Subnets
# ─────────────────────────────────────────

resource "aws_subnet" "public" {
  # count iterates over public_subnet_cidrs - creates one subnet per CIDR.
  # count.index used to look up matching AZ from availability_zones list.
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # map_public_ip_on_launch: EC2 instances in public subnet get a public IP
  # automatically. The MLflow EC2 needs this to be reachable from outside.
  map_public_ip_on_launch = true

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index}"
    Tier = "public"

    # ALB Controller uses this tag to place internet-facing ALBs.
    # Without it: "no subnets found" error when creating LoadBalancer service.
    "kubernetes.io/role/elb" = var.eks_cluster_name != "" ? "1" : null

    # Cluster ownership tag - required for ALB and VPC CNI to work.
    "kubernetes.io/cluster/${var.eks_cluster_name}" = var.eks_cluster_name != "" ? "shared" : null
  })
}

# ─────────────────────────────────────────
# Private Subnets
# ─────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # No public IPs - private subnets have no direct internet path.
  # Outbound internet only via NAT Gateway when enable_nat_gateway = true.
  map_public_ip_on_launch = false

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index}"
    Tier = "private"

    # ALB Controller uses this tag to place internal ALBs.
    "kubernetes.io/role/internal-elb" = var.eks_cluster_name != "" ? "1" : null

    "kubernetes.io/cluster/${var.eks_cluster_name}" = var.eks_cluster_name != "" ? "shared" : null
  })
}

# ─────────────────────────────────────────
# Public Route Table
# ─────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Default route: all non-VPC traffic → IGW (internet access).
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# NAT Gateway (optional - enable_nat_gateway = true)
# ─────────────────────────────────────────

# Elastic IP for each NAT Gateway.
# nat_gw_count = 0 when enable_nat_gateway = false → no EIPs created.
resource "aws_eip" "nat" {
  count  = local.nat_gw_count
  domain = "vpc"

  # depends_on ensures IGW exists before EIP allocation.
  # AWS requires an attached IGW for VPC EIPs to be routable.
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gw_count

  allocation_id = aws_eip.nat[count.index].id

  # single_nat_gateway = true  → all NAT GWs in public subnet 0
  # single_nat_gateway = false → one per AZ, matching private subnet index
  subnet_id = var.single_nat_gateway ? aws_subnet.public[0].id : aws_subnet.public[count.index].id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-nat-gw-${count.index}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ─────────────────────────────────────────
# Private Route Tables
# ─────────────────────────────────────────

resource "aws_route_table" "private" {
  # One route table per private subnet.
  # When single_nat_gateway = false, each private subnet routes through its
  # own AZ-local NAT GW. If one AZ's NAT GW fails, only that AZ is affected.
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index}"
  })
}

# Default route for private subnets: non-VPC traffic → NAT Gateway.
# Only created when enable_nat_gateway = true.
resource "aws_route" "private_nat" {
  count = local.create_nat ? length(var.private_subnet_cidrs) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # single_nat_gateway = true  → all private subnets route through NAT GW 0
  # single_nat_gateway = false → each private subnet routes through its own NAT GW
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
}

# VPC peering return route: traffic to peer VPC CIDR → peering connection.
# Only created when peer_vpc_id is set AND NAT gateway exists (private subnets active).
resource "aws_route" "private_peering" {
  count = local.create_peering ? length(var.private_subnet_cidrs) : 0

  route_table_id            = aws_route_table.private[count.index].id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main[0].id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─────────────────────────────────────────
# VPC Peering (optional - peer_vpc_id != "")
# ─────────────────────────────────────────

# Creates peering request from this VPC to the EKS-managed VPC.
# count = 1 when peer_vpc_id is set, 0 otherwise.
resource "aws_vpc_peering_connection" "main" {
  count = local.create_peering ? 1 : 0

  vpc_id      = aws_vpc.main.id
  peer_vpc_id = var.peer_vpc_id
  auto_accept = true

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-peering"
  })
}

# Return route in public route table: traffic to peer VPC CIDR → peering connection.
# The MLflow EC2 (public subnet) uses this to respond to EKS pods.
resource "aws_route" "public_peering" {
  count = local.create_peering ? 1 : 0

  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main[0].id
}

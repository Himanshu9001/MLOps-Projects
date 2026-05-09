# ─────────────────────────────────────────────────────────────────────────────
# modules/security-groups/main.tf
#
# Four security groups. Each uses separate rule resources (not inline rules)
# to allow adding/removing individual rules without recreating the SG itself.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "security-groups"
    },
    var.additional_tags
  )

  name_prefix       = "${var.project}-${var.environment}"
  eks_rules_enabled = var.eks_vpc_cidr != ""
}

# ─────────────────────────────────────────
# MLflow EC2 Security Group
# ─────────────────────────────────────────

resource "aws_security_group" "mlflow" {
  name        = "${local.name_prefix}-mlflow-sg"
  description = "MLflow EC2 server - allows port 5000 from VPC and EKS VPC"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-mlflow-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "mlflow_port_vpc" {
  security_group_id = aws_security_group.mlflow.id
  description       = "Allow MLflow port 5000 from within VPC"
  from_port         = 5000
  to_port           = 5000
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "mlflow_port_eks" {
  count = local.eks_rules_enabled ? 1 : 0

  security_group_id = aws_security_group.mlflow.id
  description       = "Allow MLflow port 5000 from EKS VPC CIDR"
  from_port         = 5000
  to_port           = 5000
  ip_protocol       = "tcp"
  cidr_ipv4         = var.eks_vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "mlflow_ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.mlflow.id
  description       = "SSH access from ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "mlflow_egress_all" {
  security_group_id = aws_security_group.mlflow.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ─────────────────────────────────────────
# RDS Security Group
# ─────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL - allows 5432 from MLflow EC2 SG only"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_mlflow" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow PostgreSQL from MLflow EC2 SG only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.mlflow.id
}

resource "aws_vpc_security_group_egress_rule" "rds_egress_all" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ─────────────────────────────────────────
# ElastiCache Security Group
# ─────────────────────────────────────────

resource "aws_security_group" "elasticache" {
  name        = "${local.name_prefix}-elasticache-sg"
  description = "ElastiCache Redis - allows 6379 from EKS VPC only"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-elasticache-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_from_eks" {
  count = local.eks_rules_enabled ? 1 : 0

  security_group_id = aws_security_group.elasticache.id
  description       = "Allow Redis 6379 from EKS VPC CIDR"
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
  cidr_ipv4         = var.eks_vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_from_vpc" {
  security_group_id = aws_security_group.elasticache.id
  description       = "Allow Redis 6379 from within VPC"
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "elasticache_egress_all" {
  security_group_id = aws_security_group.elasticache.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ─────────────────────────────────────────
# EKS Nodes Security Group
# ─────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "EKS worker nodes - node-to-node and control plane communication"
  vpc_id      = var.vpc_id

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-eks-nodes-sg"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "owned"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow all traffic between nodes in this SG"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_control_plane_443" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "EKS control plane to nodes HTTPS"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_control_plane_kubelet" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "EKS control plane to kubelet API"
  from_port         = 10250
  to_port           = 10250
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_egress_all" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all outbound - nodes need ECR, S3, AWS APIs"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

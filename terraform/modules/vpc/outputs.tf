# ─────────────────────────────────────────────────────────────────────────────
# modules/vpc/outputs.tf
#
# Outputs consumed by other stacks via terraform_remote_state:
#   20-data       → vpc_id, private_subnet_ids, rds_subnet_group_name (future)
#   30-compute    → vpc_id, public_subnet_ids, private_subnet_ids
#   40-kubernetes → vpc_id, private_subnet_ids
#   security-groups module → vpc_id
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "The ID of the VPC. Used by security-groups, RDS, ElastiCache, and EKS modules."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The primary CIDR block of the VPC. Used by security group ingress rules."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs. Used by EC2 (MLflow), NAT GW placement, and ALB."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs. Used by RDS subnet group, ElastiCache, and EKS nodegroup."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "Public route table ID. Used to add VPC peering routes post-EKS creation."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs, one per AZ. Used for adding peering/transit routes."
  value       = aws_route_table.private[*].id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID attached to this VPC."
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs. Empty list when enable_nat_gateway = false."
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of NAT Gateways. Used to whitelist outbound traffic in external firewalls."
  value       = aws_eip.nat[*].public_ip
}

output "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID. Empty string when peer_vpc_id not set."
  value       = local.create_peering ? aws_vpc_peering_connection.main[0].id : ""
}

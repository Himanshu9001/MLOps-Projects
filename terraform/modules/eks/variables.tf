# ─────────────────────────────────────────────────────────────────────────────
# modules/eks/variables.tf
#
# Creates NEW EKS cluster - parallel to existing churn-mlops cluster.
# Naming: ${project}-${environment}
# Example: churn-mlops-nonprod
#
# Existing cluster is NOT touched.
# Blue-green cutover: ArgoCD app-of-apps repointed to new cluster,
# kubeconfig updated, DNS/ALB cutover last.
#
# Called by: live/nonprod/40-kubernetes and live/prod/40-kubernetes
# ─────────────────────────────────────────────────────────────────────────────

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be 'nonprod' or 'prod'."
  }
}

variable "project" {
  type        = string
  description = "Project name prefix. Example: churn-mlops"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project))
    error_message = "project must be lowercase alphanumeric + hyphens."
  }
}

variable "region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "cluster_version" {
  # Pin to a specific EKS version - never use latest.
  # EKS auto-upgrades are disabled by default but explicit pinning
  # prevents surprise upgrades during terraform apply.
  # Your existing cluster runs 1.34 - match it for parity.
  type        = string
  description = "Kubernetes version for EKS cluster. Example: 1.34"
  default     = "1.34"
}

variable "node_instance_type" {
  # t3.medium: 2 vCPU, 4 GB RAM - matches existing cluster nodes.
  # Fits the full stack: API pods, Kafka, Redis, Airflow, ArgoCD, Prometheus.
  # t3.large needed if adding Istio sidecars (Phase 14) - each sidecar ~50MB RAM.
  type        = string
  description = "EC2 instance type for EKS worker nodes. Example: t3.medium"
  default     = "t3.medium"
}

variable "node_desired_count" {
  type        = number
  description = "Desired number of worker nodes."
  default     = 3
}

variable "node_min_count" {
  type        = number
  description = "Minimum worker nodes (Cluster Autoscaler lower bound)."
  default     = 2
}

variable "node_max_count" {
  # 6 nodes: enough headroom for Cluster Autoscaler to expand during
  # load tests (Phase 17) or Airflow DAG bursts (Phase 12).
  type        = number
  description = "Maximum worker nodes (Cluster Autoscaler upper bound)."
  default     = 6
}

variable "private_subnet_ids" {
  # EKS nodes in private subnets - Phase 19 hardening.
  # NAT Gateway provides outbound internet for ECR pulls.
  # From vpc module: module.vpc.private_subnet_ids
  type        = list(string)
  description = "Private subnet IDs for EKS worker nodes. Nodes should NOT be in public subnets."
}

variable "node_security_group_ids" {
  # Additional SGs attached to nodes beyond the EKS-managed default SG.
  # From security-groups module: [module.security_groups.eks_nodes_sg_id]
  type        = list(string)
  description = "Additional security group IDs for EKS worker nodes."
  default     = []
}

variable "node_role_arn" {
  # From iam module: module.iam.eks_node_role_arn
  # Must have: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy,
  #            AmazonEC2ContainerRegistryReadOnly, AmazonEBSCSIDriverPolicy
  type        = string
  description = "IAM role ARN for EKS worker nodes. From iam module output."
}

variable "enable_cluster_creator_admin" {
  # When true: the IAM identity running terraform apply gets cluster-admin
  # access automatically. Without this, you cannot run kubectl after apply
  # until access entries are configured manually.
  type        = bool
  description = "Grant cluster-admin to the IAM identity running terraform apply."
  default     = true
}

variable "enabled_cluster_log_types" {
  # Control plane logs sent to CloudWatch.
  # api + audit minimum for production - audit log is your security trail.
  # authenticator: JWT token validation logs (IRSA debugging).
  # controllerManager + scheduler: needed for HPA/scheduling issue debugging.
  type        = list(string)
  description = "EKS control plane log types to enable."
  default     = ["api", "audit", "authenticator"]
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto all EKS resources."
  default     = {}
}

variable "ebs_csi_role_arn" {
  type        = string
  description = "IAM role ARN for EBS CSI driver IRSA. Required when IMDS is not accessible from pods."
  default     = ""
}

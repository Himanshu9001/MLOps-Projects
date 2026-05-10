# ─────────────────────────────────────────────────────────────────────────────
# modules/iam/main.tf
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.project}-${var.environment}"
  create_irsa = var.eks_oidc_provider_arn != "" && var.eks_oidc_provider_url != ""
}

# ─────────────────────────────────────────
# MLflow EC2 IAM Role + Instance Profile
# ─────────────────────────────────────────

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mlflow_ec2" {
  name               = "${local.name_prefix}-mlflow-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "mlflow_ec2_s3" {
  statement {
    sid    = "MLflowArtifactAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      var.artifacts_bucket_arn,
      "${var.artifacts_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "mlflow_ec2_s3" {
  name        = "${local.name_prefix}-mlflow-ec2-s3-policy"
  description = "Scoped S3 access for MLflow EC2 artifact store"
  policy      = data.aws_iam_policy_document.mlflow_ec2_s3.json
}

resource "aws_iam_role_policy_attachment" "mlflow_ec2_s3" {
  role       = aws_iam_role.mlflow_ec2.name
  policy_arn = aws_iam_policy.mlflow_ec2_s3.arn
}

# Allow MLflow EC2 to read RDS master password from Secrets Manager.
# Required for manage_master_user_password — EC2 userdata fetches the
# password at startup via aws secretsmanager get-secret-value.
# Scoped to rds!* prefix — only RDS-managed secrets, not all secrets.
resource "aws_iam_role_policy" "mlflow_ec2_rds_secret" {
  name = "${local.name_prefix}-mlflow-ec2-rds-secret"
  role = aws_iam_role.mlflow_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadRDSMasterSecret"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      # rds! prefix is the AWS-managed namespace for RDS secrets
      Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:rds!*"
    }]
  })
}

# SSM Session Manager - allows shell access without SSH or open ports.
# AmazonSSMManagedInstanceCore gives the SSM agent permission to:
#   - register with SSM service
#   - receive session commands
#   - stream session output back to SSM
# No inbound SG rule needed - agent opens outbound HTTPS to SSM endpoint.
resource "aws_iam_role_policy_attachment" "mlflow_ec2_ssm" {
  role       = aws_iam_role.mlflow_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mlflow" {
  name = "${local.name_prefix}-mlflow-ec2-profile"
  role = aws_iam_role.mlflow_ec2.name
}

# ─────────────────────────────────────────
# IRSA Role for EKS Pods
# ─────────────────────────────────────────

data "aws_iam_policy_document" "irsa_assume_role" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  count              = local.create_irsa ? 1 : 0
  name               = "${local.name_prefix}-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[0].json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "irsa_s3" {
  statement {
    sid    = "PodS3Access"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      var.artifacts_bucket_arn,
      "${var.artifacts_bucket_arn}/*",
      var.dvc_bucket_arn,
      "${var.dvc_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "irsa_s3" {
  count       = local.create_irsa ? 1 : 0
  name        = "${local.name_prefix}-irsa-s3-policy"
  description = "Scoped S3 access for EKS pods via IRSA"
  policy      = data.aws_iam_policy_document.irsa_s3.json
}

resource "aws_iam_role_policy_attachment" "irsa_s3" {
  count      = local.create_irsa ? 1 : 0
  role       = aws_iam_role.irsa[0].name
  policy_arn = aws_iam_policy.irsa_s3[0].arn
}

data "aws_iam_policy_document" "irsa_secrets" {
  statement {
    sid    = "PodSecretsAccess"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project}/*"
    ]
  }
}

resource "aws_iam_policy" "irsa_secrets" {
  count       = local.create_irsa ? 1 : 0
  name        = "${local.name_prefix}-irsa-secrets-policy"
  description = "Secrets Manager read access for EKS pods via IRSA"
  policy      = data.aws_iam_policy_document.irsa_secrets.json
}

resource "aws_iam_role_policy_attachment" "irsa_secrets" {
  count      = local.create_irsa ? 1 : 0
  role       = aws_iam_role.irsa[0].name
  policy_arn = aws_iam_policy.irsa_secrets[0].arn
}

# ─────────────────────────────────────────
# EKS Node IAM Role
# ─────────────────────────────────────────

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# REMOVED: AmazonEBSCSIDriverPolicy from node role — moved to IRSA below.
# Node role should NOT have EBS CSI permissions — that violates least privilege.
# All EBS CSI permissions now flow through the dedicated IRSA role below,
# scoped to ebs-csi-controller-sa ServiceAccount only.
# resource "aws_iam_role_policy_attachment" "eks_ebs_csi" { ... } ← removed

# ─────────────────────────────────────────
# EBS CSI Driver IRSA Role
#
# WHY dedicated IRSA over node role attachment:
#   Node role attachment = every pod on every node gets EBS provisioning rights
#   IRSA = only the ebs-csi-controller-sa ServiceAccount gets those rights
#
# Trust policy scoped to ebs-csi-controller-sa in kube-system — matches
# the ServiceAccount that the EBS CSI controller pod runs as.
#
# IMPORT NOTE: this role was created manually on 2026-05-09.
# Run terraform import before first apply:
#   terraform import module.iam.aws_iam_role.ebs_csi #     churn-mlops-nonprod-ebs-csi-role
# ─────────────────────────────────────────

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count              = local.create_irsa ? 1 : 0
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role[0].json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = local.create_irsa ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "ClusterAutoscalerActions"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler-policy"
  description = "Minimal 9-action policy for Cluster Autoscaler"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.eks_node.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "aws_iam_instance_profile" "eks_node" {
  name = "${local.name_prefix}-eks-node-profile"
  role = aws_iam_role.eks_node.name
}

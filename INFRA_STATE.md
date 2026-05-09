# Infrastructure State Tracking
# Update this file after every Terraform pass and resource creation.
# DO NOT commit passwords to git — use placeholder <secret> for sensitive values.

---

## AWS Account
| Key | Value |
|-----|-------|
| Account ID | 011528270076 |
| Region | us-east-1 |

---

## Existing Infrastructure (OLD — do not modify)

### Existing EKS Cluster
| Key | Value |
|-----|-------|
| Cluster Name | churn-mlops |
| EC2 MLflow IP | 98.86.0.163 |
| EC2 Instance ID | i-0d3ebb196f1ed53b8 |
| RDS Endpoint | mlflow-db.c3o84wgsio2m.us-east-1.rds.amazonaws.com |
| S3 Artifacts | churn-mlops-artifacts |
| S3 DVC | churn-mlops-dvc-store |
| ECR API | 011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api |
| ElastiCache | churn-mlops-redis.1lzaia.0001.use1.cache.amazonaws.com:6379 |
| IRSA Role | arn:aws:iam::011528270076:role/churn-mlops-irsa-role |
| ALB URL | a3bb3c740fb3747d88b007cade5f9bd4-405783512.us-east-1.elb.amazonaws.com |

---

## New Parallel Infrastructure (NONPROD — blue-green target)

### Pass 1 — State Backend (00-s3-backend) ✅
| Key | Value |
|-----|-------|
| State Bucket | churn-mlops-nonprod-terraform-state |
| Lock Table | churn-mlops-nonprod-terraform-locks |

### Pass 2 — Network (10-network) ✅
| Key | Value |
|-----|-------|
| VPC ID | vpc-0da4e83c946d24180 |
| VPC CIDR | 10.1.0.0/16 |
| Public Subnet | subnet-08ccd2db9b6d42780 (us-east-1a) |
| Private Subnet 1 | subnet-0019307f263563bc8 (us-east-1a) |
| Private Subnet 2 | subnet-0f3f3c198af07b34b (us-east-1b) |
| Public Route Table | rtb-0cf1e87b54830cc03 |
| Private RT 1 | rtb-0d064aa1c9f25f4ca |
| Private RT 2 | rtb-047dd3ef4e72d14d7 |
| IGW | igw-098d4e741d3650333 |
| NAT Gateway | nat-0ba03377828c3a783 (subnet-08ccd2db9b6d42780) |
| MLflow SG | sg-0a081e1bb2e9895d0 |
| RDS SG | sg-0648a51613b7b83b8 |
| ElastiCache SG | sg-0d8f2df91d63baa4a |
| EKS Nodes SG | sg-03b45698e809841f0 |

### Pass 3 — Data (20-data) ✅
| Key | Value |
|-----|-------|
| S3 Artifacts | churn-mlops-nonprod-artifacts |
| S3 Artifacts ARN | arn:aws:s3:::churn-mlops-nonprod-artifacts |
| S3 DVC | churn-mlops-nonprod-dvc-store |
| S3 DVC ARN | arn:aws:s3:::churn-mlops-nonprod-dvc-store |
| RDS Identifier | churn-mlops-nonprod-mlflow-db |
| RDS Endpoint | churn-mlops-nonprod-mlflow-db.c3o84wgsio2m.us-east-1.rds.amazonaws.com |
| RDS Port | 5432 |
| RDS DB Name | mlflow |
| RDS Username | mlflow |
| RDS Password | <secret - set via TF_VAR_db_password> |
| ElastiCache ID | churn-mlops-nonprod-redis |
| Redis Endpoint | churn-mlops-nonprod-redis.1lzaia.0001.use1.cache.amazonaws.com |
| Redis Port | 6379 |

### Pass 4 — Compute (30-compute) ✅
| Key | Value |
|-----|-------|
| MLflow EC2 Instance ID | i-063cfab3185b59739 |
| MLflow Public IP (EIP) | 3.90.73.230 |
| MLflow Private IP | 10.1.1.233 |
| MLflow Tracking URI | http://3.90.73.230:5000 |
| MLflow EC2 Role | churn-mlops-nonprod-mlflow-ec2-role |
| EKS Node Role ARN | arn:aws:iam::011528270076:role/churn-mlops-nonprod-eks-node-role |
| SSH Key | ~/.ssh/churn-mlops-nonprod-mlflow.pem |

### Pass 5 — Kubernetes (40-kubernetes) ✅
| Key | Value |
|-----|-------|
| EKS Cluster Name | churn-mlops-nonprod |
| EKS Endpoint | https://C7FC9A623638582F0E7BB6B4F744F7C4.gr7.us-east-1.eks.amazonaws.com |
| EKS Cluster SG | sg-0ee94d71ee1bfe45c |
| OIDC Provider ARN | arn:aws:iam::011528270076:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/C7FC9A623638582F0E7BB6B4F744F7C4 |
| OIDC Provider URL | oidc.eks.us-east-1.amazonaws.com/id/C7FC9A623638582F0E7BB6B4F744F7C4 |
| EBS CSI Role | arn:aws:iam::011528270076:role/churn-mlops-nonprod-ebs-csi-role |
| kubeconfig command | aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1 |

### Pass 6 — IRSA Role (30-compute re-apply) ⏳
| Key | Value |
|-----|-------|
| IRSA Role ARN | arn:aws:iam::011528270076:role/churn-mlops-nonprod-irsa-role |

### Pass 7 — VPC Peering (10-network re-apply) ⏳
| Key | Value |
|-----|-------|
| EKS VPC ID | (fill after aws eks describe-cluster) |
| EKS VPC CIDR | (fill after aws ec2 describe-vpcs) |
| Peering Connection ID | (fill after Pass 7 completes) |

### Pass 8 — Verification ✅
| Key | Value |
|-----|-------|
| New ALB URL | a5c8f2a5b4b0c4f51bc198d2dfb3295e-1851458498.us-east-1.elb.amazonaws.com |
| New Grafana URL | a5c8f2a5b4b0c4f51bc198d2dfb3295e-1851458498.us-east-1.elb.amazonaws.com |
| New ArgoCD URL | a5c8f2a5b4b0c4f51bc198d2dfb3295e-1851458498.us-east-1.elb.amazonaws.com |

---

## Manual Resources (created outside Terraform)
| Resource | Name | ARN | Notes |
|----------|------|-----|-------|
| EBS CSI IRSA Role | churn-mlops-nonprod-ebs-csi-role | arn:aws:iam::011528270076:role/churn-mlops-nonprod-ebs-csi-role | Created manually - move to iam module after cutover |

---

## Blue-Green Cutover Checklist
- [x] Pass 6 complete - IRSA role created
- [x] Pass 7 SKIPPED - same VPC
- [ ] setup-networking.sh run on new cluster
- [ ] ArgoCD synced - all apps Healthy
- [ ] MLflow data migrated (pg_dump old RDS -> pg_restore new RDS)
- [ ] S3 data synced (aws s3 sync old buckets -> new buckets)
- [ ] Helm values.yaml updated with new IRSA role ARN
- [ ] Smoke test: prediction API returns 200
- [ ] Smoke test: MLflow UI accessible
- [ ] Smoke test: Grafana dashboards loading
- [ ] DNS/ALB cutover executed
- [ ] Old cluster monitored for 24hrs after cutover
- [ ] Old cluster deleted
- [ ] Old EC2/RDS/ElastiCache deleted
- [ ] Manual IAM resources moved to Terraform

---

## Daily Workflow Commands
```bash
# Morning startup
./scripts/setup-mlflow-infra.sh
eksctl create cluster -f cluster.yaml    # old cluster (if needed)
./scripts/setup-networking.sh            # old cluster

# New cluster kubeconfig
aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1

# Old cluster kubeconfig
aws eks update-kubeconfig --name churn-mlops --region us-east-1

# Switch contexts
kubectl config use-context arn:aws:eks:us-east-1:011528270076:cluster/churn-mlops-nonprod
kubectl config use-context arn:aws:eks:us-east-1:011528270076:cluster/churn-mlops

# Evening teardown (new infra - keep running until cutover)
# Old infra teardown
./scripts/teardown-networking.sh
eksctl delete cluster --name churn-mlops --region us-east-1
./scripts/teardown-mlflow-infra.sh
```

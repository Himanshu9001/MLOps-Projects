# Infrastructure and model-serving diagrams

What the `nonprod` environment runs on AWS, where the model lives, and how a prediction is served.
Built from `terraform/live/nonprod`, the serving code (`app/main.py`, `streaming/stream_processor.py`,
`src/register_model.py`, `dags/churn_retraining.py`) and the README.

The diagrams are plain SVG files in [`diagrams/`](./diagrams) and follow the viewer's light or dark theme.

## AWS topology

![AWS topology](./diagrams/aws-topology.svg)

Inbound traffic enters through the internet gateway to a load balancer that Kubernetes creates, then reaches the
prediction API pods on port 8000. Everything stateful or compute-heavy sits in private subnets; the MLflow server is
the one instance in the public subnet. Pods reach MLflow on 5000 and Redis on 6379. Outbound calls to ECR, S3,
Secrets Manager and AWS APIs go through the single NAT gateway. RDS accepts 5432 from the MLflow security group only.

Dashed boxes are not managed by Terraform: the load balancer (created by the Kubernetes Service), the Karpenter role
and SQS queue, and the GitHub Actions OIDC role. The workloads inside EKS come from the README and
`scripts/bootstrap-new-cluster.sh`.

## Where the model lives

![Where the model lives](./diagrams/model-storage.svg)

The model is a folder of files in S3. The MLflow database only records which version is live. At startup the API calls
`mlflow.sklearn.load_model("models:/churn-prediction-model@production")`; MLflow answers with the version behind the
`production` alias, and the pod downloads the files from S3 using its IRSA role. The MLflow server does not proxy
files (`--default-artifact-root s3://…`, no `--serve-artifacts`), so clients read and write S3 directly. Promoting a
new model means moving the alias; running pods keep the old model until they restart.

## Weekly retraining

![Weekly retraining](./diagrams/weekly-retraining.svg)

The `churn_retraining` Airflow DAG runs Sundays at 02:00 UTC, one pod per step. Moving the alias does nothing for
running pods, so the last step restarts the rollout and the new pods load the new model.

## How one prediction is served

![One prediction](./diagrams/prediction-request.svg)

The model is already in the pod's memory, so a request never touches MLflow or S3. The caller sends all 19 customer
fields; the API does not look anything up in the feature store or Redis. Risk levels: probability ≥ 0.70 HIGH,
≥ 0.40 MEDIUM, otherwise LOW.

## Streaming path

![Streaming path](./diagrams/streaming-path.svg)

The stream processor is another client of `/predict`. It caches each result in Redis for one hour and publishes an
alert to `churn-alerts` when the probability is 0.70 or higher. Partitions cap useful parallelism at three pods, even
though KEDA allows five.

## How changes reach AWS

![Delivery paths](./diagrams/delivery-paths.svg)

Application images and infrastructure follow separate paths. Both authenticate to AWS with an OIDC role, so no
long-lived keys are stored in GitHub.

## Terraform stacks

Each stack has its own state and reads earlier stacks through remote state. Apply order is 00 → 50.

| Stack | What it creates |
|-------|-----------------|
| `00-s3-backend` | State bucket (versioned, SSE-KMS), DynamoDB lock table, KMS key. Uses local state because it creates the remote one. |
| `10-network` | VPC 10.1.0.0/16, one public and two private subnets, internet gateway, one NAT gateway, route tables, security groups for MLflow, RDS, Redis and EKS nodes. |
| `20-data` | S3 artifacts and dvc-store buckets, RDS PostgreSQL 14 (master password managed by Secrets Manager), ElastiCache Redis 7.1, three ECR repositories. |
| `30-compute` | MLflow EC2 instance with Elastic IP and key pair, EC2 role, EKS node role. |
| `40-kubernetes` | EKS 1.34 cluster, SPOT managed node group, OIDC provider, add-ons vpc-cni, coredns, kube-proxy and aws-ebs-csi-driver. |
| `50-iam` | IRSA role for the prediction API, EBS CSI role, Image Updater role. Reads the OIDC provider from `40-kubernetes`, so one pass is enough. |

## Who can connect to what

From the security-group rules in `terraform/modules/security-groups`.

| Resource | Allows |
|----------|--------|
| MLflow EC2 | Port 5000 from the VPC and the EKS VPC CIDR; SSH 22 from one allowed address. |
| RDS | Port 5432 from the MLflow security group only. |
| ElastiCache Redis | Port 6379 from the VPC and the EKS VPC CIDR. |
| EKS nodes | All traffic between nodes; 443 and 10250 from the control plane; all outbound for ECR, S3 and AWS APIs. |

## Known gaps found while tracing the code

Accurate at the time of writing; remove an item once it is fixed.

- **Retraining DAG points at the old environment.** `dags/churn_retraining.py` uses MLflow at `10.0.1.225` and the ECR
  repo `churn-prediction-api`. Nonprod uses MLflow at `10.1.1.233` and `churn-mlops-nonprod-prediction-api`.
- **Old bucket defaults.** `src/register_model.py` and `src/validate_data.py` default to `churn-mlops-artifacts`; the
  nonprod bucket is `churn-mlops-nonprod-artifacts`.
- **API autoscaler watches a queue nothing fills.** The KEDA scaler for the prediction API reads the Redis list
  `prediction_queue`, but no code in the repo pushes to it.
- **No `/explain` endpoint.** `app/main.py` serves only `/`, `/health`, `/predict` and `/metrics`; SHAP and LIME run
  in the retraining DAG.
- **New models need a restart.** The model loads once at startup.

## Not drawn

- The `prod` stacks in `terraform/live/prod` (this covers the running nonprod environment).
- The older eksctl cluster `churn-mlops`, marked as legacy in `INFRA_STATE.md`.
- VPC peering, which is not used: both clusters share one VPC and the peering variables in `10-network` are empty.

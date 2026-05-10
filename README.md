Readme · MD
Copy

# 🚀 End-to-End MLOps Pipeline — Customer Churn Prediction
 
[![CI/CD Pipeline](https://github.com/Himanshu9001/MLOps-Projects/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Himanshu9001/MLOps-Projects/actions)
[![Terraform](https://github.com/Himanshu9001/MLOps-Projects/actions/workflows/terraform.yml/badge.svg)](https://github.com/Himanshu9001/MLOps-Projects/actions)
![Python](https://img.shields.io/badge/Python-3.12-blue)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.34-blue)
![Terraform](https://img.shields.io/badge/Terraform-1.9-purple)
![MLflow](https://img.shields.io/badge/MLflow-2.22-orange)
![FastAPI](https://img.shields.io/badge/FastAPI-0.136-green)
![Airflow](https://img.shields.io/badge/Airflow-3.2.0-red)
![Kafka](https://img.shields.io/badge/Kafka-4.1.0-black)
 
A production-grade, end-to-end MLOps pipeline built from scratch — covering data versioning, experiment tracking, model registry, containerization, CI/CD, Kubernetes deployment, monitoring, drift detection, MLSecOps, real-time streaming, feature store, automated retraining, GitOps, canary deployments, and full Terraform infrastructure automation.
 
**Model:** Random Forest | **Accuracy:** 79.7% | **ROC AUC:** 0.8358 | **Dataset:** Telco Churn (7,043 customers)
 
```bash
# Live API
curl http://<ALB_URL>/health
# {"status":"healthy","model_loaded":true}
 
curl -X POST http://<ALB_URL>/predict \
  -H "Content-Type: application/json" \
  -d '{"tenure":12,"Contract":0,"MonthlyCharges":65.5,"TotalCharges":786.0,...}'
# {"churn":0,"probability":0.3792,"risk_level":"LOW","message":"Customer is likely to stay."}
```
 
---
 
## 📋 Table of Contents
 
- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Phases Completed](#phases-completed)
  - [Phase 1 — Data Versioning](#phase-1--data-versioning-dvc--s3)
  - [Phase 2 — Experiment Tracking](#phase-2--experiment-tracking-mlflow)
  - [Phase 3 — Model Registry](#phase-3--model-registry)
  - [Phase 4 — Docker + FastAPI](#phase-4--docker--fastapi)
  - [Phase 5 — CI/CD](#phase-5--cicd-github-actions)
  - [Phase 6 — Kubernetes EKS](#phase-6--kubernetes-eks)
  - [Phase 7 — Monitoring](#phase-7--monitoring-prometheus--grafana)
  - [Phase 8 — Drift Detection](#phase-8--data-drift-detection-evidently-ai)
  - [Phase 9 — MLSecOps](#phase-9--mlsecops)
  - [Phase 10 — Streaming Pipeline](#phase-10--streaming-pipeline-kafka--redis)
  - [Phase 11 — Feature Store](#phase-11--feature-store-feast--redis)
  - [Phase 12 — Auto Retraining](#phase-12--auto-retraining-airflow)
  - [Phase 13 — GitOps](#phase-13--gitops-argocd)
  - [Phase 14 — Progressive Delivery](#phase-14--progressive-delivery-argo-rollouts--istio)
  - [Phase 15 — Data Quality](#phase-15--data-quality-great-expectations)
  - [Phase 16 — Explainability](#phase-16--explainability-shap--lime)
  - [Phase 17 — Load Testing](#phase-17--load-testing-locust)
  - [Phase 18 — ElastiCache Migration](#phase-18--elasticache-migration)
  - [Phase 19 — Security Hardening](#phase-19--security-hardening)
  - [Phase 20 — Terraform Infrastructure](#phase-20--terraform-infrastructure-migration-current)
- [Infrastructure Resources](#infrastructure-resources)
- [CI/CD Pipelines](#cicd-pipelines)
- [How to Run](#how-to-run)
- [API Reference](#api-reference)
- [Key Engineering Decisions](#key-engineering-decisions)
- [Troubleshooting](#troubleshooting)
- [Infrastructure](#infrastructure)
- [Getting Started](#getting-started)
- [Daily Operations](#daily-operations)
- [API Reference](#api-reference)
- [Roadmap](#roadmap)
---
 
## 🎯 Project Overview
 
**Problem:** Predict customer churn for a telecom company using structured tabular data.
 
**Dataset:** Telco Customer Churn (7,043 customers, 19 features)
 
**ML Model:** Random Forest Classifier
- Accuracy: 79.7%
- ROC AUC: 0.8358
- F1 Score: 0.5719
**Business Value:**
- Identify customers likely to churn
- Risk levels: HIGH / MEDIUM / LOW
- Enable proactive retention campaigns
- Real-time churn scoring via streaming pipeline
---
 
## 🏗️ Architecture
 
```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA LAYER                                │
│  Raw Data (S3) ──DVC──▶ Processed Data (S3)                     │
│  Feature Store (Feast) ──▶ Online Store (Redis)                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      TRAINING LAYER                              │
│  preprocess.py ──▶ train.py ──▶ MLflow (EC2) ──▶ RDS PostgreSQL │
│                              └──▶ S3 (artifacts)                │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      REGISTRY LAYER                              │
│  register_model.py ──▶ MLflow Model Registry                    │
│  Staging ──▶ Production aliases                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      CI/CD LAYER                                 │
│  GitHub Push ──▶ GitHub Actions                                 │
│  ├── Run Tests (pytest 18 tests)                                │
│  ├── Security Scan (Trivy)                                      │
│  └── Build + Push Docker Image to AWS ECR                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      SERVING LAYER                               │
│  AWS EKS (Kubernetes)                                           │
│  ├── FastAPI Deployment (2 replicas)                            │
│  ├── AWS ALB LoadBalancer                                       │
│  └── HPA (auto-scales 1-3 pods)                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                   OBSERVABILITY LAYER                            │
│  Prometheus ──▶ Grafana Dashboards                              │
│  └── Evidently AI ──▶ Data Drift Reports ──▶ MLflow             │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                   STREAMING LAYER                                │
│  Customer Events ──▶ Kafka ──▶ Stream Processor                 │
│  ──▶ Churn Prediction ──▶ Redis Cache                           │
│  └──▶ High Risk Alerts ──▶ Kafka Alert Topic                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                   ORCHESTRATION LAYER                            │
│  Airflow DAGs                                                   │
│  ├── feature_materialization (daily)                            │
│  └── churn_retraining (weekly)                                  │
└─────────────────────────────────────────────────────────────────┘
```
 
---
 
## 🛠️ Tech Stack
 
| Category | Tools |
|----------|-------|
| **Data Versioning** | DVC, AWS S3 |
| **Experiment Tracking** | MLflow 2.22, PostgreSQL (RDS) |
| **ML Framework** | scikit-learn, pandas, numpy |
| **API Serving** | FastAPI, Uvicorn, Pydantic |
| **Containerization** | Docker, AWS ECR |
| **Orchestration** | Kubernetes (EKS 1.34), Helm |
| **CI/CD** | GitHub Actions |
| **Monitoring** | Prometheus, Grafana, kube-prometheus-stack |
| **Drift Detection** | Evidently AI 0.7.21 |
| **Security** | Trivy, IRSA, AWS Secrets Manager, OPA Gatekeeper |
| **Networking** | Kubernetes Network Policies, VPC Peering |
| **Streaming** | Kafka (Strimzi KRaft), Redis, confluent-kafka |
| **Feature Store** | Feast 0.40.1, Redis, S3 |
| **Orchestration** | Apache Airflow 3.2.0, KubernetesExecutor |
| **Infrastructure** | AWS EC2, RDS PostgreSQL, S3, EKS, ALB, EBS |
| **IaC-1** | eksctl, Helm, bash scripts, Terraform (modular, S3 backend, DynamoDB locking) |
| **Testing** | pytest, httpx, pytest-asyncio |
| **GitOps** | ArgoCD v2.14.9, Cluster Autoscaler |
| **Progressive Delivery** | Argo Rollouts v1.8.3, Istio v1.29.2 |
| **Image Auto-Deploy** | ArgoCD Image Updater v1.1.1 (polls ECR, deploys on new image — no git commits) |
| **Progressive Delivery** | Argo Rollouts v1.8.3, Istio v1.29.2 |
| **Service Mesh** | Istio v1.29.2 (VirtualService, DestinationRule, mTLS) |
| **Data Quality** | Great Expectations 1.4.4 |
| **Explainability** | SHAP 0.46.0, LIME 0.2.0.1 |
| **Load Testing** | Locust 2.32.4 |
| **Managed Cache** | AWS ElastiCache (Redis 7.1, cache.t3.micro, private subnets) |
| **IaC** | Terraform 1.9 (modular, layered, S3 remote state, native S3 file locking), eksctl, Helm |
| **Distributed Training** | Ray 2.40.0 (KubeRay), Ray Tune, Ray Train, Ray Data |
| **Node Autoprovisioning** | Karpenter v1.3.3 (EC2NodeClass, NodePool) |
| **Event-Driven Autoscaling** | KEDA v2.16.0 (Kafka lag scaler, Redis list scaler) |
| **Pod Networking** | AWS VPC CNI with Prefix Delegation (110 pods/node vs 17 default) |
| **Log Aggregation** | Loki v2.9.3 (loki-stack), Promtail DaemonSet |
| **Distributed Tracing** | Tempo v2.9.0 (single binary mode) |
| **Observability Stack** | Prometheus + Grafana + Loki + Tempo (unified) |
 
---
 
## 📁 MLOps-Projects/
├── 📱 app/
│   └── main.py                         # FastAPI + Prometheus instrumentation + lifespan handler
│
├── 🧠 src/
│   ├── preprocess.py                   # Data cleaning, encoding, train/test split
│   ├── train.py                        # MLflow experiment tracking, model_validated tag
│   ├── register_model.py               # Auto-select best run, dynamic S3 path, alias promotion
│   ├── drift_detection.py              # Evidently 0.7.21, DriftedColumnsCount metric
│   ├── validate_data.py                # Great Expectations — 34-expectation data quality gate
│   └── explain.py                      # SHAP TreeExplainer + LIME tabular explainer + MLflow logging
│
├── 🧪 tests/
│   ├── test_api.py                     # 9 API tests, mocks mlflow.sklearn.load_model
│   └── test_preprocess.py              # 9 preprocessing unit tests
│
├── ☸️  k8s/                             # Raw Kubernetes manifests
│   ├── kafka/
│   │   ├── kafka-cluster.yaml          # Strimzi KRaft Kafka cluster (Kafka 4.1.0, no Zookeeper)
│   │   └── kafka-topics.yaml           # customer-events + churn-alerts (3 partitions, 24h retention)
│   ├── gatekeeper/
│   │   ├── constraint-templates.yaml   # OPA Rego policies (NoRoot, RequireLimits, NoPrivileged)
│   │   └── constraints.yaml            # Policy enforcement scoped to churn-mlops namespace
│   ├── redis/
│   │   └── redis.yaml                  # Redis Deployment + Service + NetworkPolicy (raw manifest)
│   ├── argo-rollouts/
│   │   ├── kustomization.yaml          # Kustomize ref → Argo Rollouts v1.8.3 install.yaml
│   │   └── namespace.yaml
│   ├── argocd/
│   │   └── kustomization.yaml          # Kustomize ref → ArgoCD v2.14.9 install.yaml
│   ├── istio/
│   │   └── kustomization.yaml          # Documents: istioctl install --set profile=default -y
│   ├── cluster-autoscaler.yaml         # Cluster Autoscaler autodiscover (ASG tags, max=6)
│   ├── servicemonitor.yaml             # Prometheus ServiceMonitor (named port 'http')
│   └── stream-processor-deployment.yaml
│
├── 🔄 argocd/                          # GitOps — App of Apps pattern
│   ├── app-of-apps.yaml                # Root Application — bootstraps all child apps
│   ├── image-updater.yaml              # ImageUpdater CR — watches ECR, deploys on new image
│   ├── image-updater-configmap.yaml    # ECR registry config (pullsecret, credsexpire 10h)
│   └── apps/
│       ├── churn-api.yaml              # Manages helm/churn-mlops/ (Helm, ignoreDiff: replicas)
│       ├── kafka.yaml                  # Manages k8s/kafka/ (prune: false — stateful)
│       ├── gatekeeper-policies.yaml    # Manages k8s/gatekeeper/ (retry backoff for CRD ordering)
│       ├── monitoring.yaml             # Manages Prometheus+Grafana (admissionWebhooks: false)
│       ├── redis.yaml                  # Manages k8s/redis/ raw manifest
│       └── stream-processor.yaml      # Manages k8s/stream-processor-deployment.yaml
│
├── ⎈  helm/
│   ├── churn-mlops/                    # Application Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                 # minReplicas=2, maxReplicas=5, CPU=50%, IRSA SA
│   │   └── templates/
│   │       ├── deployment.yaml         # Gated: {{- if .Values.deployment.enabled }} (disabled)
│   │       ├── rollout.yaml            # Argo Rollouts Rollout — canary strategy + Istio routing
│   │       ├── analysis-template.yaml  # Prometheus AnalysisTemplate — success rate > 95%
│   │       ├── istio-traffic.yaml      # VirtualService (named route) + DestinationRule (subsets)
│   │       ├── service.yaml
│   │       ├── hpa.yaml                # Targets Rollout (not Deployment), CPU=50%, max=5
│   │       ├── namespace.yaml
│   │       ├── secret.yaml
│   │       ├── serviceaccount.yaml     # IRSA IAM role annotation
│   │       ├── secretproviderclass.yaml # AWS Secrets Manager CSI integration
│   │       ├── servicemonitor.yaml
│   │       └── networkpolicies.yaml    # Default deny-all + explicit allow rules
│   └── monitoring/
│       └── values.yaml                 # Grafana admin123, LoadBalancer, 7d retention
│
├── 🏗️  terraform/                       # All infrastructure as code (Phase 20)
│   ├── versions.tf                     # Pinned provider versions (AWS ~>5.80, Helm, K8s, TLS)
│   ├── modules/                        # Reusable, environment-agnostic modules
│   │   ├── vpc/                        # VPC, subnets, IGW, NAT Gateway, route tables
│   │   ├── security-groups/            # Separate rule resources (no inline — avoids SG recreation)
│   │   ├── s3/                         # Versioned buckets, lifecycle policies, encryption
│   │   ├── rds/                        # PostgreSQL 14, gp3, encrypted, performance insights
│   │   ├── elasticache/                # Redis 7.1, single-node nonprod / replication group prod
│   │   ├── ec2/                        # MLflow server, AL2023 AMI, SSM enabled, EIP, TLS key pair
│   │   ├── iam/                        # IRSA role, EKS node role (9-action), EC2 role, Image Updater role
│   │   ├── eks/                        # Managed node group, OIDC provider, 4 addons, SPOT
│   │   └── ecr/                        # 3 repos, lifecycle policy (keep 10), scan-on-push, force_delete
│   └── live/
│       ├── nonprod/                    # Each stack: backends/ + params/ + stacks/
│       │   ├── 00-s3-backend/          # State bucket + native S3 file locking (no DynamoDB)
│       │   ├── 10-network/             # VPC + security groups (reads: none)
│       │   ├── 20-data/                # RDS + ElastiCache + S3 + ECR (reads: 10-network)
│       │   ├── 30-compute/             # MLflow EC2 + IAM roles + Image Updater IRSA (reads: 10-network, 20-data, 40-kubernetes)
│       │   └── 40-kubernetes/          # EKS cluster + node group + 4 addons (reads: 10-network, 30-compute)
│       └── prod/                       # Same 5 stacks, IMMUTABLE ECR tags, keep 20 images
│
├── 🔄 streaming/
│   ├── Dockerfile.streaming            # confluent-kafka based stream processor
│   └── Dockerfile.materialize          # numpy==1.26.4 pinned, Feast materialization
│
├── 🗄️  feature_store/
│   └── churn_feature_repo/
│       └── feature_repo/
│           ├── feature_store.yaml      # Feast config (online=Redis, offline=S3)
│           └── features.py             # Entity, FeatureView, PushSource definitions
│
├── 📅 dags/
│   ├── feature_materialization.py      # Daily Feast materialize Airflow DAG
│   └── churn_retraining.py             # Weekly DAG: validate→drift→preprocess→train→explain→register→deploy
│
├── 🔍 great_expectations/
│   └── create_expectations.py          # Creates + validates 34-expectation GE suite locally
│
├── 📊 load_tests/
│   ├── locustfile.py                   # PredictionUser + HeavyPredictionUser scenarios
│   ├── RESULTS.md                      # Load test results + SLA assessment + HPA observations
│   └── results/                        # CSV output from headless runs (gitignored)
│
├── 📊 grafana/dashboards/              # Custom Grafana dashboard JSON
│
├── 🔧 scripts/
│   ├── setup-mlflow-infra.sh           # Start/create EC2 + RDS + S3 (idempotent)
│   ├── teardown-mlflow-infra.sh        # Stop EC2 + RDS (preserves data)
│   ├── setup-iam.sh                    # ONE-TIME: IAM policies + IRSA role creation
│   ├── setup-networking.sh             # Legacy eksctl cluster setup (pre-Phase 20)
│   │                                   #   Step 1.5 — OIDC association + trust policy update
│   │                                   #   Step 1.6 — VPC CNI network policy (eBPF)
│   │                                   #   Step 2-6 — VPC Peering + routes + SG
│   │                                   #   Step 10  — Secrets CSI Driver + patch
│   │                                   #   Step 11  — OPA Gatekeeper operator
│   │                                   #   Step 12  — Strimzi operator
│   │                                   #   Step 13  — Prometheus + Grafana
│   │                                   #   Step 14  — EBS CSI Driver + StorageClass
│   │                                   #   Step 15  — Airflow + RBAC
│   │                                   #   Step 16  — ArgoCD install
│   │                                   #   Step 17  — Bootstrap App of Apps
│   ├── bootstrap-new-cluster.sh        # Terraform cluster bootstrap (15 steps, idempotent, tested)
│   │                                   #   Step 1   — Verify cluster context
│   │                                   #   Step 2   — Secrets Store CSI Driver
│   │                                   #   Step 3   — OPA Gatekeeper + policies
│   │                                   #   Step 4   — Kafka (Strimzi)
│   │                                   #   Step 5   — Prometheus + Grafana
│   │                                   #   Step 6   — EBS StorageClass
│   │                                   #   Step 7   — Airflow
│   │                                   #   Step 8   — ArgoCD (pinned v2.14.9)
│   │                                   #   Step 9   — Argo Rollouts (pinned v1.8.3)
│   │                                   #   Step 10  — Istio
│   │                                   #   Step 11  — Helm chart (delete Istio resources first)
│   │                                   #   Step 12  — ArgoCD App of Apps bootstrap
│   │                                   #   Step 13  — ServiceMonitor
│   │                                   #   Step 14  — Image Updater configmap + CR
│   │                                   #   Step 15  — ECR credentials for Image Updater
│   ├── migrate-mlflow-model.py         # Blue-green MLflow model migration script
│   │                                   #   Copies model artifact S3 old→new bucket
│   │                                   #   Registers model in new MLflow registry
│   │                                   #   Sets production alias on new cluster
│   ├── teardown-networking.sh          # Evening: delete peering + clean up
│   └── materialize_features.py         # Feature materialization script
│
├── ⚙️  .github/workflows/
│   ├── ci-cd.yml                       # Application CI/CD: Test → Trivy Scan → Build → Push ECR
│   │                                   #   OIDC auth (no long-lived AWS keys)
│   │                                   #   ECR: churn-mlops-nonprod-prediction-api
│   │                                   #   No git commits (Image Updater handles deployment)
│   └── terraform.yml                   # Infrastructure CI/CD (Phase 20)
│                                       #   PR: plan all changed stacks → comment on PR
│                                       #   Merge: manual approval → apply saved plan artifact
│                                       #   Daily: drift detection (-detailed-exitcode)
│                                       #   OIDC auth, concurrency group, stack isolation
│
├── 🐳 Dockerfile                       # Multi-stage, apt-get upgrade for CVEs, non-root UID 1000
├── cluster.yaml                        # eksctl config — 3x t3.medium (legacy, pre-Phase 20)
├── .trivyignore                        # Accepted OS CVEs with no fix available in Debian
│
├── 📋 requirements-api.txt             # fastapi==0.136.1, shap==0.46.0, lime==0.2.0.1
├── 📋 requirements-dev.txt             # pytest, httpx, prometheus-client
├── 📋 requirements.txt                 # Full training environment dependencies
│
├── 📖 README.md                        # Full project documentation (this file)
├── 🔧 troubleshooting_phase20.md       # 42 real issues with root cause + fix (Phase 20)
├── 🔧 TROUBLESHOOTING.md              # 40+ issues with root cause + solutions (Phases 1-19)
├── 📅 README-ops.md                    # Daily operations runbook + resource IDs
└── 📋 INFRA_STATE.md                   # Live infrastructure resource IDs + blue-green checklist
```
 
---

## ✅ Phases Completed

### Phase 1 — Data Versioning (DVC + S3)

**What:** Version control for ML datasets using DVC with AWS S3 as remote storage.

- DVC tracks data files using MD5 content-addressable storage
- Only small `.dvc` pointer files go to Git — actual data goes to S3
- S3 bucket: `churn-mlops-dvc-store`

```bash
dvc add data/raw/churn.csv
dvc push   # uploads to S3
dvc pull   # downloads from S3
```

---

### Phase 2 — Experiment Tracking (MLflow)

**What:** Track every training experiment — parameters, metrics, artifacts, graphs.

- MLflow server on EC2 t3.small with Elastic IP
- Backend store: RDS PostgreSQL
- Artifact store: S3 bucket `churn-mlops-artifacts`

| Metric | Value |
|--------|-------|
| Accuracy | 79.70% |
| F1 Score | 0.5719 |
| Precision | 0.6497 |
| Recall | 0.5107 |
| ROC AUC | 0.8358 |

---

### Phase 3 — Model Registry

**What:** Promote best models through Staging → Production lifecycle.

- Auto-selects best validated run by ROC AUC
- Uses `model_validated=true` tag to filter eligible runs
- Alias-based promotion (MLflow 2.x standard)

---

### Phase 4 — Docker + FastAPI

**What:** Containerize the model as a REST API with production-grade Docker best practices.

- Multi-stage build (builder + runtime)
- Non-root user (UID 1000)
- HEALTHCHECK instruction
- Minimal base image (`python:3.12-slim`)

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API info |
| `/health` | GET | Health check |
| `/predict` | POST | Churn prediction |
| `/metrics` | GET | Prometheus metrics |
| `/docs` | GET | Swagger UI |

---

### Phase 5 — CI/CD (GitHub Actions)

**What:** Automated testing, security scanning, and Docker image publishing on every push.

**Pipeline:**
```
Push to main
    ↓
Job 1: Run Tests (pytest 18 tests)
    ↓
Job 2: Security Scan (Trivy - CRITICAL severity)
    ↓
Job 3: Build + Push Docker Image to ECR
```

---

### Phase 6 — Kubernetes EKS

**What:** Deploy to production Kubernetes with auto-scaling, health checks, and rolling updates.

- EKS 1.34 on 2x t3.medium nodes
- HPA: min 1, max 3 pods (CPU 70%, Memory 80%)
- VPC Peering between MLflow VPC and EKS VPC
- AWS ALB LoadBalancer

---

### Phase 7 — Monitoring (Prometheus + Grafana)

**What:** Full observability stack with pre-built K8s dashboards and custom API metrics.

- ServiceMonitor for automatic Prometheus scraping
- Custom Grafana dashboard for API metrics
- Node CPU/Memory, Pod CPU/Memory tracking

---

### Phase 8 — Data Drift Detection (Evidently AI)

**What:** Detect when production data distribution shifts from training data.

- Statistical tests per feature
- Drift share calculated with configurable threshold
- HTML report + MLflow logging

```bash
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/drift_detection.py --threshold 0.1
```

---

### Phase 9 — MLSecOps

#### 9.1 — Trivy Security Scanning
- Integrated into CI/CD pipeline
- Scans Docker image for CRITICAL vulnerabilities
- `.trivyignore` for accepted OS CVEs with no fix

#### 9.2 — IRSA (IAM Roles for Service Accounts)
- OIDC provider associated with EKS cluster
- IAM role `churn-mlops-irsa-role` scoped to `churn-prediction-sa` ServiceAccount
- Least-privilege S3 access (2 buckets only)
- Eliminates node-level IAM permissions

#### 9.3 — AWS Secrets Manager
- MLflow URI stored encrypted in AWS Secrets Manager
- Secrets Store CSI Driver mounts secret into pod
- No plaintext secrets in Git or K8s etcd

#### 9.4 — Kubernetes Network Policies
- Default deny-all in `churn-mlops` namespace
- Explicit allow rules for API (port 8000), MLflow (5000), Kafka (9092), Redis (6379), DNS (53)
- VPC CNI network policy controller enabled

#### 9.5 — OPA Gatekeeper
- ConstraintTemplates: no-root, require-limits, no-privileged
- Constraints scoped to `churn-mlops` namespace
- Admission webhook denies non-compliant deployments

---

### Phase 10 — Streaming Pipeline (Kafka + Redis)

**What:** Event-driven real-time churn scoring pipeline.

**Architecture:**
```
Customer Events → Kafka (customer-events) → Stream Processor
    ↓                                            ↓
Churn Prediction API ←──────────────────────────┘
    ↓
Redis Cache (1hr TTL) + Kafka Alerts (churn-alerts)
```

- Strimzi Kafka operator with KRaft mode (no Zookeeper)
- Kafka 4.1.0 with 3-partition topics
- confluent-kafka Python client (librdkafka based)
- Verified: 120 events processed, 20 high-risk alerts at 73.49%

---

### Phase 11 — Feature Store (Feast + Redis)

**What:** Central repository for ML features — eliminates training-serving skew.

**Components:**
- **Offline Store (S3):** Historical features as parquet for training
- **Online Store (Redis):** Latest features per customer for serving (<5ms retrieval)
- **Materialization:** Batch sync from S3 → Redis
- **PushSource:** Real-time feature updates

**Test Results:**
| Test | Result | Time |
|------|--------|------|
| Existing customer retrieval | ✅ | ~300ms (port-forward overhead) |
| New customer (returns None) | ✅ | ~309ms |
| Feature update via PushSource | ✅ | ~694ms |
| End-to-end fetch + predict | ✅ | ~921ms |

In-cluster latency would be <5ms.

---

### Phase 12 — Auto Retraining (Airflow)

**What:** Scheduled ML pipeline automation via Apache Airflow 3.2.0.

**DAGs:**

| DAG | Schedule | Tasks |
|-----|----------|-------|
| `feature_materialization` | Daily 1 AM | S3 → Redis feature sync (18s) |
| `churn_retraining` | Weekly Sunday 2 AM | drift check → preprocess → train → register → deploy |

**Infrastructure:**
- Airflow 3.2.0 on EKS with KubernetesExecutor
- Git-sync from GitHub (60s polling)
- PostgreSQL on EBS PVC
- RBAC ClusterRole for pod spawning across namespaces

**Verified:** `feature_materialization` DAG runs successfully — 5634 customers materialized in 18 seconds.

---

## 📖 Detailed Phase Documentation

The sections below provide in-depth implementation details, design decisions, commands, and gotchas for phases 9–12.

---

## ✅ Phase 9 — MLSecOps

### 9.1 — Trivy Security Scanning

**What:** Automated container image vulnerability scanning integrated into CI/CD pipeline.

**Why:** Every Docker image has OS packages and Python dependencies that may contain known CVEs. Trivy scans the image before it gets pushed to ECR — if CRITICAL vulnerabilities exist with fixes available, the pipeline fails and the image never reaches production.

**How it works:**
```
GitHub Push
    ↓
Job 1: Run Tests (pytest)
    ↓
Job 2: Security Scan (Trivy)
  - Scans image layers for CVEs
  - Fails on CRITICAL severity only
  - ignore-unfixed: true (skips CVEs with no available fix)
    ↓ (only if scan passes)
Job 3: Build + Push to ECR
```

**Key decisions:**
- `severity: CRITICAL` only — HIGH with no fix = accepted risk, documented in `.trivyignore`
- `ignore-unfixed: true` — avoids noise from unpatched OS CVEs
- `apt-get upgrade -y` in Dockerfile — proactively fixes OS CVEs at build time
- `fastapi==0.136.1` — pulls `starlette==0.52.1` which has no CVEs (vs older versions)

**CI/CD snippet:**
```yaml
security-scan:
  needs: test
  steps:
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ env.IMAGE_TAG }}
        format: table
        severity: CRITICAL
        ignore-unfixed: true
        exit-code: 1
        trivyignores: .trivyignore
```

---

### 9.2 — IRSA (IAM Roles for Service Accounts)

**What:** Pod-level AWS credential scoping using OIDC federation between Kubernetes and AWS IAM.

**Why:** Without IRSA, every pod on a node inherits the node's broad IAM role. A compromised pod could access any AWS resource the node can reach. IRSA scopes credentials to a specific Kubernetes ServiceAccount — only pods using `churn-prediction-sa` get S3 access. All other pods get nothing.

**How it works internally:**
```
EKS exposes OIDC endpoint (unique per cluster)
    ↓
AWS IAM trusts this OIDC endpoint as identity provider
    ↓
Pod starts with annotated ServiceAccount:
  eks.amazonaws.com/role-arn: arn:aws:iam::...:role/churn-mlops-irsa-role
    ↓
EKS pod identity webhook injects into pod:
  AWS_ROLE_ARN=arn:aws:iam::...:role/churn-mlops-irsa-role
  AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
    ↓
AWS SDK exchanges token for temporary STS credentials (AssumeRoleWithWebIdentity)
    ↓
Pod accesses S3 with scoped permissions — no static keys anywhere
```

**Trust policy — locked to one specific ServiceAccount:**
```json
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:sub":
        "system:serviceaccount:churn-mlops:churn-prediction-sa",
      "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:aud":
        "sts.amazonaws.com"
    }
  }
}
```

**IAM policies attached to role:**
- `churn-mlops-s3-policy` — GetObject, PutObject, ListBucket on 2 specific buckets only
- `churn-mlops-secrets-policy` — GetSecretValue on `churn-mlops/*` prefix only

**Important:** OIDC ID changes every time you recreate the cluster. `setup-networking.sh` runs `eksctl utils associate-iam-oidc-provider` and updates the trust policy automatically on every cluster creation.

**Setup scripts:**
```bash
./scripts/setup-iam.sh          # One-time: creates IAM policies, role, stores secret
./scripts/setup-networking.sh   # Daily: associates OIDC + updates trust policy
```

**Verification:**
```bash
kubectl describe pod -n churn-mlops | grep "AWS_ROLE_ARN\|web-identity"
# AWS_ROLE_ARN: arn:aws:iam::011528270076:role/churn-mlops-irsa-role
# AWS_WEB_IDENTITY_TOKEN_FILE: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

---

### 9.3 — AWS Secrets Manager

**What:** Encrypted secret storage with automatic injection into pods via Secrets Store CSI Driver.

**Why:** Kubernetes native Secrets are only base64-encoded (not encrypted). AWS Secrets Manager stores secrets encrypted with AES-256 via KMS, provides full CloudTrail audit trail, supports automatic rotation, and fine-grained IAM access control.

**Components:**
- **AWS Secrets Manager** — stores `churn-mlops/mlflow-tracking-uri` as JSON
- **Secrets Store CSI Driver** — K8s DaemonSet that fetches secrets from external providers
- **AWS Provider** — translates Secrets Manager API calls for the CSI driver
- **SecretProviderClass** — K8s resource defining which secret to fetch and how to expose it

**How it works:**
```
Pod starts
    ↓
CSI Driver sees SecretProviderClass annotation on pod volume
    ↓
AWS Provider calls secretsmanager:GetSecretValue (using IRSA credentials)
    ↓
Secret fetched and mounted as file at /mnt/secrets-store/
    ↓
secretObjects syncs to K8s Secret: mlflow-secrets-csi
    ↓
Pod reads MLFLOW_TRACKING_URI env var from K8s Secret
```

**SecretProviderClass:**
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: mlflow-secrets-provider
  namespace: churn-mlops
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "churn-mlops/mlflow-tracking-uri"
        objectType: "secretsmanager"
        jmesPath:
          - path: "MLFLOW_TRACKING_URI"
            objectAlias: "MLFLOW_TRACKING_URI"
  secretObjects:
    - secretName: mlflow-secrets-csi
      type: Opaque
      data:
        - objectName: "MLFLOW_TRACKING_URI"
          key: tracking-uri
```

**CSIDriver patch required** for IRSA token projection:
```bash
kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
```

---

### 9.4 — Kubernetes Network Policies

**What:** Pod-level firewall rules that restrict inter-pod communication to only what is explicitly allowed.

**Why:** Without Network Policies, every pod in the cluster can freely communicate with every other pod. A compromised prediction API pod could reach Redis, Kafka brokers, or internal services it should never touch. Network Policies enforce the principle of least privilege at the network level.

**Enforcement:** VPC CNI network policy controller uses eBPF (not iptables) — enabled via:
```bash
aws eks update-addon --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}'
```

**Note:** This must be re-enabled after every cluster recreation — automated in `setup-networking.sh` Step 1.6.

**Policies in `churn-mlops` namespace:**

| Policy | Pod Selector | Type | Ports/Destinations |
|--------|-------------|------|-------------------|
| `default-deny-all` | All pods `{}` | Ingress + Egress | DENY EVERYTHING |
| `allow-ingress-churn-api` | `app=churn-prediction-api` | Ingress | 8000/TCP from any pod + ALB (0.0.0.0/0) |
| `allow-egress-churn-api` | `app=churn-prediction-api` | Egress | 5000 → 10.0.1.225 (MLflow), 443 (AWS APIs), 53 (DNS) |
| `allow-ingress-stream-processor` | `app=churn-stream-processor` | Ingress | Empty (no external ingress) |
| `allow-egress-stream-processor` | `app=churn-stream-processor` | Egress | 9092 (Kafka), 6379 (Redis), 8000 (API), 443, 53 |

**Default-deny pattern:** Start with deny-all, then explicitly allow what's needed. This means any new pod deployed without a matching NetworkPolicy is completely isolated — safe by default.

**Verification:**
```bash
kubectl get networkpolicy -n churn-mlops
# NAME                             POD-SELECTOR
# default-deny-all                 <none>
# allow-ingress-churn-api          app=churn-prediction-api
# allow-egress-churn-api           app=churn-prediction-api
# allow-ingress-stream-processor   app=churn-stream-processor
# allow-egress-stream-processor    app=churn-stream-processor
```

---

### 9.5 — OPA Gatekeeper

**What:** Kubernetes admission controller that evaluates every resource creation/update against Rego policies before allowing it into the cluster.

**Why:** Gatekeeper is the last line of defense. Even if a developer forgets to set security context, resource limits, or accidentally creates a privileged container — Gatekeeper blocks it before any pod is created. Policies-as-code, version controlled, cluster-wide enforcement.

**How it works:**
```
kubectl apply -f deployment.yaml
    ↓
Kubernetes API Server
    ↓ (ValidatingWebhookConfiguration)
Gatekeeper evaluation webhook
    ↓
Rego policy evaluation
    ↓ (violation found)
Request DENIED — clear error message returned to user
    ↓ (no violation)
Resource created normally
```

**Two-layer design:**

`ConstraintTemplate` = the Rego logic (what to check):
```rego
package k8snoroot
pod_spec = input.review.object.spec.template.spec {
  input.review.object.kind == "Deployment"
}
violation[{"msg": msg}] {
  not pod_spec.securityContext.runAsNonRoot == true
  container := pod_spec.containers[_]
  msg := sprintf("Container %v: pod securityContext.runAsNonRoot must be true", [container.name])
}
```

`Constraint` = enforcement config (where to apply):
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNoRoot
metadata:
  name: no-root-containers
spec:
  enforcementAction: deny      # block the request
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    namespaces:
      - churn-mlops             # scoped to this namespace only
```

**Policies enforced:**

| Policy | What it blocks |
|--------|---------------|
| `K8sNoRoot` | Deployments without `runAsNonRoot: true` at pod level |
| `K8sRequireLimits` | Containers without CPU and memory limits |
| `K8sNoPrivileged` | Containers with `privileged: true` |

**Test:**
```bash
kubectl apply --dry-run=server -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-violation
  namespace: churn-mlops
spec:
  template:
    spec:
      containers:
        - name: nginx
          image: nginx
          # No securityContext, no resources.limits
EOF
# Error: admission webhook "validation.gatekeeper.sh" denied the request:
# [no-root-containers] Container nginx: pod securityContext.runAsNonRoot must be true
```

**Important:** CRDs must be established before Constraints are applied. `setup-networking.sh` uses `kubectl wait --for=condition=established` between the two steps.

---

## ✅ Phase 10 — Streaming Pipeline (Kafka + Redis)

**What:** Real-time event-driven churn scoring pipeline. Customer events flow continuously through Kafka, get scored by the prediction model, results cached in Redis, and high-risk customers flagged immediately.

**Why:** The REST API is reactive — someone must call it. A streaming pipeline is proactive — as soon as a customer event occurs (new charge, plan change, login pattern), it gets scored automatically and instantly. This enables real-time retention campaigns before the customer has already decided to leave.

**Architecture:**
```
Customer Activity
    ↓
Kafka Topic: customer-events (3 partitions, 24h retention)
    ↓
Stream Processor Pod (confluent-kafka consumer)
    ├── Calls /predict on churn-prediction-api
    ├── Caches result in Redis (key: feast:customer:cust_001, TTL: 1hr)
    └── If probability >= 0.7:
            ↓
        Kafka Topic: churn-alerts (3 partitions)
            ↓
        Downstream: CRM, email, retention campaigns
```

### Kafka — Strimzi Operator (KRaft Mode, Kafka 4.1.0)

**Why Strimzi:** Production-grade Kubernetes operator for Kafka. Manages full Kafka lifecycle (create, upgrade, scale, heal) as Kubernetes CRDs. Instead of manually managing Kafka processes, you define desired state in YAML and Strimzi reconciles it.

**Why KRaft:** Traditional Kafka required Zookeeper — a separate distributed coordination service. KRaft (Kafka Raft) is Kafka's built-in consensus protocol that replaces Zookeeper. Result: fewer moving parts, faster recovery, simpler operations.

**KRaft roles in single-node dev setup:**
```yaml
spec:
  replicas: 1
  roles:
    - controller   # manages cluster metadata (leader election, partition assignment)
    - broker       # handles message storage, replication, consumer coordination
```
In production: separate controller and broker node pools, minimum 3 of each.

**Partitions and replicas explained:**

Partitions split a topic into parallel lanes for throughput:
```
Topic: customer-events (3 partitions)
Partition 0: [cust_001_event] [cust_004_event] [cust_007_event] ...
Partition 1: [cust_002_event] [cust_005_event] [cust_008_event] ...
Partition 2: [cust_003_event] [cust_006_event] [cust_009_event] ...
```
3 partitions = 3 parallel consumer tasks = 3x throughput.

Replicas are copies of partitions across brokers for fault tolerance:
- Dev setup: `replicas: 1` — single copy, acceptable for dev
- Production: `replicas: 3` — survives loss of 1 broker with zero data loss

**Topic configuration:**
```yaml
spec:
  partitions: 3
  replicas: 1
  config:
    retention.ms: 86400000    # 24 hours — events kept for replay
    cleanup.policy: delete    # delete old events (vs compact = keep latest)
```

### Stream Processor — confluent-kafka

**Why confluent-kafka over kafka-python:**
- `kafka-python` and its fork `kafka-python-ng` don't support Kafka 4.x properly
- `confluent-kafka` is built on `librdkafka` — a C library, the most battle-tested Kafka client
- Officially maintained by Confluent (the company behind Kafka)
- Supports all Kafka versions including 4.x
- Used in production at Uber, Netflix, LinkedIn, DoorDash

**Processing logic:**
```python
while True:
    msg = consumer.poll(timeout=1.0)
    event = json.loads(msg.value())
    customer_id = event["customer_id"]
    features = event["features"]

    # Score the customer
    prediction = requests.post(f"{API_URL}/predict", json=features).json()

    # Cache in Redis
    r.setex(f"churn:prediction:{customer_id}", 3600, json.dumps(prediction))

    # Alert if high risk
    if prediction["probability"] >= 0.7:
        producer.produce("churn-alerts", value=json.dumps({
            "customer_id": customer_id,
            "churn_probability": prediction["probability"],
            "action": "IMMEDIATE_RETENTION_REQUIRED"
        }))
```

**Network Policy consideration:** Stream processor needs egress to Kafka (9092), Redis (6379), and API (8000). These are explicitly allowed in the `allow-egress-stream-processor` NetworkPolicy.

**API URL:** Stream processor calls the prediction API via ALB hostname (not ClusterIP) due to EKS VPC CNI eBPF service routing behavior with Network Policies enabled.

**Verified results:**
```
Stats: processed=120, alerts=20
HIGH RISK ALERT: customer high_risk_000 - probability 73.49%
Alert delivered to churn-alerts partition 0
Alert delivered to churn-alerts partition 1
Alert delivered to churn-alerts partition 2
```

### Redis — Online Cache

**Why Redis for caching:** Sub-millisecond reads, simple key-value structure, TTL support. Perfect for prediction result caching — if the same customer is scored multiple times within an hour, Redis returns the cached result without calling the model again.

**Current setup:** Bitnami Redis, single master, no persistence (cache-only). In Phase 19 (Hardening), this will be replaced with AWS ElastiCache — managed Redis with multi-AZ failover, persistence, and no Bitnami dependency.

**Commands:**
```bash
# Send test events
python3 -c "
import json, random
events = [{'customer_id': f'cust_{i:03d}', 'features': {...}} for i in range(100)]
with open('/tmp/test-events.txt', 'w') as f:
    f.write('\n'.join([json.dumps(e) for e in events]))
"

kubectl run kafka-producer -n kafka --rm --restart=Never --stdin=true \
  --image=quay.io/strimzi/kafka:latest-kafka-4.1.0 \
  -- bin/kafka-console-producer.sh \
  --bootstrap-server churn-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092 \
  --topic customer-events < /tmp/test-events.txt

# Monitor stream processor
kubectl logs -n churn-mlops -l app=churn-stream-processor -f

# Check alerts topic
kubectl run kafka-consumer -n kafka --rm -it --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.1.0 \
  -- bin/kafka-console-consumer.sh \
  --bootstrap-server churn-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092 \
  --topic churn-alerts --from-beginning --timeout-ms 5000
```

---

## ✅ Phase 11 — Feature Store (Feast + Redis)

**What:** Central repository for ML features that provides consistent feature values for both training and serving, eliminating training-serving skew.

**The core problem — training-serving skew:**

Without a feature store, features are computed in multiple places:
```
Data Scientist: trains model using pandas, computes tenure as (today - signup_date)
Mobile App: computes tenure differently at serving time
Result: model was trained on feature X but served feature Y → silent accuracy drop
```

With a feature store, features are computed ONCE:
```
Feature Pipeline → S3 (offline) → materialization → Redis (online)
Training reads from S3 → same logic
Serving reads from Redis → same logic
Result: guaranteed consistency
```

**Three core concepts:**

**1. Entity** — the primary key (what you're looking up):
```python
customer = Entity(name="customer_id", description="Unique customer ID")
```

**2. FeatureView** — a group of related features for an entity:
```python
customer_churn_features = FeatureView(
    name="customer_churn_features",
    entities=[customer],
    ttl=timedelta(days=7),      # features expire after 7 days → stale data protection
    schema=[
        Field(name="tenure", dtype=Int32),
        Field(name="MonthlyCharges", dtype=Float32),
        Field(name="Contract", dtype=Int32),
        # ... 16 more features
    ],
    source=customer_push_source,
)
```

**3. DataSource** — where features come from:
- `FileSource` — parquet files in S3 (offline/batch)
- `PushSource` — real-time writes for immediate online store updates

### Offline Store (S3)

Stores ALL historical feature values with timestamps. Used for training to ensure point-in-time correct features (no data leakage).

**Schema:**
```
customer_id | gender | tenure | MonthlyCharges | Contract | ... | event_timestamp
cust_0000   |   1    |   35   |     49.20      |    0     | ... | 2026-05-05T00:00:00Z
cust_0001   |   1    |   15   |     75.10      |    0     | ... | 2026-05-05T00:00:00Z
```

**Generate and upload:**
```bash
python3 scripts/generate_feast_features.py  # reads train.csv, adds customer_id + timestamp
aws s3 cp /tmp/customer_features.parquet \
  s3://churn-mlops-artifacts/feast/customer_features.parquet
```

### Online Store (Redis)

Stores ONLY the latest feature values per customer. Sub-millisecond retrieval for real-time serving.

**Key format:** Binary Feast serialization (not human-readable plain text)
**TTL:** 7 days — after this, Feast returns `None` indicating stale/missing data

### Materialization

The process of copying features from offline (S3) → online (Redis). Only syncs records newer than the last materialization run.

```bash
feast materialize-incremental "$(date -u +%Y-%m-%dT%H:%M:%S)"
# Materializing 5634 records from S3 to Redis...
# 100%|████████████████████████████████| 5634/5634 [00:11<00:00, 473it/s]
```

### PushSource — Real-time Updates

When a customer changes their plan, contract, or other attributes:
```python
# Immediately update Redis without waiting for batch materialization
store.push("customer_push_source", updated_df)
```

### Feature Configuration

`feature_store.yaml`:
```yaml
project: churn_feature_repo
registry:
  registry_type: file
  path: s3://churn-mlops-artifacts/feast/registry.pb  # registry in S3 (shared across machines)
provider: aws
offline_store:
  type: file                                           # parquet files
online_store:
  type: redis
  connection_string: "redis-master.redis.svc.cluster.local:6379"  # in-cluster URL
```

### Test Results

```python
# Test 1: Existing customer
features = store.get_online_features(
    features=["customer_churn_features:tenure", "customer_churn_features:Contract"],
    entity_rows=[{"customer_id": "cust_0001"}]
).to_dict()
# Result: tenure=[15], Contract=[0] — 913ms first hit, 325ms subsequent hits

# Test 2: New customer
features = store.get_online_features(..., entity_rows=[{"customer_id": "cust_9999"}]).to_dict()
# Result: tenure=[None], Contract=[None] — handled gracefully

# Test 3: Feature update
store.push("customer_push_source", df_with_Contract_2)
features = store.get_online_features(...)
# Result: Contract=[2] — Redis updated immediately (694ms)

# Test 4: End-to-end
features = store.get_online_features(ALL_19_FEATURES, ...)  # 410ms
prediction = requests.post(f"{ALB}/predict", json=features)  # 718ms
# Result: churn=0, probability=0.2191, risk=LOW — total 1128ms
```

Note: 300ms+ is port-forward network overhead. In-cluster would be <5ms.

### Feature Retrieval Script

`feature_store/feature_retrieval.py`:
```python
from feast import FeatureStore

def get_customer_features(customer_ids: list[str]) -> list[dict]:
    store = FeatureStore(repo_path="feature_store/churn_feature_repo/feature_repo")
    feature_vector = store.get_online_features(
        features=CUSTOMER_FEATURES,
        entity_rows=[{"customer_id": cid} for cid in customer_ids]
    ).to_dict()
    # Returns list of feature dicts, one per customer
    # Returns None values for unknown customers
```

---

## ✅ Phase 12 — Auto Retraining (Airflow)

**What:** Scheduled ML pipeline automation using Apache Airflow 3.2.0 on EKS with KubernetesExecutor.

**Why Airflow:** Industry standard workflow orchestrator. DAGs (Directed Acyclic Graphs) define task dependencies with built-in scheduling, retries, alerting, audit logs, and a web UI. Used at Airbnb (where it was created), Twitter, LinkedIn, Lyft, and most major data-driven companies.

**Why KubernetesExecutor:** Each Airflow task runs as an isolated Kubernetes pod. No shared workers, proper resource isolation, scales to zero when idle, full K8s native — the production standard for ML workloads on Kubernetes.

### Architecture

```
GitHub repo (main branch)
    │
    │ git-sync polls every 60 seconds
    ▼
/opt/airflow/dags/repo/dags/
    │
    │ dag-processor parses Python files
    ▼
Airflow scheduler
    │
    │ Schedule trigger (cron) or manual trigger
    ▼
KubernetesExecutor spawns pod in churn-mlops namespace
    │
    │ Task runs using IRSA credentials (S3, ECR access)
    ▼
Pod completes → Airflow marks task success/failure
```

### Git-Sync — GitOps for DAGs

Every `git push` to the `dags/` folder deploys automatically. No manual `kubectl cp` or pod restarts needed.

```
Developer edits dags/feature_materialization.py
    ↓
git push origin main
    ↓ (within 60 seconds)
git-sync sidecar in dag-processor pod detects new commit
    ↓
Updates symlink: /opt/airflow/dags/repo → .worktrees/<new_commit>/
    ↓
dag-processor re-parses DAG files
    ↓
Airflow UI shows updated DAG (version increments: v1 → v2 → v3)
```

The git-sync sidecar runs in 3 pods simultaneously (scheduler, dag-processor, triggerer) — each independently keeps its DAG volume fresh.

### DAG 1: feature_materialization

**Schedule:** `0 1 * * *` — Every day at 1 AM UTC

**Purpose:** Sync latest customer features from S3 (offline store) to Redis (online store) so the prediction API always serves fresh features.

**Why daily and not real-time:** Customer features like tenure, total charges, and contract type change slowly. Daily materialization is sufficient. Real-time updates for important events (contract change, cancellation request) are handled via the PushSource in Phase 11.

```python
with DAG(dag_id="feature_materialization", schedule="0 1 * * *", ...) as dag:
    materialize_features = KubernetesPodOperator(
        name="feast-materialize",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-materialize:latest",
        env_vars={
            "REDIS_HOST": "redis-master.redis.svc.cluster.local",
            "S3_BUCKET": "churn-mlops-artifacts",
            "S3_KEY": "feast/customer_features.parquet",
        },
        service_account_name="churn-prediction-sa",  # IRSA for S3 access
    )
```

**Dedicated image (`churn-materialize`):**
Critical package versions:
- `numpy==1.26.4` — must be pinned! pyarrow==15.0.2 was compiled against NumPy 1.x. Using NumPy 2.x causes `AttributeError: _ARRAY_API not found` crash.
- `pandas==2.2.3`, `pyarrow==15.0.2`, `boto3==1.37.1`, `redis==5.0.1`

**Materialization script logic:**
```python
# 1. Connect to Redis
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)

# 2. Load parquet from S3
obj = s3.get_object(Bucket=S3_BUCKET, Key=S3_KEY)
df = pd.read_parquet(io.BytesIO(obj["Body"].read()))

# 3. Write to Redis in batches of 500 (pipeline for efficiency)
pipe = r.pipeline()
for _, row in df.iterrows():
    key = f"feast:customer:{row['customer_id']}"
    features = {col: str(row[col]) for col in df.columns if col not in ["customer_id", "event_timestamp"]}
    pipe.hset(key, mapping=features)
    pipe.expire(key, 7 * 24 * 3600)  # 7 day TTL
    if count % 500 == 0:
        pipe.execute()
        pipe = r.pipeline()
```

**Verified:** 5634 customers materialized in 18 seconds — Success on first try (try_number=1).

### DAG 2: churn_retraining

**Schedule:** `0 2 * * 0` — Every Sunday at 2 AM UTC

**Purpose:** Full end-to-end model retraining pipeline — from data to deployed model.

**Task dependency chain:**
```
check_drift ──▶ preprocess ──▶ train ──▶ register_model ──▶ restart_api
```

| Task | What it does | Failure behavior |
|------|-------------|-----------------|
| `check_drift` | Runs drift_detection.py with 30% threshold | Alerts but continues (drift is informational) |
| `preprocess` | Runs preprocess.py, saves train/test splits to S3 | Stops pipeline if fails |
| `train` | Trains RandomForest, logs params/metrics/artifacts to MLflow | Stops pipeline if fails |
| `register_model` | Auto-selects best validated run by ROC AUC, promotes to production alias | Stops pipeline if fails |
| `restart_api` | `kubectl rollout restart deployment/churn-prediction-api` — new pods load new model | Stops pipeline if fails |

All tasks use `churn-prediction-api` image (already has all ML dependencies) and run in `churn-mlops` namespace with IRSA credentials.

### Infrastructure Details

**PostgreSQL on EBS:** Airflow metadata (DAG runs, task states, logs) stored in PostgreSQL on an EBS PVC.

Requires:
1. EBS CSI Driver addon: `aws eks create-addon --addon-name aws-ebs-csi-driver`
2. EBSCSIDriverPolicy attached to node IAM role
3. StorageClass with `Immediate` binding (not `WaitForFirstConsumer` — causes scheduling deadlock)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate   # Critical: must be Immediate, not WaitForFirstConsumer
parameters:
  type: gp2
```

**RBAC for cross-namespace pod spawning:**

Airflow tasks run as `airflow-worker` ServiceAccount. KubernetesPodOperator creates pods in `churn-mlops` namespace — requires explicit RBAC permission.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: airflow-pod-launcher
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
kind: ClusterRoleBinding
subjects:
  - kind: ServiceAccount
    name: airflow-worker       # the actual executor SA in Airflow 3.x
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-scheduler
    namespace: airflow
```

**AZ pinning lesson:** EBS volumes are AZ-specific. When PostgreSQL PVC is created, the EBS volume gets assigned to a specific AZ. If the pod is scheduled in a different AZ, it can't mount the volume. Solution: use `Immediate` binding (volume created before pod scheduling) and ensure StorageClass doesn't use `WaitForFirstConsumer`.

### Accessing Airflow

```bash
# Port-forward UI
kubectl port-forward svc/airflow-api-server -n airflow 8080:8080
# Open http://localhost:8080
# Credentials: admin / admin123

# Trigger DAG manually (CLI)
kubectl exec -n airflow \
  $(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}') \
  -c scheduler \
  -- airflow dags trigger feature_materialization

# List all DAGs
kubectl exec -n airflow \
  $(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}') \
  -c scheduler \
  -- airflow dags list

# Unpause a DAG
kubectl exec -n airflow \
  $(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}') \
  -c scheduler \
  -- airflow dags unpause feature_materialization

```
---
 
## ✅ Phase 13 — GitOps with ArgoCD
 
**What:** Replaced all manual `helm upgrade` and `kubectl apply` commands with GitOps — ArgoCD watches the GitHub repo and automatically syncs the cluster state on every `git push`.
 
**Why:** Before Phase 13, deploying a change required manually running scripts. With GitOps, Git becomes the single source of truth. Every change is auditable, reproducible, and rollback is a `git revert`. This is the production standard at companies like Airbnb, Spotify, and most cloud-native organizations.
 
**Architecture — App of Apps pattern:**
```
kubectl apply -f argocd/app-of-apps.yaml  ← one-time bootstrap
        ↓
ArgoCD watches argocd/apps/ in GitHub
        ↓
Creates 6 child Applications automatically:
  churn-prediction-api  → helm/churn-mlops/
  kafka                 → k8s/kafka/
  gatekeeper-policies   → k8s/gatekeeper/
  monitoring            → Prometheus+Grafana Helm chart
  redis                 → k8s/redis/
  stream-processor      → k8s/stream-processor-deployment.yaml
```
 
**Cluster Autoscaler:** Installed alongside ArgoCD to handle the pod capacity increase. EKS t3.medium nodes have a hard 17-pod limit (ENI-based IP allocation). With 53+ pods across the full stack, Cluster Autoscaler automatically adds a 4th node when pending pods are detected.
 
**Key design decisions:**
 
`prune: false` on Kafka and Redis — auto-pruning a stateful workload deletes data. Removing a KafkaTopic CR would destroy the topic and all messages. Stateful components must never be auto-pruned.
 
`ignoreDifferences` on Rollout `/spec/replicas` — HPA manages replica count at runtime. Without this, ArgoCD fights HPA every 3 minutes, resetting replicas back to the values.yaml value.
 
`ignoreDifferences` on Gatekeeper `/status` — Gatekeeper updates violation counts and audit timestamps continuously. Without ignoring status, ArgoCD shows perpetual `OutOfSync` noise that masks real drift.
 
`admissionWebhooks: false` in Prometheus — ArgoCD doesn't execute Helm pre-install hooks the same way `helm install` does. The kube-prometheus-stack admission webhook TLS secret is generated by a hook job. Disabling admission webhooks avoids the missing secret error when ArgoCD manages the chart.
 
**New daily workflow:**
```bash
# Before Phase 13
helm upgrade --install churn-mlops helm/churn-mlops/
kubectl apply -f k8s/stream-processor-deployment.yaml
 
# After Phase 13
git add .
git commit -m "your change"
git push origin main
# ArgoCD syncs automatically within ~3 minutes
```
 
**Infrastructure boundary — what ArgoCD manages vs setup script:**
 
| Component | Managed by |
|-----------|-----------|
| churn-prediction-api | ArgoCD (Helm) |
| Kafka CRs | ArgoCD (raw manifest) |
| Gatekeeper policies | ArgoCD (raw manifest) |
| Prometheus + Grafana | ArgoCD (Helm) |
| Redis | ArgoCD (raw manifest) |
| Stream processor | ArgoCD (raw manifest) |
| Strimzi operator | setup-networking.sh (infrastructure) |
| EBS CSI Driver | setup-networking.sh (infrastructure) |
| Airflow | setup-networking.sh (stateful, complex) |
| Cluster Autoscaler | setup-networking.sh (node-level) |
 
**Accessing ArgoCD:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
# Open https://localhost:8081 — admin / <password>
```
 
**Verified:** All 7 applications `Synced` and `Healthy`.
 
---
 
## ✅ Phase 14 — Progressive Delivery with Argo Rollouts + Istio
 
**What:** Replaced Kubernetes `Deployment` with Argo Rollouts `Rollout` for canary deployments, integrated with Istio service mesh for exact percentage-based traffic splitting and Prometheus-driven automatic rollback.
 
**Why:** Standard Kubernetes RollingUpdate deploys new model versions to 100% of traffic immediately. A bad model version silently serves wrong predictions until someone notices. Argo Rollouts + Istio enables safe progressive delivery — new model versions get 20% of traffic first, Prometheus validates accuracy metrics, then gradually promotes to 100% only if metrics pass.
 
**Architecture:**
```
New model image → git push → ArgoCD syncs Rollout spec
        ↓
Argo Rollouts creates revision 2 (canary)
        ↓
Istio VirtualService updated: stable=80%, canary=20%
        ↓
AnalysisRun queries Prometheus every 30s:
  success_rate = non-5xx / total > 95%?
        ↓ (pass × 3)
setWeight: 40% → 60% → 80% → 100%
        ↓ (or fail → automatic rollback to stable)
Revision 1 scaled down. Revision 2 = new stable.
```
 
**Argo Rollouts vs plain Kubernetes:**
 
| | RollingUpdate | Argo Rollouts + Istio |
|---|---|---|
| Traffic control | Pod count ratio (~50/50) | Exact % via Istio Envoy |
| Rollback trigger | Manual or liveness probe | Prometheus metrics |
| Canary duration | Minutes | Configurable steps |
| Visibility | None | Full step-by-step UI |
 
**Why Istio for exact traffic splitting:** Without Istio, `setWeight: 20` with 2 pods = 50/50 (1 pod each). Istio's Envoy proxy routes at the request level, not connection level — 1 canary pod + 1 stable pod can achieve exactly 20/80 because every 5th HTTP request goes to canary regardless of pod count.
 
**Canary steps:**
```yaml
steps:
  - setWeight: 20    # Istio VirtualService: stable=80, canary=20
  - pause:
      duration: 30s
  - setWeight: 40
  - pause:
      duration: 30s
  - setWeight: 60
  - pause:
      duration: 30s
  - setWeight: 80
  - pause:
      duration: 30s
  # Step 9: auto-promote to 100%
```
 
**AnalysisTemplate — Prometheus query:**
```yaml
query: |
  sum(rate(http_requests_total{namespace="churn-mlops",status!~"5.."}[2m])) /
  sum(rate(http_requests_total{namespace="churn-mlops"}[2m]))
successCondition: result[0] >= 0.95
failureLimit: 1
```
 
If success rate drops below 95% — rollback is automatic. No human intervention needed.
 
**HPA + Argo Rollouts integration:** HPA `scaleTargetRef` must point to `argoproj.io/v1alpha1 Rollout` (not `apps/v1 Deployment`). Argo Rollouts intercepts HPA scale requests and applies them to the correct ReplicaSet.
 
**Key gotcha — `ignoreDifferences` for Argo Rollouts + Istio:** Argo Rollouts dynamically updates VirtualService weights and DestinationRule subset labels during a canary. These runtime changes always differ from Git. Adding `ignoreDifferences` for `/spec/http` and `/spec/subsets` prevents ArgoCD from showing perpetual `OutOfSync`.
 
**Key gotcha — named route in VirtualService:** Argo Rollouts requires the VirtualService HTTP route to have a `name: primary` field so it knows which route to update. Without the named route, Argo Rollouts cannot find the correct route to patch weights into.
 
**Useful CLI commands:**
```bash
# Watch canary progress live
kubectl argo rollouts get rollout churn-prediction-api -n churn-mlops --watch
 
# Manually promote to next step
kubectl argo rollouts promote churn-prediction-api -n churn-mlops
 
# Emergency rollback
kubectl argo rollouts abort churn-prediction-api -n churn-mlops
 
# Trigger new rollout
kubectl argo rollouts restart churn-prediction-api -n churn-mlops
```
 
**Verified:** Revision 3 canary completed — `SetWeight: 60, ActualWeight: 60` with Istio VirtualService showing exact weight updates. AnalysisRun passed 3 consecutive Prometheus checks.
 
---
 
## ✅ Phase 15 — Data Quality with Great Expectations
 
**What:** Added data quality validation as the first gate in the retraining pipeline. Great Expectations validates the full training dataset before preprocessing begins — bad data never reaches the model.
 
**Why:** Drift detection (Phase 8) detects statistical distribution changes in production data. But it doesn't catch upstream data pipeline failures — truncated files, missing columns, invalid values, or schema changes. Great Expectations catches these at ingestion time via fail-fast validation.
 
**The core difference from Pydantic:**
 
| | Pydantic | Great Expectations |
|---|---|---|
| Scope | Single record | Entire dataset |
| When | Real-time API request | Batch pipeline |
| Checks | Types, required fields | Statistics, distributions, completeness |
| Output | HTTP 422 | HTML report + JSON to S3 |
 
**34 expectations across 4 categories:**
 
```python
# 1. Schema — all 20 columns must exist
expect_column_to_exist("tenure")  # × 20 columns
 
# 2. Nullability — critical columns must be complete
expect_column_values_to_not_be_null("MonthlyCharges")  # × 4 columns
 
# 3. Range — numerical bounds
expect_column_values_to_be_between("tenure", min_value=0, max_value=100)
expect_column_values_to_be_between("MonthlyCharges", min_value=0, max_value=200)
expect_column_values_to_be_between("TotalCharges", min_value=0, max_value=10000)
 
# 4. Categorical — encoded values must be valid
expect_column_values_to_be_in_set("Contract", [0, 1, 2])
expect_column_values_to_be_in_set("Churn", [0, 1])
 
# 5. Dataset-level
expect_table_row_count_to_be_between(min_value=1000)  # catch truncated ETL
expect_table_column_count_to_equal(value=20)
```
 
**Validation report saved to S3:**
```
s3://churn-mlops-artifacts/great_expectations/validation_results/result_<timestamp>.json
```
 
JSON report contains: timestamp, success flag, statistics (passed/failed counts), and detailed failure information with column names and kwargs.
 
**Airflow integration — fail fast pattern:**
```python
# In churn_retraining.py — first task in chain
validate_data >> check_drift >> preprocess >> train >> explain >> register >> restart_api
```
 
If `validate_data` raises `ValueError`, Airflow marks the task as failed and the entire DAG stops. Drift check and training never run on bad data.
 
**Running validation:**
```bash
python src/validate_data.py --data-path data/processed/train.csv
# OR from S3:
python src/validate_data.py --data-path s3://churn-mlops-artifacts/data/raw/churn.csv
```
 
**Verified:** 34/34 expectations passed on 5634-row training dataset. Report saved to S3.
 
---
 
## ✅ Phase 16 — Model Explainability with SHAP and LIME
 
**What:** Added model explainability to answer "why did the model predict this customer will churn?" using SHAP (game-theory based) and LIME (local approximation). Explanation artifacts logged to MLflow after every training run.
 
**Why explainability matters in MLOps:** A model with 79.7% accuracy tells you what customers will churn. It doesn't tell the retention team why — which is what drives action. Without explanations, a churn score is a black box. With SHAP/LIME, the retention team knows: "This customer is high risk because of their Month-to-month contract (+0.23) and 2-month tenure (+0.19) — offer them an annual contract discount."
 
**SHAP vs LIME:**
 
| | SHAP | LIME |
|---|---|---|
| Mathematical basis | Game theory (Shapley values) | Local linear approximation |
| Consistency | ✅ Always sums to prediction | ❌ Approximation |
| Global explanations | ✅ Yes | ❌ Local only |
| Speed | Fast (TreeSHAP for RF) | Slower (1000 perturbations) |
| Industry adoption | Very high | Moderate |
 
**SHAP internals — TreeSHAP:** For tree-based models (Random Forest, XGBoost), SHAP uses TreeSHAP which computes exact Shapley values in O(TLD²) time instead of exponential time by exploiting tree structure. This makes it practical for production — explaining 500 predictions takes ~3 seconds.
 
**Mathematical guarantee:**
```
Prediction = base_value + sum(SHAP values for all 19 features)
0.73       = 0.265      + 0.057 + 0.041 + 0.034 + ... (all features)
```
 
SHAP values always sum exactly to `prediction - base_value`. This additivity property is what makes SHAP trustworthy for business decisions.
 
**Key findings from your model:**
 
| Feature | Global SHAP Importance |
|---------|----------------------|
| Contract | 0.0793 (highest) |
| tenure | 0.0553 |
| OnlineSecurity | 0.0435 |
| TechSupport | 0.0365 |
| MonthlyCharges | 0.0352 |
 
Both SHAP and LIME agree: `Contract = Month-to-month` is the #1 churn driver.
 
**Artifacts generated:**
- `reports/explainability/shap_summary.png` — beeswarm plot (each dot = one prediction)
- `reports/explainability/shap_bar.png` — mean |SHAP| per feature (for stakeholders)
- MLflow run with top-10 feature importances as metrics + both plots as artifacts
**SHAP values array shape in v0.46.0:** `(n_samples, n_features, n_classes)` — index `[:, :, 1]` for class 1 (churn). Earlier versions returned a list `[class_0_array, class_1_array]`.
 
**Running explanations:**
```bash
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/explain.py
```
 
**Airflow DAG updated:**
```
validate_data → check_drift → preprocess → train → explain → register → restart_api
```
 
**Verified:** SHAP base value 0.2651, top 3 reasons for test customer: Contract (+0.0573), TechSupport (+0.0410), OnlineSecurity (+0.0337). MLflow run logged with plots.
 
---
 
## ✅ Phase 17 — Load Testing with Locust
 
**What:** Systematic load testing of the prediction API across three scenarios (baseline, normal, stress) to measure throughput, latency, and HPA scaling behavior under real traffic.
 
**Why load test:** Unit tests prove the API works for 1 request. Load tests prove it works for 200 concurrent users. Without load testing you discover scaling issues in production, not before it. Load testing also validates HPA configuration — does Kubernetes scale fast enough to prevent latency degradation?
 
**Test scenarios:**
 
| Scenario | Users | Spawn Rate | Duration | Purpose |
|----------|-------|-----------|----------|---------|
| Baseline | 10 | 2/s | 30s | Establish baseline latency |
| Normal load | 50 | 5/s | 60s | Verify SLA at expected traffic |
| Stress | 200 | 10/s | 120s | Find breaking point, observe HPA |
 
**Results:**
 
| Metric | Baseline (10) | Normal (50) | Stress (200) |
|--------|--------------|-------------|--------------|
| RPS | 10 | 19.4 | 35.5 |
| Median latency | 320ms | 1100ms | 3600ms |
| p95 latency | 400ms | 2500ms | 5600ms |
| p99 latency | 670ms | 3700ms | 8600ms |
| Failure rate | 0% | 0% | 0.36% |
| HPA replicas | 1→2 | 1→2 | 2→3 |
 
**HPA scaling observed during stress test:**
```
cpu: 1%    → 2 pods  (idle)
cpu: 100%  → 2 pods  (load hit, HPA detecting breach)
cpu: 148%  → 3 pods  (scaled to max)
cpu: 78%   → 3 pods  (3rd pod ready, load distributed)
cpu: 2%    → 3 pods  (test ended)
```
 
**Key findings:**
 
1. **API is stable under load** — 0% failures up to 50 users, only 0.36% at 200 users
2. **p95 SLA (500ms) breached at 50+ users** — single-pod bottleneck during HPA lag
3. **HPA lag ~60 seconds** — reactive autoscaling, not proactive. CPU saturates before new pods are ready
4. **503 errors during pod restarts** — Istio Envoy terminating connections during rolling updates
5. **Min latency = 306ms** — network round-trip from external Mac → ALB → EKS. In-cluster latency would be ~5-10ms
**Root cause of latency degradation:** `minReplicas: 1` meant 1 pod handles all traffic until HPA reacts (~60s). During that window, 50 users compete for 1 pod's CPU, causing request queuing and latency spikes.
 
**Optimizations applied from load test findings:**
 
```yaml
# Before
autoscaling:
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70
 
# After
autoscaling:
  minReplicas: 2      # always 2 pods ready — no cold-start lag
  maxReplicas: 5      # more scaling headroom for burst traffic
  targetCPUUtilizationPercentage: 50   # scale earlier, before saturation
```
 
Also added graceful shutdown to prevent 503 errors during pod restarts:
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]  # drain ALB connections before SIGTERM
terminationGracePeriodSeconds: 60             # complete in-flight requests
```
 
**Why `preStop` sleep:** When Kubernetes sends SIGTERM to a pod, the ALB still routes traffic to it for a few seconds while its target group registration is deregistered. The 5-second sleep ensures no new connections arrive after the pod starts shutting down.
 
**Locust user types:**
- `PredictionUser` — 1-3s think time, mixed health + prediction calls, `task(10)` weight on predict
- `HeavyPredictionUser` — 0.1-0.5s think time, rapid-fire predictions (batch scoring simulation)
**Running load tests:**
```bash
# Interactive web UI
locust -f load_tests/locustfile.py \
  --host http://<ALB_URL>
# Open http://localhost:8089
 
# Headless (CI/CD)
locust -f load_tests/locustfile.py \
  --host http://<ALB_URL> \
  --headless --users 50 --spawn-rate 5 --run-time 60s \
  --csv load_tests/results/normal_load
```
 
**Verified:** HPA scaled 2→3 replicas at CPU 148%. Post-optimization: minReplicas=2, maxReplicas=5, CPU threshold=50%.
 ---
 
## 📋 Phase 18 — Multi-Environment (dev/staging/prod)
 
**What:** Structured separation of dev, staging, and production environments — each with its own cluster, configuration, and promotion gates. Implemented as part of the Terraform infrastructure migration (Phase 20).
 
**Why multi-environment matters:**
 
Without environment separation, every code change goes directly to the same cluster your production model runs on. A bad model version, a misconfigured Helm value, or a broken Kafka topic affects real users immediately. Multi-environment creates isolation layers:
 
```
Developer pushes code
      ↓
dev   — runs automatically on every push to main
      ↓ (automated tests pass)
staging — mirrors prod, runs integration + load tests
      ↓ (manual approval or automated SLA check)
prod  — real traffic, real customers, real model
```
 
---
 
### Environment Separation Strategy
 
**Approach: Cluster-per-environment**
 
```
AWS Account
├── EKS cluster: churn-mlops-dev     (2x t3.small,  ~$0.10/hr)
├── EKS cluster: churn-mlops-staging (3x t3.medium, ~$0.20/hr)
└── EKS cluster: churn-mlops-prod    (3x t3.large,  ~$0.40/hr)
```
 
Each cluster has its own:
- VPC and subnets
- IAM roles and policies
- RDS PostgreSQL (MLflow backend)
- ElastiCache Redis
- ArgoCD instance
- Prometheus + Grafana stack
**Why cluster-per-environment over namespace-per-environment:**
 
Namespace separation gives logical isolation but not blast radius isolation. A pod in `churn-mlops-dev` namespace consuming all node CPU directly starves `churn-mlops-prod` pods on the same node. Separate clusters guarantee complete resource isolation — dev incidents cannot affect prod.
 
---
 
### Repo Structure
 
```
MLOps-Projects/
├── terraform/
│   ├── modules/
│   │   ├── vpc/          ← shared module, called by each env
│   │   ├── eks/          ← shared module, called by each env
│   │   ├── rds/          ← shared module, called by each env
│   │   ├── elasticache/  ← shared module, called by each env
│   │   ├── ec2/          ← MLflow server
│   │   ├── iam/          ← IRSA roles, node policies
│   │   └── s3/           ← artifacts + DVC buckets
│   └── environments/
│       ├── dev/
│       │   ├── main.tf           ← calls all modules with dev vars
│       │   ├── variables.tf
│       │   └── terraform.tfvars  ← dev-specific values
│       ├── staging/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── terraform.tfvars
│       └── prod/
│           ├── main.tf
│           ├── variables.tf
│           └── terraform.tfvars
│
├── helm/churn-mlops/
│   ├── Chart.yaml
│   ├── values.yaml           ← base values (shared)
│   ├── values-dev.yaml       ← dev overrides
│   ├── values-staging.yaml   ← staging overrides
│   └── values-prod.yaml      ← prod overrides
│
└── argocd/
    ├── dev/
    │   ├── app-of-apps.yaml  ← points to dev cluster
    │   └── apps/
    │       └── churn-api.yaml  ← uses values-dev.yaml
    ├── staging/
    │   ├── app-of-apps.yaml
    │   └── apps/
    │       └── churn-api.yaml  ← uses values-staging.yaml
    └── prod/
        ├── app-of-apps.yaml
        └── apps/
            └── churn-api.yaml  ← uses values-prod.yaml
```
 
---
 
### Environment-Specific Helm Values
 
**`values.yaml` (base — shared across all environments):**
```yaml
image:
  repository: 011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api
  pullPolicy: Always
 
probes:
  liveness:
    path: /health
    initialDelaySeconds: 40
  readiness:
    path: /health
    initialDelaySeconds: 40
```
 
**`values-dev.yaml` (overrides):**
```yaml
image:
  tag: dev-latest          # built from every push to main
 
replicaCount: 1
autoscaling:
  enabled: false           # no HPA — save cost
 
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "200m"
 
rollout:
  enabled: false           # direct deploy — no canary in dev
deployment:
  enabled: true
 
mlflow:
  trackingUri: "http://mlflow-dev.internal:5000"
```
 
**`values-staging.yaml` (overrides):**
```yaml
image:
  tag: staging-latest      # promoted from dev after tests pass
 
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 3
  targetCPUUtilizationPercentage: 60
 
rollout:
  enabled: true
  steps:
    - setWeight: 50        # simplified 50/50 canary
    - pause:
        duration: 60s
 
mlflow:
  trackingUri: "http://mlflow-staging.internal:5000"
```
 
**`values-prod.yaml` (overrides):**
```yaml
image:
  tag: v1.2.3              # pinned semantic version — never 'latest' in prod
 
replicaCount: 3
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
 
rollout:
  enabled: true
  steps:
    - setWeight: 10        # cautious — 10% first in prod
    - pause:
        duration: 300s     # 5 minute soak time per step
    - setWeight: 30
    - pause:
        duration: 300s
    - setWeight: 60
    - pause:
        duration: 300s
 
mlflow:
  trackingUri: "http://mlflow-prod.internal:5000"
```
 
---
 
### Terraform Module Pattern
 
Same module, different variables — no code duplication:
 
```hcl
# terraform/environments/dev/main.tf
module "eks" {
  source        = "../../modules/eks"
  cluster_name  = "churn-mlops-dev"
  environment   = "dev"
  instance_type = "t3.small"
  min_nodes     = 2
  max_nodes     = 4
  subnet_ids    = module.vpc.private_subnet_ids
}
 
# terraform/environments/prod/main.tf
module "eks" {
  source        = "../../modules/eks"
  cluster_name  = "churn-mlops-prod"
  environment   = "prod"
  instance_type = "t3.large"
  min_nodes     = 3
  max_nodes     = 10
  subnet_ids    = module.vpc.private_subnet_ids
}
```
 
The `eks` module is written once — `dev` and `prod` call it with different variables. Any improvement to the module (new security feature, updated AMI) automatically applies to all environments on next `terraform apply`.
 
---
 
### Promotion Flow
 
```
Feature branch → PR → merge to main
        ↓
GitHub Actions:
  - Run pytest (18 tests)
  - Trivy security scan
  - Build image → tag as dev-latest → push ECR
        ↓
ArgoCD dev: detects dev-latest → deploys to dev cluster
        ↓
Automated validation:
  - Locust load test (10 users, 30s)
  - Great Expectations data quality check
  - SHAP explanation sanity check
        ↓ (all pass)
GitHub Actions: retag dev-latest → staging-latest → push ECR
        ↓
ArgoCD staging: deploys → canary 50/50 → AnalysisRun checks metrics
        ↓ (manual approval via GitHub PR or automated if SLA met)
GitHub Actions: retag staging-latest → v1.2.3 → push ECR
        ↓
ArgoCD prod: canary 10% → 30% → 60% → 100%
             AnalysisRun checks Prometheus metrics at each step
             Auto-rollback if success rate < 95%
```
 
---
 
### CI/CD Path Filters
 
```yaml
# .github/workflows/ci-cd.yml
on:
  push:
    paths:
      - 'app/**'
      - 'src/**'
      - 'Dockerfile'
      - 'requirements-api.txt'
 
# .github/workflows/terraform.yml
on:
  push:
    paths:
      - 'terraform/**'
 
# .github/workflows/data-quality.yml
on:
  push:
    paths:
      - 'great_expectations/**'
      - 'src/validate_data.py'
```
 
Each workflow only triggers when its relevant files change — no wasted CI minutes running Docker builds when only a DAG file changed.
---
 
### Environment Comparison
 
| Aspect | dev | staging | prod |
|--------|-----|---------|------|
| Instance type | t3.small | t3.medium | t3.large |
| Min nodes | 2 | 2 | 3 |
| Max nodes | 4 | 5 | 10 |
| Image tag | `dev-latest` | `staging-latest` | `v1.x.x` (pinned) |
| Deployment strategy | Direct (no canary) | Canary 50/50 | Canary 10→30→60→100% |
| HPA | Disabled | Enabled (CPU 60%) | Enabled (CPU 50%) |
| MLflow | Shared dev instance | Dedicated staging | Dedicated prod |
| Promotion | Automatic (on push) | Automatic (tests pass) | Manual approval |
| Cost/hr | ~$0.10 | ~$0.20 | ~$0.40 |
 
---
 
## ✅ Phase 19 — Hardening
 
**What:** Production security hardening across four dimensions — IAM least privilege, managed cache migration, network isolation, and encrypted transport. Closes the security gaps that would be flagged in a production security review.
 
**Why hardening matters:** A working system and a secure system are different things. Phase 19 addresses the gap between "it works" and "it's production-ready":
 
```
Before hardening:
- Every EKS node has AmazonS3FullAccess — compromised pod = full S3 access
- AutoScalingFullAccess on nodes — compromised pod = can destroy all ASGs in account
- Redis runs as a single pod — no persistence, no failover, restarts lose all cache
- HTTP only — customer PII transmitted unencrypted
- Pods in public subnets — internet-reachable if Security Group misconfigured
 
After hardening:
- Node role has zero S3 access — all S3 via IRSA (scoped to 2 buckets only)
- Cluster Autoscaler has 9 specific actions — nothing more
- ElastiCache: managed, private subnet, SG-restricted, multi-AZ capable
- HTTPS: documented architecture, implemented at production with real domain
- NAT Gateway: documented architecture, implemented via Terraform
```
 
---
 
### 19.1 — IAM Least Privilege
 
**What was wrong:** EKS worker node role had two overly broad AWS managed policies:
- `AmazonS3FullAccess` — read/write/delete access to ALL S3 buckets in the account
- `AutoScalingFullAccess` — create/modify/delete any Auto Scaling resource in the account
A compromised pod inheriting node-level credentials could exfiltrate all training data, delete production datasets, or destroy all Auto Scaling Groups in the account.
 
**What changed:**
 
| Policy | Action | Reason |
|--------|--------|--------|
| `AmazonS3FullAccess` | Removed | S3 access handled by IRSA — scoped to 2 buckets only |
| `AutoScalingFullAccess` | Removed | Replaced with minimal 9-action policy |
| `churn-mlops-cluster-autoscaler-policy` | Added | Exact actions Cluster Autoscaler needs — nothing more |
 
**Minimal Cluster Autoscaler policy (9 actions):**
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes"
    ],
    "Resource": "*"
  }]
}
```
 
**Final node role policies (5 — all required, none excessive):**
```
AmazonEKSWorkerNodePolicy               ← register with EKS control plane
AmazonEKS_CNI_Policy                    ← VPC CNI networking
AmazonEC2ContainerRegistryReadOnly      ← pull images from ECR
AmazonEBSCSIDriverPolicy                ← EBS volume provisioning
churn-mlops-cluster-autoscaler-policy   ← 9 autoscaling actions only
```
 
**All S3 access now flows exclusively through IRSA:**
```
Pod (churn-prediction-sa) → IRSA → churn-mlops-irsa-role
  → churn-mlops-s3-policy (GetObject, PutObject on 2 buckets only)
  → churn-mlops-secrets-policy (GetSecretValue on churn-mlops/* only)
```
 
**Commands:**
```bash
# Remove broad policies
aws iam detach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
 
aws iam detach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
 
# Attach minimal policy
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::011528270076:policy/churn-mlops-cluster-autoscaler-policy
 
# Verify
aws iam list-attached-role-policies --role-name $NODE_ROLE \
  --query 'AttachedPolicies[*].PolicyName' --output table
```
 
---
 
### 19.2 — AWS ElastiCache (Replace In-Cluster Redis)
 
**What was wrong:** Redis ran as a single `redis:7.2` pod in the `redis` namespace:
- No persistence — pod restart loses all cached predictions
- No replication — single point of failure
- No multi-AZ — AZ failure = complete Redis outage
- Bitnami chart — OCI registry migration broke ArgoCD integration
**What changed:** Migrated to AWS ElastiCache — fully managed Redis with AWS handling patching, monitoring, and availability.
 
**ElastiCache configuration:**
```
Cluster ID:    churn-mlops-redis
Engine:        Redis 7.1
Node type:     cache.t3.micro (~$0.017/hour)
Endpoint:      churn-mlops-redis.1lzaia.0001.use1.cache.amazonaws.com:6379
Subnet group:  churn-mlops-elasticache-subnet
               ├── subnet-095a2844b2809bf7d (us-east-1a, private)
               └── subnet-0cf890022b3095da4 (us-east-1b, private)
Security group: sg-027c7c425469a8306
               └── port 6379 from EKS VPC (192.168.0.0/16) only
```
 
**Network path:**
```
EKS Pod → VPC Peering → ElastiCache (private subnet)
```
ElastiCache lives in private subnets of your MLflow VPC. EKS pods reach it via VPC Peering. The Security Group allows port 6379 only from the EKS VPC CIDR — no public internet access.
 
**Files updated to use ElastiCache endpoint:**
- `k8s/stream-processor-deployment.yaml` — `REDIS_HOST` env var
- `feature_store/churn_feature_repo/feature_repo/feature_store.yaml` — Feast online store
- `scripts/materialize_features.py` — default REDIS_HOST
- `dags/feature_materialization.py` — Airflow DAG env var
- `streaming/stream_processor.py` — default fallback
**Verified:** Stream processor logs show:
```
Connecting to Redis at churn-mlops-redis.1lzaia.0001.use1.cache.amazonaws.com:6379
Redis connected!
```
 
**Teardown note:** ElastiCache is NOT deleted by `eksctl delete cluster`. Delete manually every evening:
```bash
aws elasticache delete-cache-cluster \
  --cache-cluster-id churn-mlops-redis \
  --region us-east-1
```
 
---
 
### 19.3 — HTTPS with ACM Certificate (Architecture Documented)
 
**Current state:** API traffic flows over HTTP (port 80) — customer PII transmitted unencrypted.
 
**Target architecture:**
```
Client → HTTPS (443) → ALB (TLS termination) → HTTP (80) → Pods
```
 
TLS terminates at the ALB — traffic from ALB to pods stays on the private VPC network and does not need additional encryption.
 
**Implementation requires:**
1. A domain name (e.g., `api.churn-mlops.com`) registered in Route53
2. ACM certificate — free, auto-renewed, natively integrated with ALB
3. ALB HTTPS listener on port 443
4. HTTP → HTTPS redirect on port 80
**ACM + ALB configuration (Terraform):**
```hcl
resource "aws_acm_certificate" "api" {
  domain_name       = "api.churn-mlops.com"
  validation_method = "DNS"
}
 
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.api.arn
 
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
 
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"
 
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```
 
**Note:** Implemented at current company (Mindstix) with real domain + ACM + Route53. Will be implemented in this project via Terraform in Phase 20 (infrastructure migration).
 
---
 
### 19.4 — NAT Gateway + Private Subnets (Architecture Documented)
 
**Current state:** EKS worker nodes run in public subnets — they have public IPs and are protected only by Security Groups.
 
**Target architecture:**
```
Internet
    ↓
ALB (public subnet — only entry point for inbound traffic)
    ↓
EKS Worker Nodes (PRIVATE subnet — no public IPs)
    ↓ (outbound only)
NAT Gateway (public subnet) → Internet
```
 
Pods in private subnets cannot receive inbound connections from the internet regardless of Security Group configuration — defense in depth.
 
**What NAT Gateway enables:** Pods in private subnets still need outbound internet access for:
- Pulling ECR images
- AWS API calls (S3, Secrets Manager, EKS API)
- MLflow tracking server calls
NAT Gateway provides outbound-only internet access — traffic can leave the private subnet but nothing can initiate inbound connections.
 
**Implementation (Terraform):**
```hcl
# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}
 
# NAT Gateway in public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]
}
 
# Private subnet route → NAT Gateway for outbound internet
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
 
# EKS nodegroup in private subnets
resource "aws_eks_node_group" "workers" {
  subnet_ids = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1b.id
  ]
}
```
 
**Cost:** ~$0.045/hour + $0.045/GB data processed (~$1/day for dev).
 
**Note:** Will be implemented via Terraform infrastructure migration (Blue/Green cluster cutover). Current eksctl cluster uses public subnets — new Terraform cluster will use private subnets with NAT Gateway from day one.
 
---
 
### Phase 19 Summary
 
| Item | Before | After | Status |
|------|--------|-------|--------|
| IAM — S3 | `AmazonS3FullAccess` on node role | Removed — IRSA only | ✅ Done |
| IAM — Autoscaling | `AutoScalingFullAccess` on node role | 9-action minimal policy | ✅ Done |
| Redis | In-cluster pod (no persistence) | AWS ElastiCache (managed) | ✅ Done |
| HTTPS | HTTP only | Architecture documented | | ✅ Done | |
| NAT Gateway | Pods in public subnet | Architecture documented | | ✅ Done | |
 
---
 
## Phase 20 — Terraform Infrastructure Migration (Current)
 
Full infrastructure migration from eksctl to Terraform. Blue-green parallel deployment — new Terraform cluster built alongside existing, verified end-to-end, then cut over.
 
### Terraform Architecture
 
```
terraform/
├── modules/          # Reusable, environment-agnostic
│   ├── vpc/          # VPC, subnets, IGW, NAT Gateway, route tables
│   ├── security-groups/  # Separate rule resources (no inline)
│   ├── s3/           # Versioned buckets, lifecycle policies
│   ├── rds/          # PostgreSQL 14, gp3, encrypted, performance insights
│   ├── elasticache/  # Redis 7.1, single-node nonprod
│   ├── ec2/          # AL2023 AMI, SSM enabled, EIP, TLS key pair
│   ├── iam/          # IRSA role, EKS node role (9-action), EC2 role
│   ├── eks/          # Managed node group, OIDC, 4 addons, SPOT
│   └── ecr/          # 3 repos, lifecycle policy (keep 10), scan-on-push
└── live/
    ├── nonprod/      # Each stack: backends/ + params/ + stacks/
    │   ├── 00-s3-backend/    → State bucket + SSE-KMS encryption
    │   ├── 10-network/       → VPC + security groups
    │   ├── 20-data/          → RDS + ElastiCache + S3 + ECR
    │   ├── 30-compute/       → MLflow EC2 + node role (no IRSA — moved to 50-iam)
    │   ├── 40-kubernetes/    → EKS cluster + node group + 4 addons + OIDC
    │   └── 50-iam/           → ALL IRSA roles (reads OIDC from 40-kubernetes)
    │                           Eliminates two-pass apply — single pass rebuild
    └── prod/         # Same 6 stacks, IMMUTABLE ECR tags, keep 20 images
    
```
 
**Stack apply order:**
```
00-s3-backend → 10-network → 20-data → 30-compute → 40-kubernetes → 50-iam
Single pass — no re-apply needed. 50-iam reads OIDC from 40-kubernetes remote state directly.
```
 
**Stack communication:** `terraform_remote_state` reads S3 state files.
 
### GitHub Actions Terraform CI/CD
 
```
PR opened   → terraform plan (changed stacks only) → comment plan on PR
PR merged   → manual approval (GitHub Environments: nonprod)
            → terraform apply (EXACT saved plan artifact)
Daily 6AM   → drift detection → alert if infrastructure drifted
```
 
Key features: OIDC auth (no long-lived keys), plan artifacts (1-day retention), change detection (module change triggers all stacks), concurrency group (no simultaneous applies), stack isolation (separate jobs with `needs:` dependencies).
 
### Application CI/CD + Auto-Deploy Flow
 
```
git push (code change)
  → GitHub Actions: test → Trivy scan → build → push to ECR
  → No git commits (Image Updater handles deployment)
 
ArgoCD Image Updater (polls every 2 min)
  → Detects new image SHA on latest tag in ECR
  → Updates ArgoCD Application spec directly
  → ArgoCD triggers Argo Rollouts canary (120s pause steps)
  → New pods deployed automatically — zero manual steps, zero git conflicts
```
 
### ECR Repositories (Terraform-managed)
 
| Repository | Purpose |
|-----------|---------|
| `churn-mlops-nonprod-prediction-api` | FastAPI prediction service |
| `churn-mlops-nonprod-stream-processor` | Kafka consumer |
| `churn-mlops-nonprod-materialize` | Feast feature materialization |
 
All repos: lifecycle policy (keep 10 tagged, expire untagged after 1 day), scan-on-push, AES256 encrypted, `force_delete=true` for nonprod.
 
---
 
## Infrastructure Resources
 
### Nonprod Terraform Cluster
 
| Resource | Value |
|----------|-------|
| VPC | `vpc-0da4e83c946d24180` (10.1.0.0/16) |
| NAT Gateway | `nat-0ba03377828c3a783` |
| MLflow EC2 | `i-063cfab3185b59739`, EIP `3.90.73.230`, private `10.1.1.233` |
| RDS | `churn-mlops-nonprod-mlflow-db.c3o84wgsio2m.us-east-1.rds.amazonaws.com` |
| ElastiCache | `churn-mlops-nonprod-redis.1lzaia.0001.use1.cache.amazonaws.com:6379` |
| EKS Cluster | `churn-mlops-nonprod` (4x t3.medium SPOT) |
| IRSA Role | `arn:aws:iam::011528270076:role/churn-mlops-nonprod-irsa-role` |
| State Bucket | `churn-mlops-nonprod-terraform-state` |
 
### Cost Estimate
 
| Resource | Cost/hour |
|----------|-----------|
| EKS Control Plane | $0.10 |
| 4x t3.medium SPOT | ~$0.06 |
| EC2 t3.small (MLflow) | $0.023 |
| RDS db.t3.micro | $0.016 |
| ElastiCache cache.t3.micro | $0.017 |
| NAT Gateway | ~$0.045 |
| **Total** | **~$0.27/hour** |
 
**Cost saving tip:** Stop EC2 + delete EKS each evening (~$0.18/hr saved). Keep RDS + ElastiCache running to preserve MLflow data.
 
---
 
## CI/CD Pipelines
 
### Application Pipeline (`ci-cd.yml`)
 
```yaml
Triggers: push to main (app/, src/, Dockerfile changes)
Jobs:
  1. Run Tests       → pytest 18 tests
  2. Security Scan   → Trivy vulnerability scanner
  3. Build and Push  → OIDC auth, ECR push
ECR: churn-mlops-nonprod-prediction-api
Auth: OIDC via TERRAFORM_ROLE_ARN (no long-lived AWS keys)
```
 
### Terraform Pipeline (`terraform.yml`)
 
```yaml
Triggers: push/PR (terraform/** changes)
Jobs:
  detect-changes → which stacks have file changes
  plan-*         → parallel plans per changed stack
  apply-*        → sequential applies in dependency order
  drift-detect   → daily cron, -detailed-exitcode
Environments:
  nonprod-plan → no protection (auto)
  nonprod      → required reviewer approval
Concurrency: terraform-nonprod (cancel-in-progress: false)
```
 
---
 
## How to Run
 
### Prerequisites
 
```bash
# Required tools
aws CLI v2, terraform ~> 1.9, kubectl, helm 3.x
istioctl, argo rollouts kubectl plugin
session-manager-plugin
 
# SSM plugin PATH
export PATH=$PATH:/usr/local/sessionmanagerplugin/bin
echo 'export PATH=$PATH:/usr/local/sessionmanagerplugin/bin' >> ~/.zshrc
 
# DB password (use single quotes — ! causes zsh issues in double quotes)
export TF_VAR_db_password='YourPassword123'
```
 
### New Cluster Bootstrap
 
```bash
# Step 1 — Apply Terraform stacks in order
export TF_VAR_db_password='YourPassword123'
cd terraform/live/nonprod/00-s3-backend/stacks && terraform init && terraform apply
cd ../../10-network/stacks  && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../20-data/stacks     && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../30-compute/stacks  && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../40-kubernetes/stacks && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
# cd ../../30-compute/stacks  && terraform apply -var-file=../params/main.tfvars  # re-apply for IRSA OIDC
cd ../../50-iam/stacks        && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
# No re-apply needed — 50-iam reads OIDC from 40-kubernetes remote state automatically
 
# Step 2 — Bootstrap application stack
aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1
./scripts/bootstrap-new-cluster.sh  # 15 steps, idempotent
 
# Step 3 — Migrate MLflow model (new RDS always empty)
aws s3 cp scripts/migrate-mlflow-model.py s3://churn-mlops-nonprod-artifacts/scripts/
INSTANCE_ID=$(terraform -chdir=terraform/live/nonprod/30-compute/stacks output -raw mlflow_instance_id)
aws ssm start-session --target $INSTANCE_ID --region us-east-1
# Inside EC2: pip3 install mlflow boto3 --user && python3 /tmp/migrate-mlflow-model.py
 
# Step 4 — Verify
kubectl argo rollouts restart churn-prediction-api -n churn-mlops
ALB=$(kubectl get svc churn-prediction-api -n churn-mlops -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/health
```
 
### Daily Morning Checklist
 
```bash
aws ec2 start-instances --instance-ids i-063cfab3185b59739 --region us-east-1
aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1
kubectl get nodes
kubectl get pods -n churn-mlops
kubectl get applications -n argocd
curl http://$ALB/health
```
 
### Evening Teardown
 
```bash
aws ec2 stop-instances --instance-ids i-063cfab3185b59739 --region us-east-1
cd terraform/live/nonprod/40-kubernetes/stacks
terraform destroy -var-file=../params/main.tfvars
# Keep RDS + ElastiCache running to preserve data
```
 
### Access Commands
 
```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8081:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
 
# Airflow UI
kubectl port-forward svc/airflow-api-server -n airflow 8080:8080  # admin/admin123
 
# MLflow UI via SSM tunnel
aws ssm start-session --target i-063cfab3185b59739 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5000"],"localPortNumber":["5001"]}' \
  --region us-east-1
# http://localhost:5001
```
 
---
 
## API Reference
 
```bash
GET  /health   → {"status":"healthy","model_loaded":true}
POST /predict  → {"churn":0,"probability":0.3792,"risk_level":"LOW"}
POST /explain  → per-prediction SHAP feature importance
GET  /metrics  → Prometheus metrics
```
 
**Predict request body:**
```json
{
  "gender": 1, "SeniorCitizen": 0, "Partner": 1, "Dependents": 0,
  "tenure": 12, "PhoneService": 1, "MultipleLines": 0, "InternetService": 1,
  "OnlineSecurity": 0, "OnlineBackup": 1, "DeviceProtection": 0, "TechSupport": 0,
  "StreamingTV": 0, "StreamingMovies": 0, "Contract": 0, "PaperlessBilling": 1,
  "PaymentMethod": 2, "MonthlyCharges": 65.5, "TotalCharges": 786.0
}
```
 
---
 
## Key Engineering Decisions
 
**Blue-green Terraform migration over `terraform import`:** Importing 40+ eksctl resources is error-prone. Blue-green validates new infrastructure end-to-end before cutover with zero risk.
 
**SPOT instances for EKS nodes:** ~70% cost reduction. SPOT reclaim risk mitigated by multi-AZ placement and Cluster Autoscaler replacing evicted nodes automatically.
 
**ArgoCD Image Updater over CI/CD git commits:** CI/CD committing `values.yaml` image tags back to `main` caused constant `non-fast-forward` conflicts. Image Updater polls ECR every 2 minutes, updates cluster directly — zero git commits, zero conflicts.
 
**S3 native locking over DynamoDB:** Terraform 1.10+ `use_lockfile = true` eliminates the DynamoDB table. Simpler — one less managed resource. Lock files visible and deletable via standard `aws s3 rm`.
 
**IRSA over node role S3 access:** Per-pod IAM permissions. A compromised pod cannot access other pods' AWS resources. Node role has only the 9 Cluster Autoscaler actions.
 
**Separate plan/apply jobs with approval gate:** Apply uses the EXACT plan artifact — prevents plan drift where infrastructure changes between plan and apply.
 
**Delete DestinationRule before Helm upgrade:** Argo Rollouts owns `.spec.subsets` via ServerSideApply (`v1alpha3`). Helm uses `v1beta1`. Deleting before upgrade clears field ownership conflict.
 
**`force_delete = true` on nonprod ECR:** Prevents `RepositoryNotEmptyException` during cluster rebuild when Terraform recreates repos. Set `false` in prod for safety.

**`50-iam` stack eliminates two-pass apply:** IRSA roles depend on EKS OIDC provider ARN which only exists after 40-kubernetes apply. Putting IRSA in 30-compute created a circular dependency requiring a two-pass apply on every cluster rebuild. 50-iam runs after both 30 and 40, reads OIDC from remote state directly — single clean pass, no manual variable updates.

**SSE-KMS over AES256 on state bucket:** Terraform state contains sensitive resource IDs and previously plaintext passwords. AES256 requires only `s3:GetObject` to read state. SSE-KMS requires both `s3:GetObject` AND `kms:Decrypt` — two separate IAM boundaries. Attacker needs both simultaneously.

**`manage_master_user_password = true` on RDS:** Removes plaintext RDS password from Terraform state entirely. AWS generates and stores password in Secrets Manager, rotates every 7 days automatically. MLflow EC2 fetches password at startup via `aws secretsmanager get-secret-value` — resilient to rotation without restarts.

**Scoped CI/CD IAM policy over AdministratorAccess:** `github-actions-terraform` role had `AdministratorAccess` — any credential leak = full account compromise. Replaced with `churn-mlops-terraform-ci-policy` scoped to only the 13 services Terraform manages. Validated green in GitHub Actions immediately after swap.
 
---
 
## Troubleshooting
 
See [`troubleshooting_phase20.md`](./troubleshooting_phase20.md) — 42 real issues with exact errors, root cause, and fix:
 
- Terraform: state locks, em dashes in HCL, `ignore_changes` pitfalls, duplicate variables
- EKS: EBS CSI IRSA, SPOT nodes without NAT, SSH IP lockout, SSM plugin setup
- Istio: native sidecar Init:1/2 on some nodes, memory exhaustion
- Helm: ServerSideApply conflict with Argo Rollouts, `--force` deprecated
- ArgoCD Image Updater: ECR auth formats, CRD schema changes in v1.1.1, `newest-build` strategy rename
- MLflow: empty RDS after rebuild, private vs public IP in Secrets Manager
- GitHub Actions: OIDC setup, git conflicts from CI/CD commits
- Shell: zsh `!` expansion in passwords, heredoc escaping, `cat >>` duplicates
### Quick Recovery
 
```bash
# Clear stale S3 state lock
aws s3 rm s3://churn-mlops-nonprod-terraform-state/nonprod/<stack>/terraform.tfstate.tflock
 
# Promote stuck canary
kubectl argo rollouts promote churn-prediction-api -n churn-mlops
 
# Refresh ECR credentials for Image Updater (expires every 12h)
ECR_TOKEN=$(aws ecr get-authorization-token --region us-east-1 \
  --query 'authorizationData[0].authorizationToken' --output text | base64 -d | cut -d: -f2)
kubectl create secret docker-registry ecr-creds \
  --docker-server=011528270076.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS --docker-password=${ECR_TOKEN} \
  -n argocd --dry-run=client -o yaml | kubectl apply -f -
 
# Fix Helm/Argo Rollouts DestinationRule conflict
kubectl delete destinationrule churn-prediction-api-destrule -n churn-mlops 2>/dev/null || true
kubectl delete virtualservice churn-prediction-api-vsvc -n churn-mlops 2>/dev/null || true
```
---

## 🏗️ Architecture — Phase 20 (Terraform-Managed Nonprod Cluster)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GITHUB (Source of Truth)                          │
│                                                                          │
│  Application Code    Infrastructure Code    GitOps Config                │
│  (app/, src/)        (terraform/)           (argocd/, helm/, k8s/)      │
└──────┬───────────────────────┬──────────────────────┬────────────────────┘
       │                       │                      │
       ▼                       ▼                      ▼
┌──────────────┐  ┌────────────────────────┐  ┌─────────────────────────┐
│  CI/CD       │  │  Terraform CI/CD        │  │  ArgoCD GitOps          │
│  Pipeline    │  │                         │  │                         │
│              │  │  PR → plan → comment    │  │  App of Apps pattern    │
│  pytest      │  │  Merge → approve        │  │  7 applications managed │
│  Trivy scan  │  │  → apply saved plan     │  │  self-healing           │
│  Docker build│  │  Daily drift detection  │  │  auto-sync on push      │
│  ECR push    │  │  OIDC auth (no keys)    │  │                         │
└──────┬───────┘  └────────────┬───────────┘  └──────────┬──────────────┘
       │                       │                          │
       ▼                       ▼                          │
┌──────────────┐  ┌────────────────────────┐             │
│  ECR         │  │  AWS Infrastructure     │             │
│              │  │  (Terraform-managed)    │             │
│  prediction  │  │                         │             │
│  -api        │  │  VPC 10.1.0.0/16        │             │
│  stream-     │  │  ├── NAT Gateway        │             │
│  processor   │  │  ├── MLflow EC2 (SSM)   │             │
│  materialize │  │  ├── RDS PostgreSQL 14  │             │
└──────┬───────┘  │  ├── ElastiCache Redis  │             │
       │          │  └── EKS (4x SPOT)      │             │
       │          └────────────┬────────────┘             │
       │                       │                          │
       └───────────────────────┼──────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    EKS Cluster (churn-mlops-nonprod)                     │
│                    4x t3.medium SPOT │ private subnets                   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Prediction API (Argo Rollouts canary)                           │    │
│  │                                                                  │    │
│  │  ECR image ──▶ ArgoCD Image Updater (polls every 2min)          │    │
│  │  new SHA detected ──▶ update ArgoCD spec ──▶ canary rollout     │    │
│  │                                                                  │    │
│  │  Istio VirtualService: 90% stable / 10% canary                  │    │
│  │  AnalysisTemplate: abort if error rate > 5%                     │    │
│  │  HPA: CPU 50% threshold, max 5 replicas                        │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │
│  │  Kafka       │  │  Airflow     │  │  Prometheus  │                  │
│  │  Strimzi     │  │  Kubernetes  │  │  + Grafana   │                  │
│  │  KRaft mode  │  │  Executor    │  │              │                  │
│  │  2 topics    │  │  git-sync    │  │  ServiceMon  │                  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘                  │
│         │                 │                                              │
│  ┌──────▼───────┐  ┌──────▼───────┐                                    │
│  │  Stream      │  │  Retraining  │                                    │
│  │  Processor   │  │  DAG (weekly)│                                    │
│  │              │  │              │                                    │
│  │  consume     │  │  validate    │                                    │
│  │  → predict   │  │  → train     │                                    │
│  │  → cache     │  │  → register  │                                    │
│  └──────────────┘  └──────────────┘                                    │
│                                                                          │
│  Security: OPA Gatekeeper │ Secrets CSI Driver │ IRSA │ NetworkPolicies │
└─────────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA LAYER                                       │
│                                                                          │
│  MLflow EC2 ──▶ RDS PostgreSQL 14 (experiment tracking, model registry) │
│  Prediction API ──▶ S3 (model artifacts, DVC versioning)                │
│  Stream Processor ──▶ ElastiCache Redis (prediction cache)              │
│  Airflow ──▶ S3 (Great Expectations reports, SHAP plots)               │
└─────────────────────────────────────────────────────────────────────────┘
```
 
---

---
 
## ✅ Phase 21 — Distributed Training with Ray + Karpenter
 
**What:** Full distributed ML pipeline on a Ray cluster running on EKS, with Karpenter
automatically provisioning right-sized nodes on demand for Ray workloads.
 
**Why distributed training matters:**
Single-node hyperparameter search runs trials sequentially — 20 trials × 30s = 10 minutes.
Distributed search runs trials in parallel — 20 trials ÷ 2 concurrent = 5 minutes.
At production scale (1000 trials, complex models), this difference is hours vs days.
 
### Architecture
 
```
git push → CI/CD builds image → ECR
                                    ↓
                           ArgoCD syncs RayCluster CR
                                    ↓
                    KubeRay Operator creates Ray pods
                                    ↓
              ┌─────────────────────────────────────┐
              │         Ray Cluster                  │
              │                                      │
              │  Head (t3.medium)                    │
              │  ├── GCS server (cluster metadata)   │
              │  ├── Dashboard (:8265)               │
              │  ├── Scheduler                       │
              │  └── Driver process                  │
              │                                      │
              │  Workers (Karpenter → r6i.large)     │
              │  ├── Ray tasks (preprocessing)       │
              │  ├── Ray Tune trials                 │
              │  └── Ray Train workers               │
              └─────────────────────────────────────┘
                                    ↓
                    Karpenter provisions r6i.large
                    (2 vCPU, 16GB RAM, SPOT)
                    in ~30 seconds on demand
                    terminated after 30s idle
```
 
### Phase 1 — Ray Data: Distributed Preprocessing
 
**What:** Splits the 7043-row Telco Churn dataset into shards and preprocesses
each shard in parallel across Ray workers. Demonstrates the distributed data
processing pattern used at production scale with millions of rows.
 
```python
@ray.remote
def preprocess_shard(shard_records: list) -> list:
    # Each worker processes its shard independently
    # LabelEncoding, TotalCharges fix, Churn mapping
    return processed_records
 
# 4 shards → 4 Ray workers → parallel execution
futures = [preprocess_shard.remote(shard) for shard in shards]
results = ray.get(futures)  # blocks until all workers complete
```
 
**Result:** 7043 rows preprocessed in 3.7s across 2 shards.
 
### Phase 2 — Ray Tune: Parallel Hyperparameter Search
 
**What:** Runs 10 hyperparameter trials in parallel using ASHA (Asynchronous
Successive Halving Algorithm) scheduler. Each trial trains a RandomForest with
different hyperparameters and logs results to MLflow.
 
**Search space:**
```python
search_space = {
    "n_estimators"     : tune.choice([50, 100, 150, 200, 300]),
    "max_depth"        : tune.choice([5, 10, 15, 20, 25]),
    "min_samples_split": tune.choice([2, 5, 10]),
    "max_features"     : tune.choice(["sqrt", "log2", 0.5]),
}
```
 
**Key design decision — data loaded inside each trial:**
Each trial reads the CSV from S3 directly (~0.5s) instead of passing DataFrames
through Ray config. This eliminates the serialization bottleneck that caused
CPU deadlock when DataFrames were passed as config dicts.
 
**Results (10 trials, 39 seconds total):**
 
| Trial | n_estimators | max_depth | max_features | ROC AUC |
|-------|-------------|-----------|--------------|---------|
| Best | 150 | 5 | 0.5 | **0.8427** |
| 00003 | 200 | 10 | log2 | 0.8363 |
| 00004 | 150 | 5 | 0.5 | 0.8427 |
| 00008 | 50 | 5 | log2 | 0.8415 |
| Worst | 50 | 20 | 0.5 | 0.8088 |
 
### Phase 3 — Ray Train: Distributed Model Training
 
**What:** Trains RandomForest models across 2 Ray workers using data parallelism.
Each worker trains on a different data shard (2817 samples each). Results are
aggregated via soft-voting ensemble.
 
```python
@ray.remote
def train_worker(worker_id, shard_records, best_params):
    model = RandomForestClassifier(**best_params, random_state=42 + worker_id)
    model.fit(X, y)
    return {"model": model, "roc_auc": roc_auc_score(y, model.predict_proba(X)[:,1])}
 
# 2 workers train in parallel
futures = [train_worker.remote(i, shard, hp) for i, shard in enumerate(shards)]
worker_results = ray.get(futures)
 
# Ensemble: average predict_proba across all worker models
y_prob = np.mean([r["model"].predict_proba(X_test)[:,1] for r in worker_results], axis=0)
```
 
**Results:**
 
| Metric | Single-node baseline | Distributed ensemble |
|--------|---------------------|---------------------|
| ROC AUC | 0.8358 | **0.8450** (+0.009) |
| Accuracy | 0.7970 | **0.8006** (+0.004) |
| Training time | ~30s | **6.9s** (2 workers) |
| Worker 0 train ROC AUC | — | 0.8882 |
| Worker 1 train ROC AUC | — | 0.8693 |
 
### Karpenter Integration
 
**Why Karpenter over Cluster Autoscaler for Ray:**
 
| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Provisioning time | 3-5 minutes | ~30 seconds |
| Node sizing | Fixed ASG instance type | Any EC2 instance type |
| Cost optimization | SPOT via ASG | SPOT with ON_DEMAND fallback |
| Ray worker memory | 3.8GB (t3.medium) | 16GB (r6i.large) |
| Node cleanup | Manual | Auto-terminate after 30s idle |
 
**NodePool configuration:**
```yaml
spec:
  template:
    spec:
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: [r6i.large, m5.large, t3.large]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]   # SPOT first, ON_DEMAND fallback
      taints:
        - key: workload-type
          value: ray
          effect: NoSchedule          # only Ray pods schedule here
  disruption:
    consolidateAfter: 30s             # terminate idle nodes immediately
```
 
**Coexistence with Cluster Autoscaler:**
```
Cluster Autoscaler → manages existing t3.medium node group (ASG-based)
Karpenter          → manages nodes it provisions (tagged karpenter.sh/nodeclaim)
No conflict        → they manage completely separate node sets
```
 
### Key Engineering Decisions
 
**Data loading inside Tune trials over passing DataFrames via config:**
Ray Tune serializes config to every trial worker via its object store. At 5634 rows × 19
features × 2 (train+test), each trial received ~2MB of data causing CPU thrashing during
deserialization. Loading from S3 inside each trial (~0.5s) was faster and eliminated
the deadlock.
 
**Karpenter over Cluster Autoscaler for Ray workloads:**
Cluster Autoscaler adds nodes in 3-5 minutes — too slow for interactive training jobs.
Karpenter provisions r6i.large nodes in ~30 seconds and terminates them 30 seconds
after Ray workers are idle, reducing cost to near-zero when not training.
 
**Separate SG for Karpenter nodes:**
Karpenter nodes only receive SGs matching `securityGroupSelectorTerms`. The EKS nodes SG
has a self-referencing rule that only allows traffic within the same SG. Adding the
EKS cluster SG to the nodeclass allows cross-node Ray GCS communication on port 6379.
 
**`@ray.remote` over Ray Train API for sklearn:**
Ray Train's sklearn integration was removed in Ray 2.x. The `@ray.remote` decorator
provides the same data parallelism with explicit control over shard distribution
and ensemble aggregation, and works with any sklearn-compatible model.
 
### Running Distributed Training
 
```bash
# Verify Ray cluster is healthy
HEAD_POD=$(kubectl get pod -n ray-system -l component=head \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ray-system $HEAD_POD -- ray status
 
# Run full pipeline
kubectl cp src/distributed_training.py ray-system/$HEAD_POD:/tmp/distributed_training.py
kubectl exec -n ray-system $HEAD_POD -- python /tmp/distributed_training.py
 
# View results in MLflow
# Tune experiment: distributed-hyperparameter-search
# Train experiment: distributed-model-training
aws ssm start-session \
  --target i-063cfab3185b59739 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5000"],"localPortNumber":["5001"]}' \
  --region us-east-1
# http://localhost:5001
 
# Watch Karpenter provision nodes
kubectl get nodes -w
kubectl get nodeclaims
```
 
### Infrastructure Added (Phase 21)
 
| Resource | Type | Purpose |
|----------|------|---------|
| `kuberay-operator` | Helm release (ray-system) | Manages RayCluster CRDs |
| `churn-ray-cluster` | RayCluster CR | Head + worker Ray cluster |
| `ray-worker-sa` | ServiceAccount (ray-system) | IRSA for S3 + MLflow access |
| `churn-mlops-nodeclass` | EC2NodeClass | Karpenter node configuration |
| `ray-workloads` | NodePool | Karpenter node provisioning rules |
| `churn-mlops-nonprod-karpenter-role` | IAM Role | Karpenter IRSA |
| `churn-mlops-nonprod-karpenter-policy` | IAM Policy | EC2 provisioning permissions |
| `churn-mlops-nonprod` | SQS Queue | Karpenter spot interruption handling |
| `karpenter` | Helm release (karpenter) | Karpenter controller |
| `src/distributed_training.py` | Python | 3-phase distributed training pipeline |
 
---
 
## Section 4 — Add to Key Engineering Decisions
 
Add after the last existing decision:
 
**Ray data loading inside Tune trials over config serialization:**
Passing 5634-row DataFrames as Ray Tune config dicts caused CPU deadlock — Ray
serialized 2MB of data to every trial worker simultaneously, saturating the 3-CPU
cluster. Loading directly from S3 inside each trial (~0.5s) eliminated the bottleneck.
 
**Karpenter + Cluster Autoscaler coexistence:**
Cluster Autoscaler manages the existing t3.medium ASG node group. Karpenter manages
nodes it provisions (tagged `karpenter.sh/nodeclaim`). They manage completely separate
node sets with no coordination needed. Karpenter provisions r6i.large in ~30s vs
Cluster Autoscaler's 3-5min — critical for interactive ML training jobs.
 
**SPOT + ON_DEMAND fallback in Karpenter NodePool:**
Ray workers use SPOT instances (70% cheaper) for training jobs. If SPOT capacity
is unavailable, Karpenter automatically falls back to ON_DEMAND. Ray's fault
tolerance handles the rare case where a SPOT instance is reclaimed mid-training.

--
 
## ✅ Phase 22 — KEDA Event-Driven Autoscaling
 
**What:** Replaced CPU-based HPA with KEDA (Kubernetes Event Driven Autoscaler)
for workload-aware autoscaling. Stream processor scales on Kafka consumer lag.
Prediction API scales on Redis queue depth.
 
**Why KEDA over HPA:**
 
The stream processor is I/O bound — it waits for Kafka messages, calls the
prediction API, and writes results to Redis. CPU stays at 5-10% even with
a 2000-message backlog. HPA would never scale up. KEDA scales on the actual
work queued — consumer lag — which directly reflects processing demand.
 
```
HPA (CPU-based):
  2000 messages in Kafka → stream processor CPU = 8% → HPA says: no scale needed
  Result: 2000 messages sit unprocessed for hours
 
KEDA (lag-based):
  2000 messages in Kafka → consumer lag = 2000 → KEDA: need 5 pods
  Result: backlog cleared in minutes with 5 parallel consumers
```
 
### Architecture
 
```
                    Kafka topic: customer-events
                    ┌──────────────────────────┐
                    │  Partition 0  lag=667     │
                    │  Partition 1  lag=700     │──→ KEDA polls lag every 15s
                    │  Partition 2  lag=633     │
                    └──────────────────────────┘
                                │
                    KEDA formula: ceil(totalLag / lagThreshold)
                                = ceil(2000 / 10)
                                = 200 → capped at maxReplicaCount=5
                                │
                    ┌───────────────────────┐
                    │   stream-processor    │
                    │   Pod 1 → Partition 0 │
                    │   Pod 2 → Partition 1 │
                    │   Pod 3 → Partition 2 │
                    │   Pod 4 → idle*       │
                    │   Pod 5 → idle*       │
                    └───────────────────────┘
                    * idle because partitions=3 < replicas=5
```
 
### ScaledObjects
 
**stream-processor-scaler — Kafka consumer lag:**
```yaml
spec:
  scaleTargetRef:
    name: churn-stream-processor
  minReplicaCount: 0      # scale to zero when no messages
  maxReplicaCount: 5
  cooldownPeriod: 300     # wait 5min before scaling down
  pollingInterval: 15     # check lag every 15 seconds
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: churn-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092
        consumerGroup: churn-stream-processor
        topic: customer-events
        lagThreshold: "10"    # target lag per pod
```
 
**prediction-api-scaler — Redis list depth:**
```yaml
spec:
  scaleTargetRef:
    apiVersion: argoproj.io/v1alpha1
    kind: Rollout                       # Argo Rollout, not Deployment
    name: churn-prediction-api
  minReplicaCount: 1      # never scale to zero — synchronous API
  maxReplicaCount: 5
  cooldownPeriod: 120
  pollingInterval: 10
  triggers:
    - type: redis
      metadata:
        address: churn-mlops-nonprod-redis.1lzaia.0001.use1.cache.amazonaws.com:6379
        listName: prediction_queue
        listLength: "5"
```
 
### Proven Scaling Behavior
 
| Messages Published | Total Lag | KEDA Formula | Replicas |
|-------------------|-----------|--------------|----------|
| 0 | 0 | 0/10 = 0 | 0 (scale to zero) |
| 50 | 23 | ceil(23/10) = 3 | 3 |
| 2000 | ~2000 | ceil(2000/10) = 200 → cap | 5 (max) |
| 0 (consumed) | 0 | cooldown 300s | 3 → 2 → 1 → 0 |
 
**Kafka rebalance observed:**
When KEDA scaled from 1 → 3 pods, Kafka automatically rebalanced partitions:
```
Before (1 pod):  Pod1 → Partition 0, 1, 2
After  (3 pods): Pod1 → Partition 0
                 Pod2 → Partition 1
                 Pod3 → Partition 2
```
Maximum parallelism = number of partitions (3). Scaling beyond 3 pods provides
no additional throughput benefit until partition count is increased.
 
### Key Engineering Decisions
 
**Scale to zero for stream processor, not prediction API:**
Stream processor is stateless and event-driven — it only needs to run when
messages exist. Scale to zero saves cost during off-hours. Prediction API serves
synchronous HTTP requests — scaling to zero causes ~30s cold start, unacceptable
for real-time inference. `minReplicaCount: 1` keeps 1 pod always warm.
 
**lagThreshold=10 over higher values:**
Lower threshold = more aggressive scaling = faster backlog clearance.
Higher threshold = fewer pods = lower cost but slower processing.
With 3 partitions, lagThreshold=10 means each pod handles ~10 messages
before KEDA adds another pod. Tuned for <30s processing latency target.
 
**cooldownPeriod=300s for stream processor:**
Kafka traffic is bursty — a 5-minute cooldown prevents rapid scale-up/scale-down
flapping. Without cooldown, KEDA would scale down immediately after a burst,
then scale up again for the next burst, causing unnecessary pod churn.
 
**General-purpose Karpenter NodePool:**
t3.medium nodes hit the 17-pod AWS ENI limit before CPU/memory was exhausted.
Added `general-purpose` NodePool (t3.medium/large/xlarge, no taint) to handle
overflow. Weight=10 makes it lower priority than `ray-workloads` (weight=100).
 
### Infrastructure Added (Phase 22)
 
| Resource | Type | Purpose |
|----------|------|---------|
| `keda` | Helm release (keda namespace) | KEDA operator + metrics server |
| `stream-processor-scaler` | ScaledObject | Kafka lag-based scaling |
| `prediction-api-scaler` | ScaledObject | Redis queue depth scaling |
| `keda-config` | ArgoCD Application | GitOps management of ScaledObjects |
| `general-purpose` | Karpenter NodePool | Overflow node provisioning |
| `keda-hpa-stream-processor-scaler` | HPA (KEDA-managed) | Auto-created by KEDA |
| `keda-hpa-prediction-api-scaler` | HPA (KEDA-managed) | Auto-created by KEDA |
 
### Running KEDA Load Test
 
```bash
# Publish 2000 messages in one shot (single producer connection — fast)
kubectl exec -n kafka churn-kafka-combined-0 -- bash -c '
for i in $(seq 1 2000); do
  echo "{\"customerID\":\"test-$i\",\"tenure\":12,\"MonthlyCharges\":65.5}"
done | bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic customer-events
echo "Published 2000 messages"'
 
# Watch KEDA scale in real time
watch -n 2 "
kubectl get hpa keda-hpa-stream-processor-scaler -n churn-mlops
kubectl get pods -n churn-mlops --no-headers | grep stream
kubectl exec -n kafka churn-kafka-combined-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group churn-stream-processor 2>/dev/null"
```
 
---
 
## Section 4 — Add to Key Engineering Decisions
 
**KEDA over HPA for event-driven workloads:**
CPU-based HPA is ineffective for I/O-bound stream processors — CPU stays low
even with thousands of unprocessed messages. KEDA scales on Kafka consumer lag
(actual work queued), which directly reflects processing demand. This is the
industry-standard pattern for Kafka consumer autoscaling in production.
 
**Scale-to-zero with minReplicaCount=0:**
Stream processor scales to 0 pods when no messages arrive, reducing EKS node
cost during off-hours. KEDA keeps 1 internal poller (not a pod) to detect new
messages and wake the deployment. First message after idle triggers cold start
(~15s) — acceptable for async stream processing but not synchronous APIs.
 
**Partition count = parallelism ceiling:**
Kafka assigns at most 1 partition per consumer in a group. With 3 partitions,
scaling beyond 3 pods provides no throughput benefit — excess pods sit idle.
Always set `partitions >= maxReplicaCount`. Partition count can only increase,
never decrease — plan it as a permanent capacity decision.

---
 
## Section 5 — Add to Key Engineering Decisions
 
**Prefix delegation over default VPC CNI for pod density:**
Default AWS VPC CNI assigns 1 IP per ENI slot — t3.medium has 18 slots (3 ENIs × 6 IPs),
leaving only 17 pods per node. During Phase 22, KEDA scaled stream processors causing
all 4 t3.medium nodes to hit the 17-pod ENI limit simultaneously, blocking new pod
scheduling despite CPU/memory being available. Enabled prefix delegation
(`ENABLE_PREFIX_DELEGATION=true`) which assigns a /28 prefix (16 IPs) per ENI slot,
increasing t3.medium capacity from 17 to 110 pods — a 6.5x improvement with zero
infrastructure change. Cilium was evaluated but rejected for this scale — it adds
significant operational complexity (CNI replacement, overlay networking, no AWS support)
with no benefit below 200 nodes.
 
---
 
## Section 6 — New full section to add after Phase 22
 
Add as a new section after `## ✅ Phase 22`:
 
---
 
## ✅ Infrastructure Hardening — IP Exhaustion & Pod Density
 
**Problem encountered:**
During Phase 22, KEDA scaled the stream processor deployment in response to Kafka
consumer lag. All 4 t3.medium nodes simultaneously hit the 17-pod ENI limit — new
pods stayed `Pending` despite 40-50% CPU and memory available on every node.
 
```
kubectl describe pod churn-stream-processor-xxx | grep Events
  Warning FailedScheduling: 0/4 nodes available: 3 Too many pods, 1 Insufficient cpu
```
 
**Root cause — AWS ENI hardware limit:**
```
t3.medium specs:
  Max ENIs per instance:  3
  Max IPs per ENI:        6
  Total IP slots:         3 × 6 = 18
  Reserved (node itself): 1
  Available for pods:     17  ← hard hardware limit
 
This limit is independent of subnet size.
/24 subnet has 251 IPs but t3.medium can only hold 17 simultaneously.
```
 
**Why 251 subnet IPs didn't help:**
```
Subnet (251 IPs) = parking lot with 251 spaces
t3.medium NIC    = car with only 18 cup holders
 
The parking lot has 233 empty spaces
But the car can only carry 18 cups — the car is the constraint
Empty spaces are irrelevant
```
 
**Solution — Prefix Delegation:**
 
Instead of 1 IP per ENI slot, AWS assigns a /28 prefix (16 IPs) per slot:
 
```
Without prefix delegation:
  t3.medium → 3 ENIs × 6 slots × 1 IP  = 18 IPs  → 17 pods
 
With prefix delegation:
  t3.medium → 3 ENIs × 6 slots × 16 IPs = 288 IPs → 110 pods
```
 
**Implementation:**
 
```hcl
# terraform/modules/eks/main.tf
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
 
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"   # 1 warm /28 prefix per ENI — reduces cold start
      MINIMUM_IP_TARGET        = "5"   # 5 IPs always pre-allocated on node
    }
  })
}
```
 
Applied immediately to running cluster:
```bash
kubectl set env daemonset aws-node -n kube-system \
  ENABLE_PREFIX_DELEGATION=true \
  WARM_PREFIX_TARGET=1 \
  MINIMUM_IP_TARGET=5
 
kubectl rollout restart daemonset aws-node -n kube-system
```
 
**Result:**
 
| Instance Type | Without Prefix Delegation | With Prefix Delegation |
|---|---|---|
| t3.medium | 17 pods | **110 pods** (6.5x) |
| t3.large | 35 pods | **290 pods** (8.3x) |
| r6i.large | 29 pods | **290 pods** (10x) |
 
**Note:** Existing nodes retain old limit until recycled. New Karpenter-provisioned
nodes automatically get the new limit since VPC CNI daemonset runs on startup.
 
### Industry Approach to IP Exhaustion
 
Different solutions apply at different scales:
 
| Scale | Solution | Why |
|---|---|---|
| < 200 nodes | **Prefix Delegation** | Simple, AWS-supported, 30 min setup |
| 200-500 nodes | Prefix Delegation + /19 subnets | Subnet becomes bottleneck at scale |
| 500+ nodes | **Cilium** | Overlay IPs — pods don't consume VPC IPs |
| Enterprise | Custom networking (RFC 6598) | Strict IP governance requirements |
 
**Jio/Hotstar approach at 10,000+ nodes:**
- Cilium with eBPF overlay — pods get overlay IPs (100.64.x.x), not VPC IPs
- Only nodes consume real VPC IPs → 10,000 nodes = 10,000 VPC IPs (not millions)
- /8 VPC (16M IPs) planned from day 0 — never retrofitted
- Multi-cluster architecture — each cluster has its own VPC, IP space never shared
**Why we chose prefix delegation over Cilium:**
```
Our scale:   6 nodes, < 200 pods
Cilium cost: 1-2 week migration, no AWS support, operational complexity
Benefit:     Zero at this scale
 
Prefix delegation:
  30 minute implementation
  Full AWS support
  6.5x pod density improvement
  Eliminates ENI limit as bottleneck
```
 
### Karpenter General-Purpose NodePool
 
Added as part of the same fix — handles overflow when existing nodes are full:
 
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general-purpose
spec:
  template:
    spec:
      nodeClassRef:
        name: churn-mlops-nodeclass   # same VPC/SG/AMI as ray-workloads
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: [t3.medium, t3.large, t3.xlarge]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
  weight: 10    # lower than ray-workloads (100) — last resort
```
 
**Two-layer overflow strategy:**
```
Layer 1 — Prefix delegation:  17 → 110 pods per existing node (no new node needed)
Layer 2 — Karpenter NodePool: provision new node if existing nodes still full
```
 
This eliminates pod scheduling failures from IP exhaustion in all but the most
extreme cases.

---
 
## 🌐 Infrastructure

### AWS Resources

| Resource | Type | Purpose | Phase |
|----------|------|---------|-------|
| `churn-mlops-artifacts` | S3 Bucket | Model artifacts + MLflow artifact store | 1 |
| `churn-mlops-dvc-store` | S3 Bucket | DVC remote storage for dataset versioning | 1 |
| `mlflow-db` | RDS PostgreSQL | MLflow backend store (eksctl cluster) | 2 |
| `mlflow-db.c3o84wgsio2m.us-east-1.rds.amazonaws.com` | RDS Endpoint | MLflow tracking server DB | 2 |
| `i-0d3ebb196f1ed53b8` | EC2 t3.small | MLflow tracking server (EIP 98.86.0.163) | 2 |
| `churn-prediction-api` | ECR Repo | Prediction API image (eksctl cluster) | 4 |
| `churn-mlops` | EKS Cluster | eksctl-managed cluster (3x t3.medium) | 6 |
| `a3bb3c740fb3747d88b007cade5f9bd4-405783512.us-east-1.elb.amazonaws.com` | ALB | Prediction API load balancer (eksctl) | 6 |
| `churn-mlops-irsa-role` | IAM Role | IRSA for prediction API pods (eksctl cluster) | 9.2 |
| `churn-mlops-s3-policy` | IAM Policy | S3 access — artifacts + dvc buckets only | 9.2 |
| `churn-mlops-secrets-policy` | IAM Policy | Secrets Manager read (churn-mlops/* only) | 9.3 |
| `churn-mlops/mlflow-tracking-uri` | Secrets Manager | Encrypted MLflow URI for pods | 9.3 |
| `secrets-store.csi.k8s.io` | CSI Driver | Mounts Secrets Manager secrets as volumes | 9.3 |
| `churn-mlops-vpc-peering` | VPC Peering | EKS VPC ↔ MLflow VPC connectivity | 9.4 |
| `churn-mlops-irsa-role` | IAM Role | Pod-scoped AWS credentials | 9.2 |
| `churn-mlops-s3-policy` | IAM Policy | S3 access (2 buckets only) | 9.2 |
| `churn-mlops-secrets-policy` | IAM Policy | Secrets Manager read | 9.3 |
| `churn-mlops/mlflow-tracking-uri` | Secrets Manager | Encrypted MLflow URI | 9.3 |
| `churn-stream-processor` | ECR | Kafka consumer image | 10 |
| `churn-materialize` | ECR | Feature materialization image | 12 |
| `ebs-sc` | K8s StorageClass | EBS gp2 for Airflow PostgreSQL | 12 |
| `aws-ebs-csi-driver` | EKS Addon | Dynamic EBS volume provisioning | 12 |
| `argocd` namespace | K8s Namespace | ArgoCD GitOps controller | 13 |
| `Cluster Autoscaler` | K8s Deployment | Automatic node scaling (ASG 3→6) | 13 |
| `argo-rollouts` namespace | K8s Namespace | Progressive delivery controller | 14 |
| `istio-system` namespace | K8s Namespace | Istio control plane | 14 |
| `churn-prediction-api-vsvc` | Istio VirtualService | Exact canary traffic splitting | 14 |
| `churn-prediction-api-destrule` | Istio DestinationRule | Stable/canary subset routing | 14 |
| `churn-api-success-rate` | AnalysisTemplate | Prometheus-based rollback gate | 14 |
| `churn-mlops-artifacts/great_expectations/` | S3 prefix | Validation report storage | 15 |
| `churn-mlops-artifacts/explainability/` | S3 prefix | SHAP/LIME plot storage | 16 |
| `churn-mlops-elasticache-subnet` | ElastiCache Subnet Group | Private subnets for ElastiCache | 19 |
| `churn-mlops-redis` | ElastiCache Cluster | Managed Redis 7.1 (replaces in-cluster) | 19 |
| `sg-027c7c425469a8306` | Security Group | ElastiCache — port 6379 from EKS VPC only | 19 |
| `churn-mlops-cluster-autoscaler-policy` | IAM Policy | 9-action minimal Cluster Autoscaler policy | 19 |
| `churn-mlops-nonprod-terraform-state` | S3 Bucket | Terraform remote state (native S3 locking) | 20 |
| `churn-mlops-nonprod-artifacts` | S3 Bucket | Model artifacts + migration scripts | 20 |
| `churn-mlops-nonprod-dvc-store` | S3 Bucket | DVC data versioning | 20 |
| `churn-mlops-nonprod-prediction-api` | ECR Repo | Prediction API image (Terraform-managed) | 20 |
| `churn-mlops-nonprod-stream-processor` | ECR Repo | Stream processor image (Terraform-managed) | 20 |
| `churn-mlops-nonprod-materialize` | ECR Repo | Materialize image (Terraform-managed) | 20 |
| `churn-mlops-nonprod-irsa-role` | IAM Role | IRSA for prediction API pods (nonprod) | 20 |
| `churn-mlops-nonprod-image-updater-role` | IAM Role | IRSA for ArgoCD Image Updater ECR access | 20 |
| `churn-mlops-nonprod-ebs-csi-role` | IAM Role | IRSA for EBS CSI driver addon | 20 |
| `churn-mlops-nonprod` | EKS Cluster | Terraform-managed cluster (4x t3.medium SPOT) | 20 |
| `churn-mlops-nonprod-mlflow-db` | RDS PostgreSQL 14 | MLflow backend store (gp3, encrypted) | 20 |
| `churn-mlops-nonprod-redis` | ElastiCache Redis 7.1 | Stream processor cache (private subnet) | 20 |
| `i-063cfab3185b59739` | EC2 t3.small | MLflow server (AL2023, SSM enabled, EIP 3.90.73.230) | 20 |
| `github-actions-terraform` | IAM Role | OIDC role for GitHub Actions Terraform CI/CD | 20 |
| `argocd-image-updater` | K8s Deployment | Auto-deploys new ECR images via ArgoCD | 20 |

### Cost Estimate (Nonprod Terraform Cluster)

| Resource | Cost/hour |
|----------|-----------|
| EKS Control Plane | $0.10 |
| 4x t3.medium SPOT nodes | ~$0.06 |
| EC2 t3.small (MLflow) | $0.023 |
| RDS db.t3.micro (PostgreSQL 14) | $0.016 |
| ALB | ~$0.008 |
| EBS volumes (Airflow) | ~$0.003 |
| ElastiCache cache.t3.micro (Redis 7.1) | $0.017 |
| NAT Gateway | ~$0.045 |
| **Total (cluster running)** | **~$0.27/hour** |
| **Evening saving (stop EC2 + delete EKS)** | **~$0.18/hour saved** |
| **Overnight cost (RDS + ElastiCache only)** | **~$0.033/hour** |

---

## 🗺️ Roadmap

### Completed ✅

| Phase | What | Key Tools | Status |
|-------|------|-----------|--------|
| 1 | Data Versioning | DVC, S3 | ✅ |
| 2 | Experiment Tracking | MLflow, RDS | ✅ |
| 3 | Model Registry | MLflow aliases | ✅ |
| 4 | Docker + FastAPI | Multi-stage, non-root | ✅ |
| 5 | CI/CD | GitHub Actions, ECR | ✅ |
| 6 | Kubernetes EKS | eksctl, Helm, HPA, ALB | ✅ |
| 7 | Monitoring | Prometheus, Grafana | ✅ |
| 8 | Drift Detection | Evidently AI | ✅ |
| 9.1 | Trivy Scanning | Trivy, .trivyignore | ✅ |
| 9.2 | IRSA | OIDC, STS federation | ✅ |
| 9.3 | Secrets Manager | CSI Driver | ✅ |
| 9.4 | Network Policies | VPC CNI eBPF | ✅ |
| 9.5 | OPA Gatekeeper | Rego policies | ✅ |
| 10 | Streaming | Strimzi KRaft, confluent-kafka | ✅ |
| 11 | Feature Store | Feast, Redis, S3 | ✅ |
| 12 | Auto Retraining | Airflow 3.2.0, KubernetesExecutor | ✅ |
| 13 | GitOps | ArgoCD, Cluster Autoscaler | ✅ |
| 14 | Progressive Delivery | Argo Rollouts, Istio | ✅ |
| 15 | Data Quality | Great Expectations | ✅ |
| 16 | Explainability | SHAP, LIME | ✅ |
| 17 | Load Testing | Locust | ✅ |
| 18 | Multi-environment | Terraform, Helm values per env, ArgoCD per env | 📋 Via Terraform |
| 19 | Hardening | ElastiCache, IAM least privilege, NAT Gateway, HTTPS | ✅ |
| 20 | Terraform Infrastructure + GitHub Actions CI/CD + Image Updater | ✅ |
| 20.1 | Terraform Best Practices — fmt-check CI, pre-commit, SSE-KMS, manage_master_user_password, 50-iam single-pass | ✅ |
| 21 | Distributed Training — Ray Data + Ray Tune + Ray Train + Karpenter | ✅ |
| 22 | KEDA Event-Driven Autoscaling — Kafka lag + Redis queue depth triggers | ✅ |
---

## 👨‍💻 Author

**Himanshu Singh (Heman)**
- Cloud DevOps Engineer @ Mindstix Software Labs
- MTech CS @ VNIT Nagpur (Federated Learning + Adversarial ML)
- GitHub: [@Himanshu9001](https://github.com/Himanshu9001)

---

## 📄 License

This project is for learning and portfolio purposes.

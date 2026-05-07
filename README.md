# 🚀 End-to-End MLOps Pipeline — Customer Churn Prediction
 
[![CI/CD Pipeline](https://github.com/Himanshu9001/MLOps-Projects/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Himanshu9001/MLOps-Projects/actions)
![Python](https://img.shields.io/badge/Python-3.12-blue)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.34-blue)
![MLflow](https://img.shields.io/badge/MLflow-2.22-orange)
![FastAPI](https://img.shields.io/badge/FastAPI-0.136-green)
![Airflow](https://img.shields.io/badge/Airflow-3.2.0-red)
![Kafka](https://img.shields.io/badge/Kafka-4.1.0-black)
![Feast](https://img.shields.io/badge/Feast-0.40.1-purple)
 
A production-grade, end-to-end MLOps pipeline built from scratch — covering data versioning, experiment tracking, model registry, containerization, CI/CD, Kubernetes deployment, monitoring, drift detection, MLSecOps, real-time streaming, feature store, and automated retraining.
 
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
| **IaC** | eksctl, Helm, bash scripts |
| **Testing** | pytest, httpx, pytest-asyncio |
| **GitOps** | ArgoCD v2.14.9, Cluster Autoscaler |
| **Progressive Delivery** | Argo Rollouts v1.8.3, Istio v1.29.2 |
| **Data Quality** | Great Expectations 1.4.4 |
| **Explainability** | SHAP 0.46.0, LIME 0.2.0.1 |
| **Load Testing** | Locust 2.32.4 |
 
---
 
## 📁 Project Structure

```
MLOps-Projects/
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
│   ├── setup-networking.sh             # DAILY: Full automated cluster setup
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
│   ├── teardown-networking.sh          # Evening: delete peering + clean up
│   └── materialize_features.py         # Feature materialization script
│
├── 🐳 Dockerfile                       # Multi-stage, apt-get upgrade for CVEs, non-root UID 1000
├── cluster.yaml                        # eksctl config — 3x t3.medium, S3FullAccess node IAM
├── .trivyignore                        # Accepted OS CVEs with no fix available in Debian
│
├── 📋 requirements-api.txt             # fastapi==0.136.1, shap==0.46.0, lime==0.2.0.1
├── 📋 requirements-dev.txt             # pytest, httpx, prometheus-client
├── 📋 requirements.txt                 # Full training environment dependencies
│
├── ⚙️  .github/workflows/
│   └── ci-cd.yml                       # 3 jobs: Run Tests → Trivy Scan → Build & Push ECR
│
├── 📖 README.md                        # Full project documentation (this file)
├── 🔧 TROUBLESHOOTING.md              # 40+ issues with root cause + solutions
└── 📅 README-ops.md                    # Daily operations runbook + resource IDs
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
 
## Updated Infrastructure Table
 
Add these rows to the Infrastructure section:
 
| Resource | Type | Purpose | Phase |
|----------|------|---------|-------|
| `argocd` namespace | K8s Namespace | ArgoCD GitOps controller | 13 |
| `argo-rollouts` namespace | K8s Namespace | Progressive delivery controller | 14 |
| `istio-system` namespace | K8s Namespace | Istio control plane | 14 |
| `churn-prediction-api-vsvc` | Istio VirtualService | Exact canary traffic splitting | 14 |
| `churn-prediction-api-destrule` | Istio DestinationRule | Stable/canary subset routing | 14 |
| `churn-api-success-rate` | AnalysisTemplate | Prometheus-based rollback gate | 14 |
| Cluster Autoscaler | K8s Deployment | Automatic node scaling (ASG 3→6) | 13 |
| `churn-mlops-artifacts/great_expectations/` | S3 prefix | Validation report storage | 15 |
| `churn-mlops-artifacts/explainability/` | S3 prefix | SHAP/LIME plot storage | 16 |

---

## 🌐 Infrastructure

### Additional AWS Resources

| Resource | Type | Purpose | Phase |
|----------|------|---------|-------|
| `churn-mlops-irsa-role` | IAM Role | Pod-scoped AWS credentials | 9.2 |
| `churn-mlops-s3-policy` | IAM Policy | S3 access (2 buckets only) | 9.2 |
| `churn-mlops-secrets-policy` | IAM Policy | Secrets Manager read | 9.3 |
| `churn-mlops/mlflow-tracking-uri` | Secrets Manager | Encrypted MLflow URI | 9.3 |
| `churn-stream-processor` | ECR | Kafka consumer image | 10 |
| `churn-materialize` | ECR | Feature materialization image | 12 |
| `ebs-sc` | K8s StorageClass | EBS gp2 for Airflow PostgreSQL | 12 |
| `aws-ebs-csi-driver` | EKS Addon | Dynamic EBS volume provisioning | 12 |
| `argocd` namespace | K8s Namespace | ArgoCD GitOps controller | 13 |
| `argo-rollouts` namespace | K8s Namespace | Progressive delivery controller | 14 |
| `istio-system` namespace | K8s Namespace | Istio control plane | 14 |
| `churn-prediction-api-vsvc` | Istio VirtualService | Exact canary traffic splitting | 14 |
| `churn-prediction-api-destrule` | Istio DestinationRule | Stable/canary subset routing | 14 |
| `churn-api-success-rate` | AnalysisTemplate | Prometheus-based rollback gate | 14 |
| Cluster Autoscaler | K8s Deployment | Automatic node scaling (ASG 3→6) | 13 |
| `churn-mlops-artifacts/great_expectations/` | S3 prefix | Validation report storage | 15 |
| `churn-mlops-artifacts/explainability/` | S3 prefix | SHAP/LIME plot storage | 16 |

### Updated Cost Estimate (3 nodes)

| Resource | Cost/hour |
|----------|----------|
| EKS Control Plane | $0.10 |
| 3x t3.medium nodes | $0.12 |
| EC2 t3.small (MLflow) | $0.023 |
| RDS db.t3.micro | $0.016 |
| ALB | ~$0.008 |
| EBS volumes (Airflow) | ~$0.003 |
| **Total** | **~$0.27/hour** |

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

### Remaining 🔲

| Phase | What | Tools |
|-------|------|-------|
| Phase | What | Tools |
|-------|------|-------|
| 19 | Hardening | NAT, HTTPS, ElastiCache, IAM least privilege |

---

## 👨‍💻 Author

**Himanshu Singh (Heman)**
- Cloud DevOps Engineer @ Mindstix Software Labs
- MTech CS @ VNIT Nagpur (Federated Learning + Adversarial ML)
- GitHub: [@Himanshu9001](https://github.com/Himanshu9001)

---

## 📄 License

This project is for learning and portfolio purposes.
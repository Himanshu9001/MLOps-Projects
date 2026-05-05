# 🚀 End-to-End MLOps Pipeline — Customer Churn Prediction

[![CI/CD Pipeline](https://github.com/Himanshu9001/MLOps-Projects/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Himanshu9001/MLOps-Projects/actions)
![Python](https://img.shields.io/badge/Python-3.12-blue)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.34-blue)
![MLflow](https://img.shields.io/badge/MLflow-2.22-orange)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-green)

A production-grade, end-to-end MLOps pipeline built from scratch — covering data versioning, experiment tracking, model registry, containerization, CI/CD, Kubernetes deployment, monitoring, and data drift detection.

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

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA LAYER                                │
│  Raw Data (S3) ──DVC──▶ Processed Data (S3)                     │
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
| **Infrastructure** | AWS EC2, RDS PostgreSQL, S3, EKS, ALB |
| **IaC** | eksctl, Helm, bash scripts |
| **Testing** | pytest, httpx, pytest-asyncio |

---

## 📁 Project Structure

```
MLOps-Projects/
├── app/
│   ├── main.py                    # FastAPI application
│   └── __init__.py
├── src/
│   ├── preprocess.py              # Data preprocessing pipeline
│   ├── train.py                   # Training with MLflow tracking
│   ├── register_model.py          # Model registration + promotion
│   └── drift_detection.py         # Evidently AI drift detection
├── tests/
│   ├── test_api.py                # FastAPI endpoint tests
│   └── test_preprocess.py         # Preprocessing unit tests
├── k8s/
│   ├── namespace.yaml             # K8s namespace
│   ├── deployment.yaml            # K8s deployment
│   ├── service.yaml               # LoadBalancer service
│   ├── hpa.yaml                   # Horizontal Pod Autoscaler
│   └── servicemonitor.yaml        # Prometheus ServiceMonitor
├── helm/
│   ├── churn-mlops/               # Application Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── hpa.yaml
│   │       ├── namespace.yaml
│   │       ├── secret.yaml
│   │       └── servicemonitor.yaml
│   └── monitoring/
│       └── values.yaml            # Prometheus + Grafana config
├── scripts/
│   ├── setup-networking.sh        # Full EKS networking automation
│   ├── teardown-networking.sh     # Cleanup before cluster deletion
│   ├── setup-mlflow-infra.sh      # EC2 + RDS + S3 setup
│   └── teardown-mlflow-infra.sh   # Stop EC2 + RDS
├── data/
│   ├── raw/                       # Raw data (DVC tracked)
│   └── processed/                 # Train/test splits (DVC tracked)
├── grafana/
│   └── dashboards/                # Grafana dashboard JSON
├── cluster.yaml                   # eksctl cluster config
├── Dockerfile                     # Multi-stage Docker build
├── .dockerignore
├── requirements.txt               # Full dev dependencies
├── requirements-api.txt           # Minimal API dependencies
├── requirements-dev.txt           # Test dependencies
├── .github/
│   └── workflows/
│       └── ci-cd.yml              # GitHub Actions pipeline
└── README-ops.md                  # Operations runbook
```

---

## ✅ Phases Completed

### Phase 1 — Data Versioning (DVC + S3)

**What:** Version control for ML datasets using DVC with AWS S3 as remote storage.

**Key concepts:**
- DVC tracks data files using MD5 content-addressable storage
- Only small `.dvc` pointer files go to Git — actual data goes to S3
- Full data versioning — roll back to any previous dataset version

**Commands:**
```bash
# Track data
dvc add data/raw/churn.csv
git add data/raw/churn.csv.dvc
git commit -m "data: track dataset"
dvc push  # uploads to S3

# Pull data (on new machine)
git clone <repo>
dvc pull  # downloads from S3
```

**Infrastructure:**
- S3 bucket: `churn-mlops-dvc-store`
- DVC remote: configured in `.dvc/config`

---

### Phase 2 — Experiment Tracking (MLflow)

**What:** Track every training experiment — parameters, metrics, artifacts, and graphs.

**Key concepts:**
- Every training run automatically logs params, metrics, model artifacts
- MLflow UI for comparing experiments side by side
- Parallel Coordinates plot for multi-run comparison

**Training:**
```bash
# Run experiment
python src/train.py --n_estimators 100 --max_depth 10 --min_samples_split 2

# View experiments
mlflow ui
```

**Tracked metrics:**
| Metric | Value |
|--------|-------|
| Accuracy | 79.70% |
| F1 Score | 0.5719 |
| Precision | 0.6497 |
| Recall | 0.5107 |
| ROC AUC | 0.8358 |

**Artifacts logged:**
- `confusion_matrix.png`
- `roc_curve.png`
- `precision_recall_curve.png`
- `feature_importance.png`
- `feature_importance.json`
- `random_forest_model/` (model pickle)

---

### Phase 3 — Model Registry

**What:** Promote best models through Staging → Production lifecycle.

**Key concepts:**
- Auto-selects best validated run by ROC AUC
- Uses `model_validated=true` tag to filter eligible runs
- Dynamic S3 path resolution for model artifacts
- Alias-based promotion (MLflow 2.x standard)

```bash
# Tag run as validated
python -c "
from mlflow.tracking import MlflowClient
client = MlflowClient('http://98.86.0.163:5000')
client.set_tag('<run_id>', 'model_validated', 'true')
"

# Auto-register best model
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/register_model.py

# Manual registration
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/register_model.py --run_id <run_id>
```

**Model lifecycle:**
```
Training Run (validated) → Registered → Staging → Production
```

---

### Phase 4 — Docker + FastAPI

**What:** Containerize the model as a REST API with production-grade Docker best practices.

**API Endpoints:**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API info |
| `/health` | GET | Health check |
| `/predict` | POST | Churn prediction |
| `/metrics` | GET | Prometheus metrics |
| `/docs` | GET | Swagger UI |

**Example prediction:**
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{
    "gender": 0, "SeniorCitizen": 0, "Partner": 0,
    "Dependents": 0, "tenure": 2, "PhoneService": 1,
    "MultipleLines": 0, "InternetService": 1,
    "OnlineSecurity": 0, "OnlineBackup": 0,
    "DeviceProtection": 0, "TechSupport": 0,
    "StreamingTV": 0, "StreamingMovies": 0,
    "Contract": 0, "PaperlessBilling": 1,
    "PaymentMethod": 2, "MonthlyCharges": 70.7,
    "TotalCharges": 151.65
  }'
```

**Response:**
```json
{
  "churn": 1,
  "probability": 0.6735,
  "risk_level": "MEDIUM",
  "message": "Customer has moderate churn risk. Consider retention offer."
}
```

**Docker best practices applied:**
- Multi-stage build (builder + runtime)
- Non-root user (UID 1000)
- HEALTHCHECK instruction
- Minimal base image (`python:3.12-slim`)
- Layer caching optimization
- `.dockerignore` for small build context

```bash
# Build
docker build -t churn-prediction-api:v1 .

# Run locally
docker run -d \
  --name churn-api \
  -p 8000:8000 \
  -e MLFLOW_TRACKING_URI=http://98.86.0.163:5000 \
  churn-prediction-api:v1
```

---

### Phase 5 — CI/CD (GitHub Actions)

**What:** Automated testing and Docker image publishing on every push.

**Pipeline:**
```
Push to main
    ↓
Job 1: Test
  - Install dependencies
  - Run pytest (18 tests)
    ↓ (only if tests pass)
Job 2: Build & Push
  - Configure AWS credentials
  - Login to ECR
  - Build Docker image
  - Tag with commit SHA + latest
  - Push to ECR
```

**Test coverage:**
- 9 API tests (health, predict, validation)
- 9 preprocessing tests (cleaning, splitting, saving)
- Total: 18 tests, 0 failures

**Secrets required:**
| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |

---

### Phase 6 — Kubernetes EKS

**What:** Deploy to production Kubernetes with auto-scaling, health checks, and rolling updates.

**Infrastructure:**
```
AWS EKS Cluster (us-east-1)
├── 2x t3.medium nodes
├── Kubernetes 1.34
└── Managed node group

VPC (10.0.0.0/16)
├── Public Subnet  (10.0.1.0/24) — EC2 MLflow
├── Private Subnet 1 (10.0.2.0/24) — RDS
└── Private Subnet 2 (10.0.3.0/24) — RDS (multi-AZ)

VPC Peering: churn-mlops-vpc ↔ EKS VPC
```

**Kubernetes resources:**
| Resource | Config |
|----------|--------|
| Deployment | 2 replicas, RollingUpdate |
| Service | LoadBalancer (AWS ALB) |
| HPA | min 1, max 3, CPU 70%, Memory 80% |
| Namespace | churn-mlops |

**Deployment:**
```bash
# Full automated setup
eksctl create cluster -f cluster.yaml
./scripts/setup-networking.sh

# Helm deploy
helm upgrade --install churn-mlops helm/churn-mlops/ \
  --values helm/churn-mlops/values.yaml

# Check status
kubectl get all -n churn-mlops
```

**MLflow Production Setup:**
| Component | Service |
|-----------|---------|
| Tracking server | EC2 t3.small (Elastic IP: 98.86.0.163) |
| Backend store | RDS PostgreSQL db.t3.micro |
| Artifact store | S3 bucket: churn-mlops-artifacts |

---

### Phase 7 — Monitoring (Prometheus + Grafana)

**What:** Full observability stack with pre-built K8s dashboards and custom API metrics.

**Stack:**
```
FastAPI /metrics endpoint
    ↓ (scraped every 15s)
Prometheus (via ServiceMonitor)
    ↓
Grafana Dashboards
```

**Metrics tracked:**
| Metric | Description |
|--------|-------------|
| `http_requests_total` | Request count by endpoint/status |
| `http_request_duration_seconds` | Latency histogram |
| `http_requests_in_progress` | Active requests |
| Node CPU/Memory | Per EKS node |
| Pod CPU/Memory | Per pod in churn-mlops |

**Pre-built dashboards:**
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / API Server
- AlertManager Overview
- Custom: Churn Prediction API

**Installation:**
```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/monitoring/values.yaml
```

**Access Grafana:**
```
URL:      http://<grafana-lb-url>
Username: admin
Password: admin123
```

---

### Phase 8 — Data Drift Detection (Evidently AI)

**What:** Detect when production data distribution shifts from training data.

**How it works:**
```
Reference data (training set)
    ↓
Compare with production data
    ↓
Statistical tests per feature
    ↓
Drift share calculated
    ↓
Alert if drift_share > threshold
    ↓
HTML report + MLflow logging
```

**Usage:**
```bash
# Run drift check (default threshold 50%)
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/drift_detection.py

# Custom threshold (10%)
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/drift_detection.py --threshold 0.1
```

**Output:**
```
==================================================
DRIFT DETECTION SUMMARY
==================================================
Drift Detected: 🚨 YES
4 columns drifted (21.1%)
Report: reports/drift_report_20260503_182443.html
==================================================
```

**Features monitored:**
- Numerical: `tenure`, `MonthlyCharges`, `TotalCharges`
- Categorical: all 16 encoded categorical features

---

## 🌐 Infrastructure

### AWS Resources

| Resource | Type | Purpose |
|----------|------|---------|
| `churn-mlops-vpc` | VPC (10.0.0.0/16) | Network isolation |
| `churn-mlops-public-1a` | Subnet (10.0.1.0/24) | EC2 MLflow |
| `churn-mlops-private-1a` | Subnet (10.0.2.0/24) | RDS |
| `churn-mlops-private-1b` | Subnet (10.0.3.0/24) | RDS (multi-AZ) |
| `churn-mlops-igw` | Internet Gateway | Public internet access |
| `mlflow-sg` | Security Group | EC2 ports 22, 5000 |
| `rds-sg` | Security Group | PostgreSQL port 5432 |
| `mlflow-server` | EC2 t3.small | MLflow tracking server |
| `mlflow-db` | RDS PostgreSQL db.t3.micro | MLflow backend store |
| `churn-mlops-artifacts` | S3 | MLflow artifact store |
| `churn-mlops-dvc-store` | S3 | DVC data versioning |
| `churn-prediction-api` | ECR | Docker image registry |
| `churn-mlops` | EKS 1.34 | Kubernetes cluster |

### Cost Estimate (when running)

| Resource | Cost/hour |
|----------|----------|
| EKS Control Plane | $0.10 |
| 2x t3.medium nodes | $0.08 |
| EC2 t3.small (MLflow) | $0.023 |
| RDS db.t3.micro | $0.016 |
| ALB | ~$0.008 |
| **Total** | **~$0.23/hour** |

> 💡 Stop EC2 + RDS and delete EKS when not in use to minimize costs.

---

## 🚀 Getting Started

### Prerequisites

```bash
# Required tools
brew install eksctl kubectl helm awscli
brew install colima docker
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Start Colima
colima start
```

### First Time Setup

```bash
# 1. Clone repo
git clone https://github.com/Himanshu9001/MLOps-Projects.git
cd MLOps-Projects

# 2. Create virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Configure AWS
aws configure

# 4. Pull data from DVC
dvc pull

# 5. Setup MLflow infrastructure
./scripts/setup-mlflow-infra.sh

# 6. Create EKS cluster (15 min)
eksctl create cluster -f cluster.yaml

# 7. Setup networking + deploy
./scripts/setup-networking.sh
```

### Train and Deploy New Model

```bash
# 1. Preprocess data
python src/preprocess.py

# 2. Train model
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/train.py \
  --n_estimators 100 --max_depth 10 --min_samples_split 2

# 3. Tag run as validated
python -c "
from mlflow.tracking import MlflowClient
client = MlflowClient('http://98.86.0.163:5000')
client.set_tag('<run_id>', 'model_validated', 'true')
"

# 4. Register model
MLFLOW_TRACKING_URI=http://98.86.0.163:5000 python src/register_model.py

# 5. Deploy new image (CI/CD handles this automatically on push)
git add . && git commit -m "feat: new model" && git push origin main
```

---

## 📅 Daily Operations

### Morning — Start Everything

```bash
./scripts/setup-mlflow-infra.sh    # starts EC2 + RDS (~2 min)
eksctl create cluster -f cluster.yaml  # creates EKS (~15 min)
./scripts/setup-networking.sh          # full setup + deploy (~3 min)
```

### Evening — Stop Everything

```bash
./scripts/teardown-networking.sh
eksctl delete cluster --name churn-mlops --region us-east-1
./scripts/teardown-mlflow-infra.sh
```

---

## 📡 API Reference

### Health Check
```http
GET /health
```
```json
{"status": "healthy", "model_loaded": true}
```

### Predict Churn
```http
POST /predict
Content-Type: application/json
```

**Request body:**
| Field | Type | Description |
|-------|------|-------------|
| `gender` | int | 0=Female, 1=Male |
| `SeniorCitizen` | int | 0=No, 1=Yes |
| `tenure` | int | Months with company |
| `Contract` | int | 0=Month-to-month, 1=One year, 2=Two year |
| `MonthlyCharges` | float | Monthly bill |
| `TotalCharges` | float | Total billed |
| *(+13 more fields)* | | |

**Response:**
| Field | Type | Description |
|-------|------|-------------|
| `churn` | int | 0=Stay, 1=Churn |
| `probability` | float | Churn probability (0-1) |
| `risk_level` | string | HIGH/MEDIUM/LOW |
| `message` | string | Business recommendation |

**Risk levels:**
| Level | Probability | Action |
|-------|-------------|--------|
| HIGH | ≥ 0.70 | Immediate action needed |
| MEDIUM | ≥ 0.40 | Consider retention offer |
| LOW | < 0.40 | Customer likely to stay |

---

## 🗺️ Roadmap

### In Progress
- Phase 9: MLSecOps (Trivy, OPA, IRSA)
- Phase 10: Streaming Pipeline (Kafka, Flink, Redis)

### Planned
| Phase | What | Tools |
|-------|------|-------|
| 9 | MLSecOps | Trivy, OPA, Vault, IRSA |
| 10 | Streaming | Kafka, Flink, Redis |
| 11 | Feature Store | Feast, Redis |
| 12 | Auto Retraining | Airflow |
| 13 | GitOps | ArgoCD |
| 14 | Advanced Serving | A/B testing, Canary, Istio |
| 15 | Data Quality | Great Expectations |
| 16 | Explainability | SHAP, LIME |
| 17 | Load Testing | Locust, k6 |
| 18 | Multi-environment | dev/staging/prod |
| 19 | Hardening | NAT, HTTPS, IAM |
| 20 | LLMOps | Langfuse, RAG, RAGAS |
| 20.5 | Benchmarking | Locust, py-spy |
| 20.6 | GPU Optimization | ONNX, TensorRT, vLLM |
| 21 | Distributed Training | PyTorch DDP, Kubeflow |
| 22 | Model Security | ART, Opacus, Defensive Distillation |
| 23 | Federated Learning | Flower, PySyft, Homomorphic Encryption |

---

## 👨‍💻 Author

**Himanshu Singh (Heman)**
- Cloud DevOps Engineer @ Mindstix Software Labs
- MTech CS @ VNIT Nagpur (Federated Learning + Adversarial ML)
- GitHub: [@Himanshu9001](https://github.com/Himanshu9001)

---

## 📄 License

This project is for learning and portfolio purposes.
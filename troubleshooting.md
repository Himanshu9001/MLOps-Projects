# 🔧 Troubleshooting Guide — MLOps Customer Churn Pipeline
 
A comprehensive log of every real issue encountered during the build of this pipeline — with root cause analysis, fix, and lesson learned. Built iteratively throughout the project — every error was a learning opportunity.
 
---
 
## 📋 Table of Contents
 
1. [Python Virtual Environment Issues](#1-python-virtual-environment-issues)
2. [DVC Issues](#2-dvc-issues)
3. [MLflow Issues](#3-mlflow-issues)
4. [Docker Issues](#4-docker-issues)
5. [FastAPI Issues](#5-fastapi-issues)
6. [CI/CD Issues](#6-cicd-issues)
7. [AWS Infrastructure Issues](#7-aws-infrastructure-issues)
8. [Kubernetes Issues](#8-kubernetes-issues)
9. [Phase 9 — MLSecOps](#phase-9--mlsecops)
10. [Phase 10 — Streaming Pipeline](#phase-10--streaming-pipeline)
11. [Phase 11 — Feature Store](#phase-11--feature-store)
12. [Phase 12 — Airflow](#phase-12--airflow)

## 1. Python Virtual Environment Issues

### Issue 1.1 — pip user install blocked in venv

**Error:**
```
ERROR: Can not perform a '--user' install. User site-packages are not visible in this virtualenv.
```

**Root Cause:**
`~/.config/pip/pip.conf` had `user = true` set globally, which conflicts with virtual environment isolation.

**Solution:**
```bash
# Check pip config
cat ~/.config/pip/pip.conf

# Remove user = true line
nano ~/.config/pip/pip.conf
# Delete the line: user = true
# Keep: break-system-packages = true

# Then use python3 -m pip instead of pip
python3 -m pip install --upgrade pip
```

**Lesson learned:** Always use `python3 -m pip` for the first upgrade inside a venv to avoid user-site conflicts.

---

## 2. DVC Issues

### Issue 2.1 — DVC rollback failed (pointer not on GitHub)

**Error:**
```
error: pathspec 'data/raw/churn.csv.dvc' did not match any file(s) known to git
```

**Root Cause:**
The `.dvc` pointer file was never pushed to GitHub after the first `dvc add`. Git couldn't find it because it only existed locally.

**Solution:**
Always push pointer files immediately after tracking:
```bash
dvc add data/raw/churn.csv
git add data/raw/churn.csv.dvc
git commit -m "data: track dataset"
git push origin main   # ← never skip this
dvc push
```

**Lesson learned:** `git push` must happen right after `dvc add` — the pointer file and data must be in sync on both GitHub and S3.

---

### Issue 2.2 — `head -n -1` not supported on Mac

**Error:**
```
head: illegal line count -- -1
```

**Root Cause:**
GNU `head` supports `head -n -1` (remove last N lines) but macOS `head` does not.

**Solution:**
```bash
# Mac-compatible way to remove last N lines
total=$(wc -l < data/raw/churn.csv)
head -n $((total - 1)) data/raw/churn.csv > data/raw/tmp.csv
mv data/raw/tmp.csv data/raw/churn.csv
```

**Lesson learned:** Mac BSD tools behave differently from Linux GNU tools. Always test shell commands on the target OS.

---

### Issue 2.3 — DVC remote not configured (empty .dvc/config)

**Error:**
```
# cat .dvc/config showed empty file
```

**Root Cause:**
`dvc remote add` command was run but the result wasn't verified before committing.

**Solution:**
```bash
dvc remote add -d myremote s3://churn-mlops-dvc-store
cat .dvc/config  # verify before committing
```

**Lesson learned:** Always verify config files after running configuration commands.

---

## 3. MLflow Issues

### Issue 3.1 — `artifact_path` deprecated in MLflow 2.22

**Error:**
```
WARNING mlflow.models.model: `artifact_path` is deprecated. Please use `name` instead.
```

**Root Cause:**
MLflow 2.22 changed the API — `artifact_path` parameter was deprecated in favor of `name`.

**First attempted fix (wrong):**
```python
mlflow.sklearn.log_model(model, name="random_forest_model")
```

**Problem with fix:**
Using `name=` stores the model in `mlruns/1/models/` instead of `mlruns/1/<run_id>/artifacts/` — breaking `list_artifacts()`.

**Final solution:**
Use `artifact_path=` for storage compatibility, then update `register_model.py` to use S3 path directly:
```python
# In train.py — use artifact_path for correct storage location
mlflow.sklearn.log_model(model, artifact_path="random_forest_model")

# In register_model.py — find model via S3 directly
import boto3
s3 = boto3.client('s3')
response = s3.list_objects_v2(Bucket='churn-mlops-artifacts', Prefix=f"{experiment_id}/models/")
for obj in response.get('Contents', []):
    if 'MLmodel' in obj['Key']:
        model_prefix = '/'.join(obj['Key'].split('/')[:-1])
        break
```

**Lesson learned:** When upgrading MLflow versions, always check storage behavior changes — API changes often affect artifact paths.

---

### Issue 3.2 — MLflow model registration hanging (500 errors)

**Error:**
```
urllib3.exceptions.ResponseError: too many 500 error responses
```

**Root Cause:**
MLflow 3.x `register_model()` tries to copy the 6MB model.pkl from S3 to the EC2 server during registration. Gunicorn worker timeout (30s default) was too short for this operation.

**Solution:**
1. Increase gunicorn timeout:
```bash
mlflow server ... --gunicorn-opts "--timeout 120 -w 2"
```

2. Bypass the copy entirely using `client.create_model_version()` with direct S3 path:
```python
model_version = client.create_model_version(
    name=model_name,
    source=f"s3://churn-mlops-artifacts/{model_prefix}",
    run_id=run_id,
    await_creation_for=300
)
```

**Lesson learned:** MLflow 3.x changed registration behavior to copy artifacts. Always check MLflow version changelog when upgrading.

---

### Issue 3.3 — MLflow DNS rebinding attack detection

**Error:**
```
403: Invalid Host header - possible DNS rebinding attack detected
```

**Root Cause:**
MLflow UI blocks requests from `host.docker.internal` as a security measure against DNS rebinding attacks.

**Solution:**
1. Start MLflow with `--host 0.0.0.0` (allows external connections)
2. Use actual Mac IP instead of `host.docker.internal`:
```bash
mlflow ui --host 0.0.0.0 --port 5000
ipconfig getifaddr en0  # get your Mac IP
docker run -e MLFLOW_TRACKING_URI=http://192.168.1.7:5000 ...
```

**Lesson learned:** `host.docker.internal` doesn't work reliably with all services. Using actual IP is more reliable.

---

### Issue 3.4 — MLflow model not found in artifacts (new storage path)

**Error:**
```
OSError: No such file or directory: '/Users/.../mlruns/1/models/m-xxx/artifacts/.'
```

**Root Cause:**
MLflow 2.22+ with `name=` parameter stores models in `mlruns/1/models/` not `mlruns/1/<run_id>/artifacts/`. The Docker container can't access the local Mac filesystem.

**Solution:**
Mount the `mlruns/` directory into the container:
```bash
docker run -v $(pwd)/mlruns:/Users/himanshusingh/.../mlruns ...
```

**Long-term solution:** Use production MLflow server on EC2 with S3 artifact store — no filesystem mounting needed.

**Lesson learned:** Local MLflow for development is fine but containers need either a shared filesystem or a remote MLflow server.

---

### Issue 3.5 — Model auto-registration picking wrong run

**Problem:**
`get_best_run()` kept picking an old run with high ROC AUC but no real model artifacts (only a 260KB pointer file instead of 6MB real model).

**Root Cause:**
The old run had artificially high ROC AUC metrics but its model artifacts were corrupt (just a reference pointer).

**Solution evolved through 3 attempts:**

Attempt 1 (hack — rejected): Size check `model.pkl > 1MB`
```python
# BAD — fragile, arbitrary threshold
if model_pkl and model_pkl[0].file_size > 1_000_000:
```

Attempt 2 (better): `model_validated` tag filter
```python
filter_string="attributes.status = 'FINISHED' AND tags.model_validated = 'true'"
```

Final solution (production grade): Tag-based validation
```python
# In train.py — set tag after successful training
mlflow.set_tags({"model_validated": "true"})

# In register_model.py — filter by tag
runs = client.search_runs(
    filter_string="attributes.status = 'FINISHED' AND tags.model_validated = 'true'"
)
```

**Lesson learned:** Use semantic tags for model governance — never use file size or other hacky heuristics.

---

### Issue 3.6 — scikit-learn version mismatch in container

**Error:**
```
InconsistentVersionWarning: Trying to unpickle RandomForestClassifier 
from version 1.8.0 when using version 1.6.1
```

**Root Cause:**
Model was trained with `scikit-learn 1.8.0` locally but `requirements-api.txt` pinned `scikit-learn==1.6.1`.

**Solution:**
```bash
# Check local version
pip show scikit-learn | grep Version  # → 1.8.0

# Update requirements-api.txt
scikit-learn==1.8.0

# Rebuild image with --no-cache
docker rmi churn-prediction-api:v1
docker build --no-cache -t churn-prediction-api:v1 .
```

**Lesson learned:** Always pin the exact same library versions in training and serving environments.

---

## 4. Docker Issues

### Issue 4.1 — docker command not found (Colima)

**Error:**
```
zsh: command not found: docker
```

**Root Cause:**
Docker Desktop was not installed. Colima was installed but Docker socket wasn't properly configured.

**Solution:**
```bash
brew install colima docker
colima start

# Set Docker socket
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

**Better solution:** Add to `~/.zshrc`:
```bash
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

---

### Issue 4.2 — `docker buildx` not working

**Error:**
```
unknown shorthand flag: 't' in -t
```

**Root Cause:**
`docker buildx` was not installed as a plugin. The Docker CLI couldn't find it.

**Solution:**
```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sf $(brew --prefix)/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx
```

---

### Issue 4.3 — Docker image too large (1.45GB)

**Problem:**
Initial Docker image was 1.45GB because `requirements.txt` (full dev environment) was used instead of minimal API requirements.

**Solution:**
Created separate `requirements-api.txt` with only what the API needs:
```
fastapi==0.115.12
uvicorn==0.34.3
pydantic==2.11.4
mlflow-skinny==2.22.0
scikit-learn==1.8.0
numpy==1.26.4
pandas==2.2.3
```

**Size reduction journey:**
| Change | Size |
|--------|------|
| Full requirements.txt | 1.45GB |
| requirements-api.txt | 873MB |
| mlflow → mlflow-skinny | 747MB |
| Remove boto3 | 747MB (no change — transitive dep) |
| Add pandas back (required by mlflow) | 873MB |

**Lesson learned:** Always create separate requirements files for production. Use `mlflow-skinny` instead of `mlflow` for serving.

---

### Issue 4.4 — pandas required by mlflow-skinny

**Problem:**
Removed pandas to reduce image size but container crashed:
```
ModuleNotFoundError: No module named 'pandas'
```

**Root Cause:**
Even `mlflow-skinny` internally imports pandas in `mlflow/models/utils.py`. It's a transitive dependency you can't avoid.

**Solution:**
Add pandas back to `requirements-api.txt`. Accept the larger image size.

**Lesson learned:** Some dependencies are unavoidable transitive requirements. Check actual import chains before removing packages.

---

### Issue 4.5 — Dockerfile running as root

**Problem:**
Default Docker containers run as root — security risk.

**Solution:**
Add non-root user to Dockerfile:
```dockerfile
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --no-create-home appuser
COPY --chown=appuser:appgroup app/ ./app/
USER appuser
```

**Lesson learned:** Always run containers as non-root in production. Kubernetes `runAsNonRoot: true` will block root containers.

---

## 5. FastAPI Issues

### Issue 5.1 — `on_event` deprecated in newer FastAPI

**Warning:**
```
DeprecationWarning: on_event is deprecated, use lifespan event handlers instead.
```

**Root Cause:**
FastAPI deprecated `@app.on_event("startup")` in favor of lifespan context managers.

**Solution:**
```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    await load_model()  # startup
    yield
    # shutdown code here if needed

app = FastAPI(lifespan=lifespan, ...)
```

**Lesson learned:** Always check deprecation warnings — they become errors in future versions.

---

### Issue 5.2 — Duplicate FastAPI app definition

**Problem:**
`/metrics` endpoint returned 404 even though Prometheus instrumentation was added.

**Root Cause:**
`app` was defined twice in `main.py`:
```python
# Line 18 — first app (Instrumentator applied here)
app = FastAPI(title="Churn Prediction API", ...)
Instrumentator().instrument(app).expose(app)

# Line 68 — second app (this one actually runs)
app = FastAPI(title="Churn Prediction API", lifespan=lifespan, ...)
```

Instrumentator was applied to the first `app` but the second `app` (with lifespan) was the one serving requests.

**Solution:**
Remove the first app definition, keep only one:
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await load_model()
    yield

app = FastAPI(
    title="Churn Prediction API",
    version="1.0.0",
    lifespan=lifespan
)

# Apply AFTER single app definition
Instrumentator().instrument(app).expose(app)
```

**Lesson learned:** Never define the same variable twice. Code review would have caught this immediately.

---

## 6. CI/CD Issues

### Issue 6.1 — pytest not found in CI

**Error:**
```
/tmp/xxx.sh: line 1: pytest: command not found
```

**Root Cause:**
`pytest` was installed in the virtual environment locally but not in `requirements.txt` used by CI.

**Solution:**
Create `requirements-dev.txt`:
```
pytest==9.0.3
pytest-asyncio==1.3.0
httpx==0.28.1
prometheus-fastapi-instrumentator==7.1.0
prometheus-client==0.25.0
```

Update CI workflow:
```yaml
- name: Install dependencies
  run: |
    pip install -r requirements.txt
    pip install -r requirements-dev.txt

- name: Run tests
  run: python -m pytest tests/ -v --tb=short
```

**Lesson learned:** Always use `python -m pytest` instead of `pytest` in CI for correct Python path resolution.

---

### Issue 6.2 — AWS secret key exposed in chat

**Problem:**
AWS secret key was accidentally pasted in the chat conversation.

**Solution:**
1. Immediately rotate the key:
   - AWS Console → Security Credentials → Delete old key
   - Create new access key
2. Update local `aws configure`
3. Update GitHub Secrets

**Lesson learned:** Never paste AWS credentials anywhere. Use `aws configure` to set them and `aws sts get-caller-identity` to verify. If exposed, rotate immediately.

---

### Issue 6.3 — `prometheus-fastapi-instrumentator` packages merged on same line

**Error:**
```
Invalid requirement: 'httpx==0.28.1prometheus-fastapi-instrumentator==7.1.0'
```

**Root Cause:**
Used `echo "package" >> requirements-dev.txt` which appended without a newline, merging two packages on the same line.

**Solution:**
```bash
# Use tee/cat with heredoc instead
cat > requirements-dev.txt << 'EOF'
pytest==9.0.3
pytest-asyncio==1.3.0
httpx==0.28.1
prometheus-fastapi-instrumentator==7.1.0
prometheus-client==0.25.0
EOF
```

**Lesson learned:** Use heredoc or a text editor for multi-line files — `echo >>` can cause line ending issues.

---

### Issue 6.4 — API tests failing in CI (MLflow model not found)

**Error:**
```
RuntimeError: Model loading failed: No such file or directory: 
'/Users/himanshusingh/.../mlruns/...'
```

**Root Cause:**
The `client` fixture in `test_api.py` was trying to load the real MLflow model during test setup because the mock wasn't applied before the lifespan ran.

**Solution:**
Mock `mlflow.sklearn.load_model` directly instead of mocking the global `model` variable:
```python
@pytest.fixture
def client(mock_model):
    with patch('mlflow.sklearn.load_model', return_value=mock_model):
        from app.main import app
        with TestClient(app) as c:
            yield c
```

**Lesson learned:** When testing FastAPI with lifespan, mock the dependencies (mlflow.load_model) not the results (model variable).

---

## 7. AWS Infrastructure Issues

### Issue 7.1 — RDS subnet group creation failed (wrong filter)

**Error:**
```
An error occurred (InvalidParameterValue): The filter 'defaultVpc' is invalid
```

**Root Cause:**
Used `"Name=defaultVpc,Values=true"` but the correct filter name is `"Name=isDefault,Values=true"`.

**Solution:**
```bash
# Get default VPC
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text
```

---

### Issue 7.2 — EKS CloudFormation stack already exists

**Error:**
```
AlreadyExistsException: Stack [eksctl-churn-mlops-cluster] already exists
```

**Root Cause:**
EKS cluster was deleted but the CloudFormation stack got stuck in `DELETE_FAILED` state due to VPC Peering still being attached.

**Solution:**
```bash
# 1. Delete peering first
aws ec2 delete-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxx

# 2. Force delete the stuck stack
aws cloudformation delete-stack \
  --stack-name eksctl-churn-mlops-cluster

# 3. Wait for completion
aws cloudformation describe-stacks \
  --stack-name eksctl-churn-mlops-cluster 2>&1 | grep "does not exist"

# 4. Recreate cluster
eksctl create cluster -f cluster.yaml
```

**Lesson learned:** Always run teardown script before deleting EKS cluster to clean up VPC peering connections first.

---

### Issue 7.3 — EC2 user data script failed (requests package conflict)

**Error in cloud-init logs:**
```
ERROR: Cannot uninstall requests 2.25.1, RECORD file not found. 
Hint: The package was installed by rpm.
```

**Root Cause:**
The user data script tried to `pip install mlflow` which attempted to upgrade the system `requests` package installed by `yum`. System packages installed by rpm don't have pip RECORD files, so pip can't uninstall them.

**Solution:**
Manually install MLflow after SSH-ing into EC2:
```bash
pip3 install mlflow boto3 psycopg2-binary --user
```

Then create the startup script manually.

**Lesson learned:** On Amazon Linux, avoid installing packages that conflict with system Python packages. Use `--user` flag or install as ec2-user.

---

### Issue 7.4 — Elastic IP showing as unused when EC2 stopped

**Problem:**
Elastic IP was allocated but when EC2 was stopped, AWS warned about unused EIP charges.

**Root Cause:**
Elastic IPs are free when attached to a running instance but cost $0.005/hour when unattached.

**Solution:**
Always stop EC2 via script which also handles EIP association:
```bash
# Stop EC2 (EIP stays associated — no charge)
aws ec2 stop-instances --instance-ids i-xxx
# EIP remains associated with stopped instance — no charge
```

**Lesson learned:** EIPs attached to stopped instances don't incur charges. Only unattached EIPs cost money.

---

## 8. Kubernetes Issues

### Issue 8.1 — EKS pods couldn't access S3 (AccessDenied)

**Error:**
```
RuntimeError: Model loading failed: An error occurred (AccessDenied) 
when calling the ListObjectsV2 operation
```

**Root Cause:**
EKS worker nodes didn't have IAM permissions to access S3. The node role `NodeInstanceRole` had no S3 policy attached.

**Solution:**
```bash
# Attach S3 policy to EKS node role
aws iam attach-role-policy \
  --role-name eksctl-churn-mlops-nodegroup-stand-NodeInstanceRole-xxx \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

**Better solution (in cluster.yaml):**
```yaml
managedNodeGroups:
  - name: standard-workers
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonS3FullAccess
```

**Lesson learned:** Always define IAM policies in cluster config so they're applied automatically on cluster creation.

---

### Issue 8.2 — VPC Peering route already exists on re-setup

**Error:**
```
RouteAlreadyExists: The route identified by 192.168.0.0/16 already exists.
```

**Root Cause:**
The setup script tried to `create-route` but a route from a previous cluster still existed in the route table.

**Solution:**
Use `create-route || replace-route` pattern:
```bash
aws ec2 create-route ... > /dev/null 2>&1 || \
aws ec2 replace-route ... > /dev/null
```

**Lesson learned:** Infrastructure scripts must be idempotent — handle "already exists" gracefully.

---

### Issue 8.3 — EKS VPC in different CIDR than expected

**Problem:**
Assumed EKS VPC CIDR would be `192.168.0.0/16` but it could vary between cluster recreations.

**Solution:**
Always dynamically fetch the EKS VPC CIDR:
```bash
EKS_CIDR=$(aws ec2 describe-vpcs \
  --vpc-ids $EKS_VPC_ID \
  --query 'Vpcs[0].CidrBlock' \
  --output text)
```

**Lesson learned:** Never hardcode VPC CIDRs. Always fetch dynamically.

---

### Issue 8.4 — EKS pods couldn't reach MLflow (VPC in different network)

**Problem:**
EKS pods tried to reach MLflow at `10.0.1.225` (our VPC) but EKS is in a separate VPC (`192.168.0.0/16`). No network path existed between them.

**Solution:**
Set up VPC Peering:
1. Create peering connection between our VPC and EKS VPC
2. Accept the peering request
3. Add routes in both VPCs
4. Update security group to allow traffic from EKS CIDR

**Lesson learned:** Always plan network topology before deploying. EKS creates its own VPC — plan for cross-VPC communication upfront.

---

## 9. Helm Issues

### Issue 9.1 — Helm install failed (resources exist without Helm labels)

**Error:**
```
INSTALLATION FAILED: unable to continue with install: Namespace "churn-mlops" 
exists and cannot be imported: missing key "app.kubernetes.io/managed-by"
```

**Root Cause:**
Resources were previously created with `kubectl apply` — they had no Helm ownership labels. Helm refused to manage resources it didn't create.

**Solution:**
Add Helm ownership labels to existing resources:
```bash
# Fix namespace
kubectl label namespace churn-mlops app.kubernetes.io/managed-by=Helm
kubectl annotate namespace churn-mlops \
  meta.helm.sh/release-name=churn-mlops \
  meta.helm.sh/release-namespace=default

# Fix all resources at once
for resource in $(kubectl get all,secret -n churn-mlops -o name); do
  kubectl label $resource -n churn-mlops \
    app.kubernetes.io/managed-by=Helm --overwrite
  kubectl annotate $resource -n churn-mlops \
    meta.helm.sh/release-name=churn-mlops \
    meta.helm.sh/release-namespace=default --overwrite
done
```

**Lesson learned:** Never mix `kubectl apply` and `helm install` for the same resources. Pick one and stick to it.

---

### Issue 9.2 — ServiceMonitor namespace mismatch

**Problem:**
ServiceMonitor lives in `monitoring` namespace but Helm release is in `default` namespace — causing ownership conflicts.

**Solution:**
Add explicit namespace in ServiceMonitor template:
```yaml
# helm/churn-mlops/templates/servicemonitor.yaml
metadata:
  namespace: {{ .Values.serviceMonitor.namespace }}  # "monitoring"
```

And in values.yaml:
```yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
```

**Lesson learned:** When a Helm resource lives in a different namespace than the release, always make the namespace explicit in the template.

---

### Issue 9.3 — `helm upgrade` failed (no deployed releases)

**Error:**
```
Error: UPGRADE FAILED: "churn-mlops" has no deployed releases
```

**Root Cause:**
Used `helm upgrade` but the release was never installed with Helm in the first place (resources existed from `kubectl apply`).

**Solution:**
Always use `helm upgrade --install` which handles both cases:
```bash
# This is idempotent — installs if not exists, upgrades if exists
helm upgrade --install churn-mlops helm/churn-mlops/ \
  --values helm/churn-mlops/values.yaml
```

**Lesson learned:** Prefer `helm upgrade --install` over separate `helm install` and `helm upgrade` commands.

---

## 10. Prometheus & Grafana Issues

### Issue 10.1 — Prometheus helm install failed (namespace not found)

**Error:**
```
INSTALLATION FAILED: create: failed to create: namespaces "monitoring" not found
```

**Root Cause:**
The `--namespace monitoring` flag requires the namespace to exist first.

**Solution:**
```bash
kubectl create namespace monitoring
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring ...
```

**Better solution (idempotent):**
```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
```

**Lesson learned:** Always create namespace before installing Helm chart with a custom namespace.

---

### Issue 10.2 — `/metrics` endpoint returned 404

**Error:**
```json
{"detail": "Not Found"}
```

**Root Cause:**
`Instrumentator().instrument(app).expose(app)` was applied to a different `app` instance than the one serving requests (duplicate app definition bug — see Issue 5.2).

**Solution:**
Fix duplicate app definition (see Issue 5.2).

---

### Issue 10.3 — Prometheus not scraping FastAPI metrics

**Problem:**
ServiceMonitor was created but Prometheus wasn't discovering the target.

**Root Cause:**
The Service didn't have a named port. ServiceMonitor references ports by name:
```yaml
# ServiceMonitor requires named port
endpoints:
  - port: http  # ← references port name
```

**Solution:**
Add port name to Service:
```yaml
ports:
  - name: http  # ← add this
    port: 80
    targetPort: 8000
```

**Lesson learned:** ServiceMonitor targets ports by name — always name your service ports.

---

## 11. Evidently AI Issues

### Issue 11.1 — Wrong import for DataQualityPreset

**Error:**
```
ImportError: cannot import name 'DataQualityPreset' from 'evidently.presets'
Did you mean: 'DataSummaryPreset'?
```

**Root Cause:**
Evidently 0.7.x renamed `DataQualityPreset` to `DataSummaryPreset`.

**Solution:**
```python
# Old (Evidently < 0.7)
from evidently.presets import DataDriftPreset, DataQualityPreset

# New (Evidently 0.7.x)
from evidently.presets import DataDriftPreset, DataSummaryPreset
```

**Lesson learned:** Always check the changelog when installing a specific library version.

---

### Issue 11.2 — `report.save_html()` AttributeError

**Error:**
```
AttributeError: 'Report' object has no attribute 'save_html'
```

**Root Cause:**
Evidently 0.7.x changed the API — `report.run()` returns a `Run` object, and `save_html()` is a method on the `Run` object, not the `Report` object.

**Solution:**
```python
# Old API
report = Report(metrics=[...])
report.run(reference_data=ref, current_data=cur)
report.save_html("report.html")  # ← WRONG

# New API (0.7.x)
report = Report(metrics=[...])
my_run = report.run(reference_data=ref, current_data=cur)  # returns Run object
my_run.save_html("report.html")  # ← CORRECT
```

**Lesson learned:** Always run a quick smoke test when upgrading library versions before writing full integration code.

---

### Issue 11.3 — Drift threshold check always returning False

**Problem:**
`check_drift_threshold()` always returned `False` even with obvious drift in the data.

**Root Cause:**
The function tried to parse the result using wrong key names. The actual Evidently 0.7.x result structure is:
```json
{
  "metrics": [{
    "metric_name": "DriftedColumnsCount(drift_share=0.5)",
    "value": {
      "count": 4.0,
      "share": 0.211
    }
  }]
}
```

But the code looked for `metric.get('result', {}).get('drift_share', 0)` which didn't exist.

**Debugging approach:**
```python
# Always inspect the raw result first
result = run.dict()
print(result['metrics'][0])  # see actual structure
```

**Solution:**
```python
def check_drift_threshold(run, threshold=0.5):
    result = run.dict()
    for metric in result.get('metrics', []):
        if 'DriftedColumnsCount' in metric.get('metric_name', ''):
            drift_share = metric.get('value', {}).get('share', 0)
            if drift_share > threshold:
                return True
    return False
```

**Lesson learned:** Always debug library output by printing the raw result structure before writing parsing logic.

---

## 🔑 Key Lessons Summary

| # | Lesson |
|---|--------|
| 1 | Always verify config files after running setup commands |
| 2 | Push `git` and `dvc` together — never let them get out of sync |
| 3 | Use `python3 -m pip` inside venv for upgrades |
| 4 | Always test on the target OS — Mac BSD tools ≠ Linux GNU tools |
| 5 | Never hardcode credentials — rotate immediately if exposed |
| 6 | Use `helm upgrade --install` — always idempotent |
| 7 | Never mix `kubectl apply` and `helm install` for same resources |
| 8 | Infrastructure scripts must handle "already exists" gracefully |
| 9 | Always check MLflow version changelog when upgrading |
| 10 | Separate requirements files: `requirements.txt` / `requirements-api.txt` / `requirements-dev.txt` |
| 11 | Mock dependencies (not results) when testing FastAPI with lifespan |
| 12 | Plan network topology before deploying — VPC peering requires upfront design |
| 13 | Always print raw library output before writing parsing logic |
| 14 | Named ports are required for Kubernetes ServiceMonitor |
| 15 | Delete VPC peering before deleting EKS cluster |

---

---
 
## Phase 9 — MLSecOps
 
### Issue: IRSA — OIDC ID changes on every cluster recreation
 
**Symptom:**
After recreating the EKS cluster in the morning, pods fail to access S3:
```
botocore.exceptions.NoCredentialsError: Unable to locate credentials
```
Even though IAM role and ServiceAccount annotation are correct.
 
**Root Cause:**
The EKS OIDC provider URL contains the cluster's unique OIDC ID (e.g., `oidc.eks.us-east-1.amazonaws.com/id/ABC123`). This ID changes every time the cluster is deleted and recreated. The IAM trust policy still has the old OIDC ID hardcoded — so the new cluster's tokens are rejected by AWS STS.
 
**Fix:**
Automate OIDC re-association and trust policy update in `setup-networking.sh`:
 
```bash
# Step 1: Associate new OIDC provider
eksctl utils associate-iam-oidc-provider \
  --cluster churn-mlops --approve --region us-east-1
 
# Step 2: Get new OIDC ID
OIDC_ID=$(aws eks describe-cluster \
  --name churn-mlops --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's/.*\///')
 
# Step 3: Update trust policy with new OIDC ID
aws iam update-assume-role-policy \
  --role-name churn-mlops-irsa-role \
  --policy-document "{...trust policy with $OIDC_ID...}"
```
 
This runs automatically every morning as part of the full cluster setup.
 
**Lesson:** OIDC ID is not static — it's per cluster instance. Never hardcode it. Always automate trust policy updates as part of the cluster creation workflow.
 
---
 
### Issue: Secrets Store CSI Driver — secret not mounting, pods stuck in Init
 
**Symptom:**
```
Warning  FailedMount  pod/churn-prediction-api-xxx
MountVolume.SetUp failed: rpc error: code = Unknown
desc = failed to mount secrets store objects for pod: error getting secret data
```
 
**Root Cause:**
The CSI Driver needed an IRSA token projected into it with audience `sts.amazonaws.com` to call AWS Secrets Manager. The CSIDriver object was missing the `tokenRequests` field — so it couldn't get credentials to fetch the secret.
 
**Fix:**
Patch the CSIDriver object after installation:
 
```bash
kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
```
 
**Lesson:** The Secrets Store CSI Driver Helm chart does not configure IRSA token projection by default. This patch is mandatory when using IRSA with the AWS provider. Add it to `setup-networking.sh` so it runs automatically.
 
---
 
### Issue: OPA Gatekeeper — Constraints applied before CRDs established
 
**Symptom:**
```
error: unable to recognize "constraints.yaml": 
no matches for kind "K8sNoRoot" in version "constraints.gatekeeper.sh/v1beta1"
```
 
**Root Cause:**
`setup-networking.sh` applied `constraint-templates.yaml` and `constraints.yaml` back-to-back too quickly. The ConstraintTemplate CRD registration is asynchronous — the custom `K8sNoRoot` kind doesn't exist yet when Constraints try to reference it.
 
**Fix:**
Add a `kubectl wait` between ConstraintTemplate and Constraint application:
 
```bash
kubectl apply -f k8s/gatekeeper/constraint-templates.yaml
 
# Wait for CRDs to be established before applying Constraints
kubectl wait --for=condition=established \
  --timeout=60s \
  crd/k8snorootcontainers.constraints.gatekeeper.sh \
  crd/k8srequirelimits.constraints.gatekeeper.sh \
  crd/k8snoprivileged.constraints.gatekeeper.sh
 
kubectl apply -f k8s/gatekeeper/constraints.yaml
```
 
**Lesson:** Kubernetes CRD registration is eventually consistent. Any resource that depends on a CRD must wait for `condition=established` before being applied.
 
---
 
### Issue: OPA Gatekeeper Rego — checking wrong level of pod spec
 
**Symptom:**
Gatekeeper constraint `K8sNoRoot` was installed and supposedly enforcing `runAsNonRoot`, but non-compliant deployments were not being blocked.
 
**Root Cause:**
The Rego policy was checking `input.review.object.spec.securityContext` (the pod-level spec directly) instead of `input.review.object.spec.template.spec.securityContext` (the pod template inside a Deployment). For Deployments, the pod spec is nested under `.spec.template.spec`, not at `.spec` directly.
 
**Fix:**
```rego
# WRONG — this is the Deployment spec, not the pod spec
pod_spec = input.review.object.spec {
  input.review.object.kind == "Deployment"
}
 
# CORRECT — traverse into .template.spec for Deployments
pod_spec = input.review.object.spec.template.spec {
  input.review.object.kind == "Deployment"
}
```
 
**Lesson:** Kubernetes resource structures differ between kinds. For Deployments/StatefulSets/DaemonSets the pod spec is at `.spec.template.spec`. Always test Gatekeeper policies with `--dry-run=server` on both compliant and non-compliant resources.
 
---
 
### Issue: VPC CNI Network Policies — ClusterIP service routing broken
 
**Symptom:**
After enabling VPC CNI network policy controller, the stream processor could not reach the prediction API via its Kubernetes ClusterIP service (`churn-prediction-api.churn-mlops.svc.cluster.local`). Connection timed out even though egress NetworkPolicy allowed port 8000.
 
**Root Cause:**
The VPC CNI network policy controller uses eBPF for packet interception. When eBPF intercepts traffic destined for a ClusterIP, service routing (kube-proxy or iptables NAT) doesn't complete in the expected order — causing connection failures for pods going through the eBPF enforcement path.
 
**Fix:**
Route stream processor traffic via the ALB (external load balancer) hostname instead of the internal ClusterIP:
 
```python
# BROKEN — ClusterIP fails with VPC CNI eBPF
API_URL = "http://churn-prediction-api.churn-mlops.svc.cluster.local:8000"
 
# WORKING — ALB hostname bypasses eBPF ClusterIP issue
API_URL = "http://<alb-hostname>.us-east-1.elb.amazonaws.com"
```
 
The ALB hostname is passed as an environment variable in the stream processor deployment.
 
**Lesson:** VPC CNI eBPF-based network policies can interfere with ClusterIP service routing. When troubleshooting network connectivity issues after enabling network policies, try the external LoadBalancer URL as a workaround. AWS is aware of this behavior.
 
---
 
## Phase 10 — Streaming Pipeline
 
### Issue: kafka-python incompatible with Kafka 4.x
 
**Symptom:**
```python
from kafka import KafkaConsumer
# Hangs indefinitely during broker metadata fetch
# OR: kafka.errors.NoBrokersAvailable
```
Stream processor pod starts but never consumes any messages.
 
**Root Cause:**
`kafka-python` (and its maintained fork `kafka-python-ng`) do not properly support Kafka 4.x's new KRaft protocol handshake. The client hangs during broker metadata fetch because it uses an incompatible API version negotiation.
 
**Fix:**
Replace `kafka-python` with `confluent-kafka`:
 
```dockerfile
# requirements-streaming.txt
confluent-kafka==2.3.0   # built on librdkafka, supports Kafka 4.x
redis==5.0.1
requests==2.32.3
```
 
```python
from confluent_kafka import Consumer, Producer
 
consumer = Consumer({
    'bootstrap.servers': 'churn-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092',
    'group.id': 'churn-stream-processor',
    'auto.offset.reset': 'latest'
})
```
 
**Lesson:** `confluent-kafka` is the production-grade Kafka client. It's built on `librdkafka` (C library), officially maintained by Confluent, and supports all Kafka versions including 4.x. Use it for any new Kafka project.
 
---
 
### Issue: Kafka cross-namespace DNS resolution — advertised hostname wrong
 
**Symptom:**
Stream processor in `churn-mlops` namespace cannot connect to Kafka broker in `kafka` namespace:
```
%3|1234567890.123|FAIL|churn-kafka-kafka-0.churn-kafka-kafka-brokers.kafka:9092/0|
Connection refused (after 0ms in state CONNECT)
```
 
**Root Cause:**
The Kafka broker's `advertisedHost` was set to `churn-kafka-kafka-0.churn-kafka-kafka-brokers.kafka` — missing the `.svc.cluster.local` suffix. Within the same namespace this resolves fine via DNS search domains, but from a different namespace the full FQDN is required.
 
**Fix:**
In `k8s/kafka/kafka-cluster.yaml`, explicitly set the advertised hostname to include `.svc.cluster.local`:
 
```yaml
spec:
  kafka:
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    configuration:
      brokerRackInitImage: quay.io/strimzi/kafka:latest-kafka-4.1.0
  # Strimzi auto-sets FQDN when using KRaft — verify with:
  # kubectl get kafka -n kafka -o yaml | grep advertisedHost
```
 
**Lesson:** Always use FQDNs (`service.namespace.svc.cluster.local`) for cross-namespace service communication. Short names only resolve within the same namespace due to DNS search domain scoping.
 
---
 
## Phase 11 — Feature Store
 
### Issue: Feast Redis keys are binary — can't query with plain redis-cli
 
**Symptom:**
After running `feast materialize-incremental`, tried to verify with:
```bash
redis-cli KEYS "churn*"
# (empty array)
```
Expected keys like `churn:customer:cust_001` but nothing found.
 
**Root Cause:**
Feast uses a binary serialization format (Protocol Buffers) for Redis keys, not plain text. The actual key looks like `\x02\x00\x00\x00customer_id\x02\x00\x00\x00\t\x00\x00\x00cust_3378churn_feature_repo` — not the human-readable string you'd expect.
 
**Fix:**
To verify materialization worked, use Python with `decode_responses=False`:
 
```python
import redis
r = redis.Redis(host='localhost', port=6379)  # decode_responses=False is default
all_keys = r.keys('*')
print(f'Total keys in Redis: {len(all_keys)}')
# Output: Total keys in Redis: 5639
print('Sample keys:', all_keys[:3])
# Output: [b'\x02\x00\x00\x00customer_id\x02\x00\x00\x00...', ...]
```
 
Do NOT use `decode_responses=True` when inspecting Feast keys — it throws `UnicodeDecodeError` because the binary keys can't be decoded as UTF-8.
 
**Lesson:** Feast's Redis online store uses Protobuf binary keys. Never query it with plain `redis-cli KEYS "pattern*"` — you won't find anything. Always verify via Python redis client with `decode_responses=False`, or use `r.keys('*')` and check the count.
 
---
 
## Phase 12 — Airflow
 
### Issue: EKS StorageClass `WaitForFirstConsumer` causes PostgreSQL pod deadlock
 
**Symptom:**
Airflow PostgreSQL pod stays in `Pending` state indefinitely:
```
Warning  FailedScheduling  pod/airflow-postgresql-0
0/2 nodes are available: 2 node(s) had volume node affinity conflict.
```
PVC is `Pending`, pod is `Pending` — neither can proceed.
 
**Root Cause:**
The default EBS StorageClass uses `volumeBindingMode: WaitForFirstConsumer`. This means the EBS volume is not created until a pod is scheduled to a node. But the pod can't be scheduled until a volume is available in the same AZ. This creates a circular deadlock: volume waits for pod → pod waits for volume.
 
**Fix:**
Create a custom StorageClass with `Immediate` binding:
 
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate      # Volume created immediately, before pod scheduling
parameters:
  type: gp2
```
 
With `Immediate`, the EBS volume is provisioned first in a specific AZ, then the pod is scheduled to a node in that AZ.
 
**Lesson:** Always use `volumeBindingMode: Immediate` for single-node or small dev clusters. `WaitForFirstConsumer` is designed for multi-zone production clusters where you want the volume to follow the pod — not useful in a dev setup.
 
---
 
### Issue: EBS CSI Driver not installed — PVC provisioning silently fails
 
**Symptom:**
PVC created but stays in `Pending` state with no clear error:
```bash
kubectl get pvc -n airflow
# NAME                    STATUS    VOLUME   CAPACITY
# data-airflow-postgresql-0   Pending
```
 
**Root Cause:**
The EKS cluster didn't have the EBS CSI Driver addon installed. Without it, the `ebs.csi.aws.com` provisioner doesn't exist, so any PVC using it silently hangs as `Pending`.
 
**Fix:**
```bash
aws eks create-addon \
  --cluster-name churn-mlops \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1
 
# Wait for addon to become active
aws eks wait addon-active \
  --cluster-name churn-mlops \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1
 
# Also attach EBS policy to node IAM role
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`)].RoleName' \
  --output text)
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```
 
**Lesson:** EKS does not include the EBS CSI Driver by default. It must be installed as an addon. PVCs using `ebs.csi.aws.com` will silently hang as `Pending` without it. Always install this addon before deploying any stateful workloads on EKS.
 
---
 
### Issue: Nodes full — Airflow pods stuck in Pending (Insufficient CPU/memory)
 
**Symptom:**
```
Warning  FailedScheduling  pod/airflow-api-server-xxx
0/2 nodes are available: 2 Insufficient cpu, 2 Insufficient memory.
```
Airflow has 5+ components (scheduler, api-server, dag-processor, triggerer, postgresql) — all compete for resources on 2 t3.medium nodes already running the prediction API and stream processor.
 
**Root Cause:**
2x t3.medium nodes (2 vCPU, 4GB each) = 4 vCPU, 8GB total. With 33+ pods (system pods + API + stream processor + Kafka + Redis + Prometheus + Grafana), there simply wasn't enough CPU/memory headroom for Airflow components.
 
**Fix:**
Scale the nodegroup to 3 nodes:
```bash
aws eks update-nodegroup-config \
  --cluster-name churn-mlops \
  --nodegroup-name standard-workers \
  --scaling-config minSize=3,maxSize=3,desiredSize=3 \
  --region us-east-1
 
# Wait for nodes to join
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```
 
Updated `cluster.yaml` to use 3 nodes by default:
```yaml
managedNodeGroups:
  - name: standard-workers
    instanceType: t3.medium
    desiredCapacity: 3
    minSize: 3
    maxSize: 3
```
 
**Lesson:** Always estimate resource requirements before deploying a full stack. A 2-node t3.medium cluster is too small for: API + monitoring + Kafka + Redis + Airflow simultaneously. Use 3 nodes minimum.
 
---
 
### Issue: Airflow git-sync — DAG files present but not parsed
 
**Symptom:**
```bash
kubectl exec -n airflow <dag-processor-pod> -c dag-processor \
  -- airflow dags list
# (empty — no DAGs listed)
```
 
But the files ARE there:
```bash
kubectl exec -n airflow <dag-processor-pod> -c dag-processor \
  -- ls /opt/airflow/dags/repo/dags/
# churn_retraining.py
# feature_materialization.py
```
 
**Root Cause:**
The dag-processor's configured `dags_folder` was `/opt/airflow/dags/repo/dags` but the git-sync symlink `repo` was pointing to the wrong worktree path because the Helm `--set dags.gitSync.dest=repo` parameter doesn't exist in this chart version — it caused a schema validation error.
 
**Investigation:**
```bash
# Check what dags_folder the processor actually uses
kubectl exec -n airflow <dag-processor-pod> -c dag-processor \
  -- airflow config get-value core dags_folder
# /opt/airflow/dags/repo/dags  ← correct path
 
# Check if symlink is correct
kubectl exec -n airflow <dag-processor-pod> -c dag-processor \
  -- ls -la /opt/airflow/dags/
# repo -> .worktrees/6709d38a155c7680be2543bc14b130fe74aec30c  ← symlink exists
 
# Check files under symlink
kubectl exec -n airflow <dag-processor-pod> -c dag-processor \
  -- ls /opt/airflow/dags/repo/dags/
# churn_retraining.py  feature_materialization.py  ← files present
```
 
**Fix:**
The issue was a timing problem — the dag-processor hadn't yet parsed the new files. Triggering a DAG via the scheduler CLI caused it to parse:
```bash
kubectl exec -n airflow <scheduler-pod> -c scheduler \
  -- airflow dags list
# churn_retraining        | /opt/airflow/dags/repo/dags/churn_retraining.py        | True
# feature_materialization | /opt/airflow/dags/repo/dags/feature_materialization.py | True
```
 
The `dest` parameter doesn't exist in newer chart versions — remove it from `helm upgrade` command.
 
**Lesson:** In Airflow 3.x with KubernetesExecutor, the dag-processor is a separate component from the scheduler. Both need time to sync after a git-sync pull. Wait ~30 seconds after git-sync before expecting DAGs to appear.
 
---
 
### Issue: Airflow dags list CLI syntax changed in Airflow 3.x
 
**Symptom:**
```bash
airflow dags list-runs -d feature_materialization
# error: unrecognized arguments: -d
 
airflow dags list-runs --dag-id feature_materialization
# error: unrecognized arguments: --dag-id
```
 
**Root Cause:**
Airflow 3.x significantly restructured the CLI. Many subcommands were removed, renamed, or had their flags changed. `dags clear`, `dags list-runs -d`, and several other common commands no longer exist.
 
**Available commands in Airflow 3.x:**
```bash
airflow dags list              # list all DAGs
airflow dags trigger <dag_id>  # trigger a run
airflow dags unpause <dag_id>  # unpause a DAG
airflow dags pause <dag_id>    # pause a DAG
airflow dags list-runs         # list runs (no --dag-id flag)
```
 
**Fix:**
Use the Airflow UI for detailed run inspection, or the API. For triggering from CLI:
```bash
kubectl exec -n airflow \
  $(kubectl get pod -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}') \
  -c scheduler \
  -- airflow dags trigger feature_materialization
```
 
**Lesson:** Airflow 3.x broke backward compatibility with many CLI commands. Always check the CLI help (`airflow --help`, `airflow dags --help`) rather than assuming older commands work.
 
---
 
### Issue: KubernetesPodOperator — airflow-worker RBAC missing, pods not spawning
 
**Symptom:**
DAG shows `Running` in UI, but no pod appears in `churn-mlops` namespace. Pod logs show:
```
ApiException: (403)
pods is forbidden: User "system:serviceaccount:airflow:airflow-worker" 
cannot list resource "pods" in API group "" in the namespace "churn-mlops"
```
 
**Root Cause:**
KubernetesPodOperator needs to create, list, watch, and delete pods in the target namespace (`churn-mlops`). The `airflow-worker` ServiceAccount has no RBAC permissions outside the `airflow` namespace by default.
 
Additionally, the initial RBAC fix targeted `airflow-scheduler` but the actual executor SA is `airflow-worker` in Airflow 3.x.
 
**Fix:**
```bash
kubectl apply -f - << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: airflow-pod-launcher
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: airflow-pod-launcher-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: airflow-pod-launcher
subjects:
  - kind: ServiceAccount
    name: airflow-scheduler    # scheduler
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-worker       # actual task executor in Airflow 3.x
    namespace: airflow
  - kind: ServiceAccount
    name: airflow-triggerer    # for deferred tasks
    namespace: airflow
EOF
```
 
**Lesson:** In Airflow 3.x, the task execution SA is `airflow-worker`, not `airflow-scheduler`. Always bind RBAC to all three: scheduler, worker, triggerer. After fixing RBAC, restart the scheduler to pick up new permissions: `kubectl rollout restart deployment airflow-scheduler -n airflow`.
 
---
 
### Issue: KubernetesPodOperator — task shows Failed but pod actually Succeeded
 
**Symptom:**
DAG task shows `Failed` (red) in Airflow UI. Task logs show:
```
Could not read served logs: HTTPConnectionPool(host='feature-materialization-...', port=8793):
Max retries exceeded (Caused by NameResolutionError)
```
 
But the pod ran successfully:
```bash
kubectl logs -n airflow feature-materialization-materialize-features-xxx
# Starting feature materialization...
# Redis connected!
# Loaded 5634 records from S3
# Feature materialization complete!
```
 
**Root Cause:**
After the task pod completes, Airflow tries to fetch logs from the pod's log endpoint (`pod-hostname:8793`). If the pod was deleted (`is_delete_operator_pod=True`) before log fetching completes, the hostname no longer resolves — throwing the log fetch error. In Airflow 3.x with KubernetesExecutor, this log fetch failure is treated as a task failure.
 
**Fix:**
Set `is_delete_operator_pod=False` in the KubernetesPodOperator:
```python
materialize_features = KubernetesPodOperator(
    ...
    is_delete_operator_pod=False,  # Keep pod alive for log reading
    get_logs=True,
)
```
 
Note: Even with this setting, Airflow 3.x KubernetesExecutor may still delete pods — this is a known limitation. The actual task execution is correct; the failure is only in log retrieval.
 
**Verification:** Check XCom tab in Airflow UI — if `pod_name` and `pod_namespace` are populated, the task ran and the pod was created successfully. Check Redis key count to verify materialization actually worked.
 
**Lesson:** In Airflow 3.x + KubernetesExecutor, pod lifecycle is controlled by the executor — `is_delete_operator_pod=False` may not always be respected. Always verify actual task success by checking the side effects (Redis keys, S3 files, MLflow runs) rather than relying solely on Airflow UI status.
 
---
 
### Issue: churn-materialize image — NumPy version conflict crashes container
 
**Symptom:**
```
A module that was compiled using NumPy 1.x cannot be run in NumPy 2.4.4
AttributeError: _ARRAY_API not found
 
ImportError: Unable to find a usable engine; tried using: 'pyarrow', 'fastparquet'.
```
The materialize container crashes immediately on startup.
 
**Root Cause:**
The `Dockerfile.materialize` installed `pyarrow==14.0.1` which was compiled against NumPy 1.x. But `python:3.12-slim` base image pulls NumPy 2.4.4 as a transitive dependency. NumPy 2.x broke the ABI (Application Binary Interface) — C extension modules compiled against 1.x crash at import time.
 
**Fix:**
Pin NumPy to 1.x explicitly, and use a pyarrow version that's compatible with it:
 
```dockerfile
RUN pip install --no-cache-dir \
    numpy==1.26.4 \       # Must install FIRST and PINNED — controls ABI
    boto3==1.37.1 \
    pandas==2.2.3 \
    redis==5.0.1 \
    pyarrow==15.0.2       # pyarrow 15.x works with numpy 1.26.x
```
 
Order matters — install numpy before pyarrow so pip resolves the ABI correctly.
 
**Verification:**
```bash
# Test the image before pushing
kubectl run test-mat -n churn-mlops \
  --image=011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-materialize:latest \
  --restart=Never \
  --env="AWS_DEFAULT_REGION=us-east-1" \
  --env="REDIS_HOST=redis-master.redis.svc.cluster.local"
kubectl logs -n churn-mlops test-mat
# Starting feature materialization...
# Redis connected!
# Loaded 5634 records — Feature materialization complete!
```
 
**Lesson:** pyarrow and NumPy have a tight ABI coupling. Always pin `numpy==1.26.4` when using pyarrow in any image. NumPy 2.x will break any C extension compiled against 1.x. This applies to: pyarrow, scikit-learn (older versions), scipy, and many other scientific Python libraries.
 
---
 
### Issue: Stream processor image missing boto3 — wrong image used for materialization
 
**Symptom:**
```
ModuleNotFoundError: No module named 'boto3'
```
Pod crashes immediately.
 
**Root Cause:**
The initial DAG used `churn-stream-processor` image (which has `confluent-kafka`, `redis`, `requests`) instead of a dedicated materialization image. The stream processor image was never meant to access S3 — it doesn't have `boto3` or `pandas`.
 
Conversely, `churn-prediction-api` image has `boto3` and `pandas` but no `redis`.
 
Neither existing image had all required dependencies (`boto3` + `pandas` + `redis` + `pyarrow`).
 
**Fix:**
Build a dedicated `churn-materialize` image with exactly the dependencies needed:
 
```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get upgrade -y && apt-get clean
RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    boto3==1.37.1 \
    pandas==2.2.3 \
    redis==5.0.1 \
    pyarrow==15.0.2
COPY scripts/materialize_features.py .
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser
CMD ["python", "materialize_features.py"]
```
 
**Lesson:** Each Airflow KubernetesPodOperator task should use an image purpose-built for that task. Don't reuse images across different task types — it leads to missing dependency issues. The overhead of maintaining an extra image is worth the clarity and reliability.
 
---
 
## 🧠 General Lessons Learned
 
| Area | Lesson |
|------|--------|
| **OIDC/IRSA** | Never hardcode OIDC ID. Automate trust policy updates per cluster recreation. |
| **EBS CSI** | Always install EBS CSI driver addon before deploying stateful workloads on EKS. |
| **StorageClass** | Use `volumeBindingMode: Immediate` for dev clusters. `WaitForFirstConsumer` causes deadlocks. |
| **Kafka client** | Use `confluent-kafka`, not `kafka-python`, for Kafka 4.x. |
| **Cross-namespace DNS** | Always use FQDNs (`svc.cluster.local`) for cross-namespace service calls. |
| **NumPy ABI** | Pin `numpy==1.26.4` whenever using pyarrow. NumPy 2.x breaks ABI. |
| **Airflow 3.x CLI** | CLI changed significantly. Verify commands with `airflow --help`. |
| **Airflow RBAC** | Bind to `airflow-worker` (not scheduler) for task pod creation permissions. |
| **HPA + Helm** | Use `{{- if not .Values.autoscaling.enabled }} replicas: N {{- end }}` to avoid conflict. |
| **Feast Redis** | Feast uses binary Protobuf keys. Use Python `decode_responses=False` to inspect. |
| **Gatekeeper CRDs** | Always `kubectl wait --for=condition=established` before applying Constraints. |
| **VPC CNI eBPF** | ClusterIP routing may break with eBPF network policies. Use ALB URL as workaround. |
| **Node capacity** | 2x t3.medium insufficient for full stack. Use 3 nodes minimum. |
| **Docker images** | Build purpose-specific images per task type. Don't reuse across different workloads. |

---

*This document was built iteratively throughout the project — every error was a learning opportunity.*
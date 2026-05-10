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
 
## Phase 13 — GitOps with ArgoCD
 
### Issue: ArgoCD application-controller stuck in Pending — too many pods
 
**Symptom:**
```
Warning  FailedScheduling  argocd-application-controller-0
0/3 nodes are available: 3 Too many pods.
```
 
**Root cause:**
EKS t3.medium nodes have a hard limit of 17 pods per node (ENI-based IP allocation, not CPU/memory). With 53+ pods across the full stack (Kafka, Redis, Airflow, Prometheus, Grafana, kube-system), there was no space for the ArgoCD application controller.
 
**Fix:**
Install Cluster Autoscaler first, then let it add a 4th node automatically when it detects the pending pod:
```bash
kubectl apply -f k8s/cluster-autoscaler.yaml
kubectl -n kube-system annotate deployment.apps/cluster-autoscaler \
  cluster-autoscaler.kubernetes.io/safe-to-evict="false"
kubectl -n kube-system set env deployment/cluster-autoscaler CLUSTER_NAME=churn-mlops
 
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $ASG_NAME \
  --min-size 3 --max-size 6 --region us-east-1
```
 
**Lesson:** Always check `kubectl describe nodes | grep -E "Name:|Non-terminated Pods:"` before installing new components. EKS pod limits are ENI-based, not resource-based — a node with 1% CPU can still refuse new pods.
 
---
 
### Issue: Cluster Autoscaler AccessDenied — missing IAM policy
 
**Symptom:**
```
AccessDenied: User: .../NodeInstanceRole/... is not authorized to perform:
autoscaling:DescribeAutoScalingGroups
```
 
**Root cause:**
The `AutoScalingFullAccess` policy was not attached to the EKS node role before the Cluster Autoscaler pod started. The pod cached the failed credential check and kept failing even after the policy was attached.
 
**Fix:**
```bash
NODE_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `NodeInstanceRole`) && contains(RoleName, `churn-mlops`)].RoleName' \
  --output text)
 
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
 
kubectl rollout restart deployment/cluster-autoscaler -n kube-system
```
 
**Lesson:** Always attach IAM policies before deploying the workload that needs them. A pod restart is required after policy attachment because the credential cache is not refreshed automatically.
 
---
 
### Issue: ArgoCD bootstrap — `stable` branch URL returns 404
 
**Symptom:**
```
error: unable to read URL "https://raw.githubusercontent.com/argoproj/argo-cd/stable/install.yaml"
server reported 404 Not Found
```
 
**Root cause:**
The ArgoCD `stable` branch was renamed. The raw GitHub URL using branch name `stable` no longer resolves.
 
**Fix:**
Use a pinned release tag instead of the branch name:
```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.9/manifests/install.yaml
```
 
For reproducibility, store as a Kustomization reference in the repo:
```bash
cat > k8s/argocd/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.9/manifests/install.yaml
EOF
kubectl apply -k k8s/argocd/ -n argocd
```
 
**Lesson:** Never reference `stable` or `latest` branch names in raw GitHub URLs for infrastructure manifests. Always pin to a specific release tag.
 
---
 
### Issue: Prometheus — duplicate stack created by ArgoCD (monitoring-* and prometheus-* pods)
 
**Symptom:**
```
NAME                                                     READY   STATUS
alertmanager-monitoring-kube-prometheus-alertmanager-0   0/2     Terminating
alertmanager-prometheus-kube-prometheus-alertmanager-0   2/2     Running
monitoring-grafana-xxx                                   3/3     Running
prometheus-grafana-xxx                                   3/3     Running
```
 
**Root cause:**
ArgoCD deployed the `kube-prometheus-stack` Helm chart with release name `monitoring` (ArgoCD Application name) instead of `prometheus` (existing manual install). Two stacks ran simultaneously, fighting for resources.
 
**Fix:**
Explicitly set `releaseName: prometheus` in the ArgoCD Application to match the existing Helm release:
```yaml
source:
  helm:
    releaseName: prometheus    # must match existing helm release name
```
 
Then delete the orphaned `monitoring-*` resources and let ArgoCD adopt the existing `prometheus` release:
```bash
kubectl delete deployment monitoring-grafana monitoring-kube-prometheus-operator \
  monitoring-kube-state-metrics -n monitoring 2>/dev/null || true
kubectl delete daemonset monitoring-prometheus-node-exporter -n monitoring 2>/dev/null || true
```
 
**Lesson:** When ArgoCD adopts an existing Helm release, `releaseName` must exactly match the release name used during the original `helm install`. Mismatched names cause duplicate deployments.
 
---
 
### Issue: Prometheus — operator stuck in ContainerCreating, TLS secret missing
 
**Symptom:**
```
Warning  FailedMount  MountVolume.SetUp failed for volume "tls-secret":
secret "prometheus-kube-prometheus-admission" not found
```
 
**Root cause:**
`kube-prometheus-stack` uses a Helm pre-install hook job to generate a self-signed TLS certificate for its admission webhook. ArgoCD does not execute Helm hooks the same way `helm install` does — the job never ran, so the TLS secret was never created.
 
**Fix:**
Disable admission webhooks entirely in the ArgoCD Application values (not needed for dev/portfolio):
```yaml
prometheusOperator:
  admissionWebhooks:
    enabled: false
  tls:
    enabled: false
```
 
**Lesson:** ArgoCD skips Helm pre-install/post-install hooks by default. Any chart that depends on hook-generated resources (TLS secrets, schema migrations, CRD initialization) will fail silently. The fix is to either disable the hook-dependent feature or use ArgoCD's `resource.hooks` configuration.
 
---
 
### Issue: Namespace stuck in Terminating — force clear finalizers
 
**Symptom:**
```
kubectl get ns monitoring
NAME         STATUS        AGE
monitoring   Terminating   2d3h
```
 
**Root cause:**
Kubernetes finalizers on resources inside the namespace prevent deletion. The finalizer `networking.k8s.aws/resources` (VPC CNI) was holding a NetworkPolicy that couldn't be deleted because the namespace was already terminating — a circular dependency.
 
**Fix:**
Force clear namespace finalizers via the raw Kubernetes API:
```bash
kubectl get namespace monitoring -o json | \
  python3 -c "
import json, sys
ns = json.load(sys.stdin)
ns['spec']['finalizers'] = []
print(json.dumps(ns))
" | kubectl replace --raw /api/v1/namespaces/monitoring/finalize -f -
```
 
For individual stuck resources (e.g., NetworkPolicy):
```bash
# Recreate the namespace first to make the resource addressable
kubectl create namespace redis
 
# Then clear the finalizer
kubectl patch networkpolicy redis -n redis \
  --type merge -p '{"metadata":{"finalizers":[]}}'
 
kubectl delete networkpolicy redis -n redis --force --grace-period=0
```
 
**Lesson:** `networking.k8s.aws/resources` is the VPC CNI finalizer. It holds NetworkPolicy objects until the CNI cleans up eBPF rules. When the namespace is gone but the resource persists in etcd, recreating the namespace makes it addressable again so you can clear the finalizer.
 
---
 
### Issue: ArgoCD `ServerSideApply` — ports missing `protocol` field
 
**Symptom:**
```
ComparisonError: error building typed value from config resource:
.spec.template.spec.containers[name="churn-prediction-api"].ports:
element 0: associative list with keys has an element that omits key field "protocol"
```
 
**Root cause:**
`ServerSideApply=true` in ArgoCD uses strict schema validation. Kubernetes associative lists (like `ports`) require all key fields to be present. The `protocol` field is technically optional in regular apply but required by ServerSideApply's typed validation.
 
**Fix:**
Add `protocol: TCP` to every port definition in Helm templates:
```yaml
ports:
  - name: http
    containerPort: 8000
    protocol: TCP    # required for ServerSideApply
```
 
**Lesson:** `ServerSideApply=true` is stricter than regular `kubectl apply`. Any field that is part of a merge key in a Kubernetes schema must be explicitly set. Always add `protocol` to port definitions when using ServerSideApply.
 
---
 
### Issue: Bitnami Redis — OCI chart URL fails in ArgoCD
 
**Symptom:**
```
error fetching chart: failed to fetch chart:
helm pull --version 25.4.1 --repo https://charts.bitnami.com/bitnami redis
failed exit status 1: Error: invalid_reference: invalid tag
```
 
**Root cause:**
Bitnami migrated their Helm charts from the traditional HTTP Helm repo (`https://charts.bitnami.com/bitnami`) to OCI registry format. Old chart versions were removed from the HTTP repo. ArgoCD's `helm pull` cannot fetch charts that no longer exist at the HTTP endpoint.
 
**Fix:**
Switch to OCI URL format in the ArgoCD Application:
```yaml
source:
  repoURL: oci://registry-1.docker.io/bitnamicharts/redis
  chart: redis
  targetRevision: "25.5.0"
```
 
Or avoid the Bitnami dependency entirely by using a raw Kubernetes manifest:
```yaml
# k8s/redis/redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-master
  namespace: redis
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: redis
          image: redis:7.2
          ports:
            - containerPort: 6379
```
 
**Lesson:** Bitnami's migration to OCI broke many existing ArgoCD integrations. For simple stateless components like Redis in a dev environment, a raw manifest avoids all chart versioning complexity and is easier to maintain.
 
---
 
## Phase 14 — Progressive Delivery
 
### Issue: HPA targets Deployment but Rollout replaced it
 
**Symptom:**
```
the HPA controller was unable to get the target's current scale:
deployments.apps "churn-prediction-api" not found
```
ArgoCD shows `Degraded` health status.
 
**Root cause:**
When the Deployment was replaced with an Argo Rollouts `Rollout` object, the HPA still pointed at `apps/v1 Deployment`. The Deployment no longer existed so HPA couldn't find its scale target.
 
**Fix:**
Update HPA `scaleTargetRef` to target the Rollout:
```yaml
spec:
  scaleTargetRef:
    apiVersion: argoproj.io/v1alpha1
    kind: Rollout                        # was: apps/v1 Deployment
    name: churn-prediction-api
```
 
**Lesson:** When migrating from Deployment to Rollout, update all resources that reference the Deployment: HPA, PodDisruptionBudget, and any monitoring rules that use `kind: Deployment` selectors.
 
---
 
### Issue: VirtualService weights not updating — missing named route
 
**Symptom:**
VirtualService stays at `stable: 100, canary: 0` throughout the entire canary even though `ActualWeight` updates correctly in `kubectl argo rollouts get rollout`.
 
**Root cause:**
Argo Rollouts needs the VirtualService HTTP route to have a `name` field so it can find the correct route to update. Without a named route, Argo Rollouts cannot determine which HTTP route in the VirtualService to patch weights into.
 
**Fix:**
Add `name: primary` to the VirtualService HTTP route and reference it in the Rollout:
 
```yaml
# VirtualService
spec:
  http:
    - name: primary      # required — Argo Rollouts uses this to find the route
      route:
        - destination:
            host: churn-prediction-api
            subset: stable
          weight: 100
        - destination:
            host: churn-prediction-api
            subset: canary
          weight: 0
```
 
```yaml
# Rollout trafficRouting
trafficRouting:
  istio:
    virtualService:
      name: churn-prediction-api-vsvc
      routes:
        - primary           # must match the named route in VirtualService
```
 
**Lesson:** Argo Rollouts + Istio requires the VirtualService HTTP route to be named. Without this, Argo Rollouts reconciles traffic routing silently but never updates the VirtualService weights.
 
---
 
### Issue: ArgoCD perpetual OutOfSync on Istio VirtualService
 
**Symptom:**
`churn-prediction-api` Application shows `OutOfSync` continuously even after successful syncs. Argo Rollouts updates VirtualService weights during canary which always differ from Git state.
 
**Root cause:**
Argo Rollouts dynamically patches the VirtualService `spec.http` routes during canary to update traffic weights. ArgoCD compares live state against Git and sees the weights have changed — triggering endless reconciliation loops.
 
**Fix:**
Add `ignoreDifferences` for the VirtualService HTTP spec in the ArgoCD Application:
```yaml
ignoreDifferences:
  - group: networking.istio.io
    kind: VirtualService
    name: churn-prediction-api-vsvc
    jsonPointers:
      - /spec/http
  - group: networking.istio.io
    kind: DestinationRule
    name: churn-prediction-api-destrule
    jsonPointers:
      - /spec/subsets
```
 
**Lesson:** Any resource that is dynamically updated at runtime by another controller (HPA replicas, Argo Rollouts VirtualService weights, cert-manager certificates) must have those fields added to `ignoreDifferences`. Otherwise ArgoCD will perpetually show `OutOfSync`.
 
---
 
### Issue: Argo Rollouts install URL returns 0 bytes
 
**Symptom:**
```bash
curl -o k8s/argo-rollouts/install.yaml \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
# Total: 0 bytes
```
 
**Root cause:**
GitHub releases redirect to a CDN URL. `curl` without the `-L` flag doesn't follow redirects, resulting in 0 bytes downloaded.
 
**Fix:**
Always use `-L` to follow redirects:
```bash
curl -L -o k8s/argo-rollouts/install.yaml \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```
 
Or use Kustomize reference (preferred — doesn't store large files in repo):
```yaml
# k8s/argo-rollouts/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```
 
```bash
kubectl apply -k k8s/argo-rollouts/ -n argo-rollouts
```
 
**Lesson:** `-L` is mandatory for GitHub release downloads. Use Kustomize references in the repo instead of storing large install manifests — keeps the repo clean and pins the version declaratively.
 
---
 
## Phase 15 — Data Quality
 
### Issue: Great Expectations API changed between v0.x and v1.x
 
**Symptom:**
```
AttributeError: 'EphemeralDataContext' object has no attribute 'run_validation_definition'
AttributeError: module 'great_expectations.expectations' has no attribute 'ExpectTableRowCountToBeGreaterThan'
```
 
**Root cause:**
GE 1.x completely rewrote the API. `run_validation_definition` replaced the old checkpoint-based approach. `ExpectTableRowCountToBeGreaterThan` was renamed to `ExpectTableRowCountToBeBetween` with `max_value=None`.
 
**Fix (GE 1.4.4 API):**
```python
# Create validation definition
validation_definition = context.validation_definitions.add(
    gx.ValidationDefinition(
        name="churn_validation",
        data=batch_definition,
        suite=suite
    )
)
 
# Run it
validation_result = validation_definition.run(
    batch_parameters={"dataframe": df}
)
 
# Row count (renamed)
gx.expectations.ExpectTableRowCountToBeBetween(min_value=1000, max_value=None)
```
 
**Lesson:** Always check the GE changelog when upgrading. GE 1.x is not backward compatible with 0.x. Pin to a specific version (`great-expectations==1.4.4`) and test before upgrading.
 
---
 
### Issue: Great Expectations + pandas version conflict with SHAP
 
**Symptom:**
```
ERROR: pip's dependency resolver conflict:
great-expectations 1.4.4 requires pandas<2.2
shap 0.46.0 installs pandas 3.0.2
```
 
**Root cause:**
`shap==0.46.0` pulls in `scikit-image` which upgrades numpy to 2.4.4 and pandas to 3.0.2. GE 1.4.4 has a strict `pandas<2.2` constraint. MLflow also requires `pandas<3`.
 
**Fix:**
Pin the compatible versions explicitly after installing shap:
```bash
pip install shap==0.46.0 lime==0.2.0.1
pip uninstall tifffile scikit-image -y   # remove scikit-image (pulls new numpy)
pip install numpy==1.26.4 pandas==2.1.4  # 2.1.4 satisfies GE (<2.2) and mlflow (<3)
```
 
**Verify compatibility:**
```bash
python -c "import numpy, pandas, shap, lime, mlflow, great_expectations; \
  print('numpy:', numpy.__version__, '| pandas:', pandas.__version__)"
# Expected: numpy: 1.26.4 | pandas: 2.1.4
```
 
**Lesson:** In ML projects, dependency conflicts are inevitable as the stack grows. Always maintain a pinned `requirements.txt` with every version locked. The compatible set for this stack is: `numpy==1.26.4`, `pandas==2.1.4`, `pyarrow==15.0.2`, `shap==0.46.0`, `great-expectations==1.4.4`, `mlflow-skinny==2.22.0`.
 
---
 
## Phase 16 — Explainability
 
### Issue: SHAP values shape changed in v0.46.0
 
**Symptom:**
```
ValueError: The truth value of an array with more than one element is ambiguous
TypeError: only length-1 arrays can be converted to Python scalars
ValueError: Per-column arrays must each be 1-dimensional
```
 
**Root cause:**
SHAP 0.46.0 changed the output format for `TreeExplainer.shap_values()` on multi-class models. Previously returned `[class_0_array, class_1_array]` (list of 2D arrays). Now returns a single 3D array of shape `(n_samples, n_features, n_classes)`.
 
**Debug:**
```python
shap_values = explainer.shap_values(X)
print(type(shap_values))       # <class 'numpy.ndarray'>
print(shap_values.shape)       # (500, 19, 2) — samples × features × classes
```
 
**Fix — extract class 1 (churn) values:**
```python
# For single prediction
shap_vals = np.array(shap_values)[:, :, 1].flatten()
 
# For batch (summary plot)
shap_vals = np.array(shap_values)[:, :, 1]   # shape: (n, 19)
 
# For global importance
mean_shap = np.abs(np.array(shap_values)[:, :, 1]).mean(axis=0)  # shape: (19,)
```
 
**Lesson:** SHAP output format is version-dependent. Always check `shap_values.shape` before processing. The 3D format `(samples, features, classes)` is now standard in SHAP 0.46.0+ for multi-output models.
 
---
 
### Issue: SHAP summary_plot fails with feature_names as list
 
**Symptom:**
```
TypeError: only integer scalar arrays can be converted to a scalar index
feature_names=feature_names[sort_inds]
```
 
**Root cause:**
`shap.summary_plot()` with a numpy array + separate `feature_names` list tries to index the list with a numpy array of indices. Numpy fancy indexing on a Python list raises this error.
 
**Fix:**
Pass a pandas DataFrame instead of numpy array — SHAP reads column names directly:
```python
shap.summary_plot(
    shap_vals,
    pd.DataFrame(X_data, columns=FEATURE_COLUMNS),  # DataFrame, not numpy array
    show=False,
    plot_type="beeswarm"
)
```
 
**Lesson:** When passing data to SHAP plotting functions, prefer pandas DataFrames over numpy arrays. DataFrames carry column names natively, avoiding the separate `feature_names` parameter that causes indexing issues.
 
---
 
## Phase 17 — Load Testing
 
### Issue: Locust `stats.max_rps` AttributeError
 
**Symptom:**
```
AttributeError: 'StatsEntry' object has no attribute 'max_rps'
```
Test summary logs fail to print at test end.
 
**Root cause:**
`max_rps` was removed from the `StatsEntry` object in Locust 2.x. The replacement is `current_rps` which returns the RPS at the moment it's called.
 
**Fix:**
```bash
sed -i '' 's/stats.max_rps/stats.current_rps/' load_tests/locustfile.py
```
 
**Lesson:** Locust has breaking API changes between minor versions. Always pin Locust to a specific version (`locust==2.32.4`) and test the locustfile after upgrades.
 
---
 
### Issue: 503 failures during ArgoCD sync mid-load-test
 
**Symptom:**
```
CatchResponseError('Service unavailable — model not loaded or pod restarting')
CatchResponseError('HTTP 503: upstream connect error... reset reason: connection termination')
```
32% failure rate when ArgoCD synced a values.yaml change during an active load test.
 
**Root cause:**
ArgoCD synced new HPA values which triggered a Rollout update. During pod restart, Istio Envoy sidecar terminated in-flight connections. The ALB continued routing to terminating pods for a few seconds before deregistering them, causing connection resets.
 
**Fix:**
Add `preStop` lifecycle hook and `terminationGracePeriodSeconds` to the Rollout pod spec:
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]   # drain ALB before SIGTERM
terminationGracePeriodSeconds: 60              # complete in-flight requests
```
 
**Why 5 seconds:** ALB target group deregistration takes 2-5 seconds. The preStop sleep ensures no new connections arrive after the pod starts shutting down, preventing connection resets.
 
**Lesson:** Always add `preStop` hooks to production pods that receive HTTP traffic. Without it, rolling updates and scale-down events cause connection errors during the ALB deregistration window. This is especially important when Istio sidecars are present — Envoy proxy shutdown is not instantaneous.
 
---
 
### Issue: HPA not reflecting updated values after ArgoCD sync
 
**Symptom:**
```bash
kubectl get hpa -n churn-mlops
# Shows old values: MINPODS=1, MAXPODS=3, cpu=70%
# Even after git push with new values
```
 
**Root cause:**
ArgoCD has a 3-minute polling interval. Changes pushed to Git are not immediately reflected. Additionally, `ServerSideApply=true` can cause ArgoCD to skip updating fields it didn't originally manage.
 
**Fix:**
Force immediate refresh:
```bash
kubectl annotate application churn-prediction-api -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```
 
Wait 30 seconds and verify:
```bash
kubectl get hpa -n churn-mlops
# Should show: MINPODS=2, MAXPODS=5, cpu=50%
```
 
**Lesson:** `argocd.argoproj.io/refresh=hard` forces ArgoCD to bypass the manifest cache and re-fetch from GitHub immediately. Use this whenever you need changes to apply faster than the 3-minute polling interval.
 
---
 
## 🧠 Additional Lessons Learned (Phases 13–17)
 
| Area | Lesson |
|------|--------|
| **ArgoCD + Helm hooks** | ArgoCD skips pre/post-install hooks. Disable hook-dependent features (e.g., admission webhooks) when managing charts via ArgoCD. |
| **ArgoCD adoption** | When adopting existing Helm releases, `releaseName` must match exactly. Mismatched names create duplicate deployments. |
| **Namespace finalizers** | Force-clear with `kubectl replace --raw /api/v1/namespaces/<name>/finalize`. Recreating the namespace first makes orphaned resources addressable. |
| **Argo Rollouts + Istio** | VirtualService HTTP route must have `name: primary`. Without it, Argo Rollouts cannot find the route to update weights. |
| **ServerSideApply** | All port definitions need `protocol: TCP`. Associative list key fields must be explicit. |
| **SHAP 0.46.0** | Output shape changed to `(samples, features, classes)`. Index `[:, :, 1]` for class 1. |
| **GE + pandas** | GE 1.4.4 requires `pandas<2.2`. Install `pandas==2.1.4` to satisfy GE, mlflow, and shap simultaneously. |
| **Locust + Istio** | 503s during pod restarts are caused by Envoy sidecar shutdown + ALB deregistration lag. Fix with `preStop: sleep 5`. |
| **HPA tuning** | `minReplicas=1` causes cold-start latency spikes. Always set `minReplicas=2` for production APIs. Lower CPU threshold to 50% for earlier scaling. |
| **Bitnami OCI migration** | Bitnami removed old chart versions from HTTP repo. Use OCI URL or raw manifests instead. |
| **GitHub curl** | Always use `-L` flag for GitHub release downloads. Without it, redirects are not followed and 0 bytes are downloaded. |

---
 
## Phase 18 — Multi-Environment
 
### Issue: ArgoCD Application in wrong cluster syncs resources to prod
 
**Symptom:**
A change pushed to the `dev` branch accidentally synced to the prod ArgoCD instance because both instances watch the same repo path.
 
**Root cause:**
When multiple ArgoCD instances watch the same Git repo, the `path` and `targetRevision` fields must be unique per environment. If both dev and prod ArgoCD Applications point to `path: helm/churn-mlops` with `targetRevision: main`, a push to main triggers both clusters simultaneously.
 
**Fix:**
Use environment-specific paths or branches:
```yaml
# argocd/dev/apps/churn-api.yaml
source:
  path: helm/churn-mlops
  targetRevision: main
  helm:
    valueFiles:
      - values.yaml
      - values-dev.yaml     # dev-specific overrides
 
# argocd/prod/apps/churn-api.yaml
source:
  path: helm/churn-mlops
  targetRevision: main
  helm:
    valueFiles:
      - values.yaml
      - values-prod.yaml    # prod-specific overrides
```
 
Each ArgoCD instance is installed in its own cluster — dev ArgoCD only manages dev resources, prod ArgoCD only manages prod resources. The `destination.server` field points each Application to its own cluster API server.
 
**Lesson:** Always use separate ArgoCD instances per cluster, not one ArgoCD instance managing multiple clusters via `destination.server`. While ArgoCD supports multi-cluster management, for environment isolation each cluster should have its own ArgoCD with its own RBAC and sync policies.
 
---
 
### Issue: `latest` image tag causes prod to run untested code
 
**Symptom:**
A broken model was deployed to prod because the image tag `latest` was updated by a dev build pipeline that ran tests but not the full integration test suite.
 
**Root cause:**
Using `latest` as the image tag in prod means any new `docker push` overwrites what prod is running. There's no way to know which code version is running, no ability to pin to a known-good version, and no audit trail.
 
**Fix:**
Use semantic versioning for prod image tags:
```yaml
# values-dev.yaml
image:
  tag: dev-latest       # rebuilt on every push — acceptable for dev
 
# values-staging.yaml
image:
  tag: staging-latest   # promoted from dev after tests pass
 
# values-prod.yaml
image:
  tag: v1.2.3           # pinned — never changes until explicit promotion
```
 
In CI/CD, retag the image at each promotion gate:
```bash
# Promote dev → staging
docker pull $ECR/churn-prediction-api:dev-latest
docker tag $ECR/churn-prediction-api:dev-latest $ECR/churn-prediction-api:staging-latest
docker push $ECR/churn-prediction-api:staging-latest
 
# Promote staging → prod (with semantic version)
docker tag $ECR/churn-prediction-api:staging-latest $ECR/churn-prediction-api:v1.2.3
docker push $ECR/churn-prediction-api:v1.2.3
```
 
**Lesson:** `latest` is acceptable in dev and staging where you want the newest code automatically. In prod, always pin to a specific semantic version tag. This gives you rollback capability (`helm upgrade --set image.tag=v1.2.2`) and a clear audit trail of what ran when.
 
---
 
### Issue: Terraform module change breaks all environments simultaneously
 
**Symptom:**
A bug introduced in `terraform/modules/eks/main.tf` broke all three environments (dev, staging, prod) when `terraform apply` was run in each environment directory.
 
**Root cause:**
All environments call the same module. A breaking change to the module affects all environments that reference it.
 
**Fix:**
Use module versioning with Git tags:
```hcl
# Reference a specific tagged version of the module
module "eks" {
  source = "git::https://github.com/Himanshu9001/MLOps-Projects.git//terraform/modules/eks?ref=v1.2.0"
}
```
 
Or use a `versions.tf` pattern where dev tracks `main` and prod tracks a pinned tag:
```hcl
# dev — always uses latest module
module "eks" {
  source = "../../modules/eks"   # local reference, always latest
}
 
# prod — pinned to tested version
module "eks" {
  source  = "../../modules/eks"
  # Manually update only after testing in dev and staging
}
```
 
**Lesson:** Treat Terraform modules like software libraries — pin versions in prod, allow latest in dev. Always test module changes in dev before applying to staging/prod. Use `terraform plan` before every `terraform apply` to review changes.
 
---
 
## Phase 19 — Hardening
 
### Issue: ElastiCache connection reset from EKS pods
 
**Symptom:**
```
Error: Connection reset by peer
redis-cli -h churn-mlops-redis.xxx.cache.amazonaws.com ping
```
 
**Root cause:**
Two possible causes:
1. VPC Peering route missing from private subnet route table — ElastiCache lives in private subnets but the private route table had no route to the EKS VPC CIDR
2. Security Group not allowing traffic from EKS VPC CIDR
**Fix:**
Check both:
```bash
# 1. Verify SG allows port 6379 from EKS VPC CIDR
aws ec2 describe-security-groups \
  --group-ids $ELASTICACHE_SG \
  --query 'SecurityGroups[0].IpPermissions'
 
# 2. Check private subnet route table has route to EKS VPC
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-0c08813ed92e2b022" \
  --query 'RouteTables[*].{ID:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Target:GatewayId}}'
 
# Fix — add missing route to private subnet route table
aws ec2 create-route \
  --route-table-id rtb-0bdd1180eb26d9c25 \
  --destination-cidr-block 192.168.0.0/16 \
  --vpc-peering-connection-id $PEERING_ID \
  --region us-east-1
```
 
**Lesson:** ElastiCache in private subnets needs two things to be reachable from EKS: (1) a Security Group rule allowing port 6379 from the EKS VPC CIDR, and (2) a route in the private subnet route table pointing EKS VPC traffic to the VPC Peering connection. Missing either one causes a connection reset.
 
---
 
### Issue: ElastiCache subnet group — wrong CLI subcommand
 
**Symptom:**
```
aws: [ERROR]: argument operation: Found invalid choice 'create-subnet-group'
Maybe you meant:
  * create-cache-subnet-group
```
 
**Root cause:**
All ElastiCache CLI subcommands use the `cache-` prefix. `create-subnet-group` is the EC2/RDS pattern — ElastiCache uses `create-cache-subnet-group`.
 
**Fix:**
```bash
# Wrong
aws elasticache create-subnet-group ...
 
# Correct
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name churn-mlops-elasticache-subnet \
  --cache-subnet-group-description "Private subnets for ElastiCache" \
  --subnet-ids subnet-095a2844b2809bf7d subnet-0cf890022b3095da4 \
  --region us-east-1
```
 
**Lesson:** ElastiCache CLI subcommands follow `*-cache-*` naming convention — `create-cache-cluster`, `create-cache-subnet-group`, `describe-cache-clusters`. When in doubt, run `aws elasticache help` to see all available subcommands.
 
---
 
### Issue: AWS CLI Security Group description rejects non-ASCII characters
 
**Symptom:**
```
An error occurred (InvalidParameterValue): Value for parameter GroupDescription
is invalid. Character sets beyond ASCII are not supported.
```
 
**Root cause:**
The `—` em dash character (Unicode U+2014) was used in the description string. AWS Security Group descriptions only accept standard ASCII characters (letters, numbers, spaces, and basic punctuation).
 
**Fix:**
Replace em dash `—` with regular hyphen `-`:
```bash
# Wrong — em dash copied from formatted text
--description "ElastiCache Redis SG — allow port 6379 from EKS only"
 
# Correct — ASCII hyphen
--description "ElastiCache Redis SG - allow port 6379 from EKS only"
```
 
**Lesson:** Always use plain ASCII in AWS resource names and descriptions. Em dashes, smart quotes, and other Unicode characters commonly appear when copying from formatted documents (markdown, PDFs, chat interfaces) and cause AWS API validation errors. Use regular hyphens `-` and straight quotes `"` in all AWS CLI commands.
 
---
 
### Issue: ElastiCache NOT deleted by `eksctl delete cluster`
 
**Symptom:**
Unexpected AWS charges after deleting the EKS cluster. ElastiCache cluster still running and billing at $0.017/hour.
 
**Root cause:**
`eksctl delete cluster` only deletes resources created by eksctl — the EKS cluster, nodegroups, VPC (if eksctl created it), and associated CloudFormation stacks. ElastiCache was created independently via `aws elasticache create-cache-cluster` and is not tracked by eksctl.
 
**Fix:**
Always delete ElastiCache manually as part of evening teardown:
```bash
aws elasticache delete-cache-cluster \
  --cache-cluster-id churn-mlops-redis \
  --region us-east-1
```
 
Add to `teardown-networking.sh`:
```bash
echo "Deleting ElastiCache cluster..."
aws elasticache delete-cache-cluster \
  --cache-cluster-id churn-mlops-redis \
  --region us-east-1 2>/dev/null || echo "ElastiCache already deleted or not found"
echo "ElastiCache deletion initiated (takes ~2 minutes)"
```
 
**Lesson:** Any AWS resource created outside of eksctl (ElastiCache, RDS, EC2, S3) must be tracked and deleted separately. The safest approach is Terraform — `terraform destroy` deletes everything it created, nothing more and nothing less. This is one of the key motivations for migrating to Terraform in Phase 20.
 
---
 
### Issue: Route table has `192.168.0.0/16 → None` after cluster recreation
 
**Symptom:**
```bash
aws ec2 describe-route-tables ...
# Shows: 192.168.0.0/16 | None
```
ElastiCache unreachable after morning cluster recreation.
 
**Root cause:**
`setup-networking.sh` creates a new VPC Peering connection every morning (new cluster = new EKS VPC = new peering ID). The route in `rtb-0aa03046d2eddd459` that previously pointed to yesterday's peering connection now shows `None` because the old peering connection was deleted during teardown.
 
**Fix:**
`setup-networking.sh` automatically runs `aws ec2 replace-route` after creating the new peering connection — this updates the route target. But the private subnet route table `rtb-0bdd1180eb26d9c25` needs a separate `create-route` call since ElastiCache lives there.
 
Add to `setup-networking.sh` after VPC peering setup:
```bash
# Fix route for private subnet route table (ElastiCache lives here)
aws ec2 create-route \
  --route-table-id rtb-0bdd1180eb26d9c25 \
  --destination-cidr-block $EKS_CIDR \
  --vpc-peering-connection-id $PEERING_ID \
  --region $REGION > /dev/null 2>&1 || \
aws ec2 replace-route \
  --route-table-id rtb-0bdd1180eb26d9c25 \
  --destination-cidr-block $EKS_CIDR \
  --vpc-peering-connection-id $PEERING_ID \
  --region $REGION > /dev/null
echo "Private subnet route to EKS VPC updated"
```
 
**Lesson:** Your VPC has two route tables — public (`rtb-0aa03046d2eddd459`) and private (`rtb-0bdd1180eb26d9c25`). `setup-networking.sh` originally only updated the public one. After adding ElastiCache to private subnets, both route tables need updating on every cluster recreation. This will be automated in the Terraform migration.
 
---
 
### Issue: IAM policy already exists when re-running setup-iam.sh
 
**Symptom:**
```
An error occurred (EntityAlreadyExists): A policy called
churn-mlops-cluster-autoscaler-policy already exists with a different name.
```
 
**Root cause:**
`setup-iam.sh` runs `aws iam create-policy` without checking if the policy already exists. On second run it fails because IAM policy names must be unique per account.
 
**Fix:**
Add `2>/dev/null || true` to handle idempotency:
```bash
aws iam create-policy \
  --policy-name churn-mlops-cluster-autoscaler-policy \
  --policy-document file:///tmp/cluster-autoscaler-policy.json \
  2>/dev/null || echo "Policy already exists — skipping"
```
 
Or check existence first:
```bash
POLICY_ARN="arn:aws:iam::011528270076:policy/churn-mlops-cluster-autoscaler-policy"
aws iam get-policy --policy-arn $POLICY_ARN > /dev/null 2>&1 || \
  aws iam create-policy \
    --policy-name churn-mlops-cluster-autoscaler-policy \
    --policy-document file:///tmp/cluster-autoscaler-policy.json
```
 
**Lesson:** All infrastructure scripts must be idempotent — safe to run multiple times. AWS CLI create commands fail on second run with `EntityAlreadyExists`. Always add `2>/dev/null || true` or existence checks to creation commands in setup scripts.
 
---
 
### Issue: ElastiCache `wait` command hangs with smart quote error
 
**Symptom:**
```bash
aws elasticache wait cache-cluster-available \
  --cache-cluster-id churn-mlops-redis \
  --region us-east-1 && echo "ElastiCache ready!"
cmdand dquote>
```
Terminal hangs waiting for a closing quote.
 
**Root cause:**
The `"` in `"ElastiCache ready!"` was interpreted as a smart/curly quote (Unicode `"`) instead of a straight ASCII double quote. The shell saw an unclosed string and waited for the closing quote.
 
**Fix:**
Run as two separate commands instead of using `&&` chaining:
```bash
# Command 1 — wait for availability
aws elasticache wait cache-cluster-available \
  --cache-cluster-id churn-mlops-redis \
  --region us-east-1
 
# Command 2 — confirm when done
echo "ElastiCache ready!"
```
 
**Lesson:** Smart quotes (`"` `"`) copied from formatted text (markdown renderers, chat interfaces, PDFs) look identical to straight quotes in some fonts but are different Unicode characters. Shells only recognize straight ASCII quotes as string delimiters. Always type quotes directly in the terminal rather than copying from formatted sources.
 
---
 
## 🧠 Additional Lessons Learned (Phases 18–19)
 
| Area | Lesson |
|------|--------|
| **Multi-env image tags** | Never use `latest` in prod. Use `dev-latest` → `staging-latest` → `v1.x.x` promotion chain. |
| **Terraform modules** | All envs call the same module — a bug in the module affects all envs. Test module changes in dev first. |
| **ElastiCache teardown** | ElastiCache is NOT deleted by `eksctl delete cluster`. Always delete manually or via `teardown-networking.sh`. |
| **Private subnet routing** | ElastiCache in private subnets needs routes in the private route table, not just the public one. |
| **IAM idempotency** | All IAM create commands need `2>/dev/null || true` — they fail on second run with EntityAlreadyExists. |
| **ASCII descriptions** | AWS resource descriptions only accept ASCII. Em dashes and smart quotes from formatted text cause API errors. |
| **ElastiCache CLI prefix** | All ElastiCache subcommands use `cache-` prefix: `create-cache-cluster`, `create-cache-subnet-group`. |
| **Smart quotes in terminal** | Never copy-paste commands containing smart quotes from formatted sources — use straight ASCII quotes. |
| **Terraform destroy** | Key motivation for Terraform: `terraform destroy` deletes everything it created. No manual tracking of external resources. |
 

 # Troubleshooting Guide — Phase 20 (Terraform Infrastructure + CI/CD)

> All issues encountered during the May 2026 blue-green migration from eksctl to Terraform-managed infrastructure. Each entry includes the exact error, root cause, and fix.

---

## Table of Contents

1. [Terraform Issues](#terraform-issues)
2. [EKS / Kubernetes Issues](#eks--kubernetes-issues)
3. [Istio Issues](#istio-issues)
4. [Helm Issues](#helm-issues)
5. [ArgoCD Issues](#argocd-issues)
6. [ArgoCD Image Updater Issues](#argocd-image-updater-issues)
7. [MLflow / Model Issues](#mlflow--model-issues)
8. [GitHub Actions CI/CD Issues](#github-actions-cicd-issues)
9. [AWS / Infrastructure Issues](#aws--infrastructure-issues)
10. [Shell / Git Issues](#shell--git-issues)

---

## Terraform Issues

### 1. Em Dash Characters in HCL Description Fields

**Error:**
```
Error: Invalid character
An unexpected character was found: '—'
```

**Root Cause:** Em dash (`—`) characters copied from documentation or chat were embedded in HCL `description` fields. AWS API rejects them; HCL parser fails.

**Fix:**
```bash
# Find and replace all em dashes in terraform files
find terraform/ -name "*.tf" -exec sed -i '' 's/\xe2\x80\x94/-/g' {} \;
```

---

### 2. Stale Terraform State Lock

**Error:**
```
Error: Error acquiring the state lock
Error message: resource temporarily unavailable
```

**Root Cause:** Previous `terraform` process was killed (Ctrl+C or kill -9) without releasing the S3 native lock file.

**Diagnosis:**
```bash
aws s3 cp \
  s3://churn-mlops-nonprod-terraform-state/nonprod/<stack>/terraform.tfstate.tflock \
  - | python3 -m json.tool
```

If `"Operation": "OperationTypeInvalid"` — always stale, safe to delete.

**Fix:**
```bash
# ⚠️ CAUTION — only if no terraform operation is actually running
aws s3 rm \
  s3://churn-mlops-nonprod-terraform-state/nonprod/<stack>/terraform.tfstate.tflock \
  --region us-east-1
```

---

### 3. Local State Lock (00-s3-backend Stack)

**Error:**
```
Error: Error acquiring the state lock
open .terraform.tfstate.lock.info: no such file or directory
```

**Root Cause:** `00-s3-backend` uses local state. Two terminal processes ran simultaneously or previous process was killed without releasing the local lock.

**Diagnosis:**
```bash
ps aux | grep terraform | grep -v grep | grep -v terraform-ls
```

**Fix:**
```bash
# Kill the stale process
kill -9 <PID>

# If lock file still exists
rm -f terraform/live/nonprod/00-s3-backend/stacks/.terraform.tfstate.lock.info
```

---

### 4. Terraform Plan Hanging (00-s3-backend)

**Symptom:** `terraform plan` hangs indefinitely with no output.

**Root Cause:** Two `terraform plan` processes running simultaneously in different terminals fighting over the local state lock.

**Diagnosis:**
```bash
ps aux | grep terraform | grep -v grep | grep -v terraform-ls
```

**Fix:**
```bash
kill -9 <PID of stale terraform plan>
terraform plan -lock=false 2>&1 | tail -10
```

---

### 5. Accidentally Deleted Terraform State File

**Symptom:** `terraform plan` shows 30+ resources to create that already exist.

**Root Cause:** Manual `aws s3 rm` or accidental deletion of state file.

**Recovery (S3 versioning saves you):**
```bash
# Check delete markers
aws s3api list-object-versions \
  --bucket churn-mlops-nonprod-terraform-state \
  --query 'DeleteMarkers[?Key==`nonprod/10-network/terraform.tfstate`].{Key:Key,VersionId:VersionId}' \
  --output table

# Restore by deleting the delete marker
aws s3api delete-object \
  --bucket churn-mlops-nonprod-terraform-state \
  --key nonprod/10-network/terraform.tfstate \
  --version-id <DELETE_MARKER_VERSION_ID>

# Verify restored
terraform plan -var-file=../params/main.tfvars 2>&1 | tail -5
# Expected: No changes. Your infrastructure matches the configuration.
```

---

### 6. `ignore_changes` Silently Blocks Intentional Scaling

**Symptom:** `terraform apply` shows `desired_size = 3 -> 4` in plan but AWS node group stays at 3.

**Root Cause:** `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` prevents Terraform from changing `desired_size` even when explicitly set in tfvars.

**Fix:**
```bash
# Scale directly via CLI
aws eks update-nodegroup-config \
  --cluster-name churn-mlops-nonprod \
  --nodegroup-name churn-mlops-nonprod-node-group \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --region us-east-1

# Remove the ignore_changes block from eks/main.tf
# lifecycle { ignore_changes = [] }
```

---

### 7. Module Not Installed After Adding New Module

**Error:**
```
Error: Module not installed
on main.tf line 104: module "ecr" {
This module is not yet installed. Run "terraform init" to install all modules.
```

**Root Cause:** New module added to stack but `terraform init` not re-run.

**Fix:**
```bash
terraform init -backend-config=../backends/backend.hcl -reconfigure
terraform apply -var-file=../params/main.tfvars
```

---

### 8. Duplicate Variable Declaration

**Error:**
```
Error: Duplicate variable declaration
on ../../../../modules/ecr/variables.tf line 65: variable "force_delete"
A variable named "force_delete" was already declared at line 57.
```

**Root Cause:** `cat >>` appended content to `variables.tf` when the variable already existed.

**Fix:**
```python
# Use Python to remove exact duplicate
with open('terraform/modules/ecr/variables.tf', 'r') as f:
    content = f.read()

import re
blocks = list(re.finditer(r'variable "force_delete" \{[^}]+\}', content, re.DOTALL))
if len(blocks) > 1:
    for block in reversed(blocks[1:]):
        content = content[:block.start()].rstrip() + '\n' + content[block.end():]
    with open('terraform/modules/ecr/variables.tf', 'w') as f:
        f.write(content)
```

**Prevention:** Always check before appending:
```bash
grep -q "force_delete" terraform/modules/ecr/variables.tf && echo "EXISTS" || cat >> variables.tf
```

---

### 9. `terraform_remote_state` Not Declared

**Error:**
```
Error: Reference to undeclared resource
on main.tf line 100: identifiers = [data.terraform_remote_state.kubernetes.outputs.oidc_provider_arn]
A data resource "terraform_remote_state" "kubernetes" has not been declared.
```

**Root Cause:** New resource in `30-compute` references `40-kubernetes` state output but the data source was not declared in `30-compute/stacks/main.tf`.

**Fix:** Add the remote state data source:
```hcl
data "terraform_remote_state" "kubernetes" {
  backend = "s3"
  config = {
    bucket = "churn-mlops-nonprod-terraform-state"
    key    = "nonprod/40-kubernetes/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

### 10. `dynamodb_table` Deprecation Warning

**Warning:**
```
Warning: Deprecated Parameter
The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile" instead.
```

**Root Cause:** Terraform 1.10+ switched from DynamoDB to S3 native file-based locking. The old `dynamodb_table` backend config is deprecated.

**Fix:** Update `backend.hcl` files:
```hcl
# Old
dynamodb_table = "churn-mlops-nonprod-terraform-locks"

# New
use_lockfile = true
```

---

## EKS / Kubernetes Issues

### 11. EBS CSI Driver CrashLoopBackOff

**Error:**
```
no EC2 IMDS role found
```

**Root Cause:** EBS CSI addon was configured without an IRSA role. It tried to use EC2 instance metadata (IMDS) which is disabled or insufficient.

**Fix:** Create a dedicated IRSA role for EBS CSI and add it to the addon config:
```bash
# Create role manually
aws iam create-role --role-name churn-mlops-nonprod-ebs-csi-role \
  --assume-role-policy-document file:///tmp/ebs-csi-trust.json

aws iam attach-role-policy \
  --role-name churn-mlops-nonprod-ebs-csi-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# Add to eks module in Terraform
service_account_role_arn = "arn:aws:iam::011528270076:role/churn-mlops-nonprod-ebs-csi-role"
```

---

### 12. EKS SPOT Nodes Not Joining Cluster

**Symptom:** Node group shows `InProgress` but nodes never become `Ready`. Pods stuck in `Pending`.

**Root Cause:** SPOT nodes in private subnets could not reach EKS control plane or pull images — NAT Gateway was not enabled for nonprod.

**Fix:** Enable NAT Gateway in nonprod VPC:
```hcl
# terraform/live/nonprod/10-network/params/main.tfvars
enable_nat_gateway = true
single_nat_gateway = true
```

---

### 13. kubectl top nodes — Metrics API Not Available

**Error:**
```
error: Metrics API not available
```

**Root Cause:** Kubernetes Metrics Server is not installed. `kube-prometheus-stack` installs Prometheus but NOT the Kubernetes Metrics Server — they are separate components.

**Fix:** Install Metrics Server separately or check if it is included in your addon config:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

### 14. Pod Stuck in Pending — Insufficient Memory

**Error (from kubectl describe):**
```
0/3 nodes are available: 1 Too many pods, 3 Insufficient memory.
```

**Root Cause:** Full stack (Kafka, Airflow, Prometheus, ArgoCD, Istio) exceeded 3x t3.medium memory capacity.

**Fix:** Scale to 4 nodes:
```bash
# Update tfvars
# node_desired_count = 4
# node_min_count     = 3

# Apply via Terraform (preferred)
terraform apply -var-file=../params/main.tfvars

# Or directly via CLI if ignore_changes blocks Terraform
aws eks update-nodegroup-config \
  --cluster-name churn-mlops-nonprod \
  --nodegroup-name churn-mlops-nonprod-node-group \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --region us-east-1
```

---

### 15. SSH Timeout — Dynamic IP Changed

**Symptom:** `ssh -i key.pem ec2-user@<EIP>` times out.

**Root Cause:** ISP assigned a new dynamic public IP. Security group SSH rule only allows old IP.

**Fix:**
```bash
NEW_IP=$(curl -s https://api.ipify.org)
# Update allowed_ssh_cidrs in 10-network/params/main.tfvars
# allowed_ssh_cidrs = ["<NEW_IP>/32"]
terraform apply -var-file=../params/main.tfvars
```

**Long-term fix:** Use SSM Session Manager — no inbound ports needed:
```bash
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

---

### 16. SSM Session Manager Plugin Not Found

**Error:**
```
SessionManagerPlugin is not found.
```

**Fix (macOS ARM):**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" \
  -o /tmp/session-manager-plugin.pkg
sudo installer -pkg /tmp/session-manager-plugin.pkg -target /
export PATH=$PATH:/usr/local/sessionmanagerplugin/bin
echo 'export PATH=$PATH:/usr/local/sessionmanagerplugin/bin' >> ~/.zshrc
```

---

## Istio Issues

### 17. istiod Pending — Insufficient Memory

**Symptom:** `istiod` pod stuck in `Pending` for hours.

**Error (from kubectl describe):**
```
0/3 nodes are available: 3 Insufficient memory.
```

**Root Cause:** Full stack consumed all available memory across 3x t3.medium nodes.

**Fix:** Scale to 4 nodes (see Issue #14).

---

### 18. Stream Processor Stuck at Init:1/2

**Symptom:** `churn-stream-processor` pod shows `Init:1/2` and never becomes ready.

**Root Cause:** Istio namespace label `istio-injection=enabled` was applied to `churn-mlops` namespace. Stream processor does not need Istio — `istio-proxy` native sidecar init container blocks startup.

**Fix:** Add annotation to stream processor deployment:
```yaml
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "false"
```

```bash
# In k8s/stream-processor-deployment.yaml
# Then git push → ArgoCD auto-syncs
```

---

### 19. Prediction API Init:1/2 — Istio Native Sidecar Intermittent Failure

**Symptom:** New prediction API pods intermittently stuck at `Init:1/2`. One pod starts fine (`2/2`), another gets stuck.

**Root Cause:** Istio 1.29+ uses native sidecar mode where `istio-proxy` runs as an init container. Intermittently fails on some nodes due to CNI configuration differences.

**Fix:** Disable Istio sidecar on prediction API pods (Argo Rollouts + ALB handles canary traffic without Istio):
```yaml
# In helm/churn-mlops/templates/rollout.yaml
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "false"
```

---

## Helm Issues

### 20. Helm ServerSideApply Conflict with Argo Rollouts

**Error:**
```
conflict occurred while applying object churn-mlops/churn-prediction-api-destrule:
Apply failed with 1 conflict: conflict with "rollouts-controller" using networking.istio.io/v1alpha3: .spec.subsets
```

**Root Cause:** Argo Rollouts controller owns `.spec.subsets` on `DestinationRule` via ServerSideApply with field manager `networking.istio.io/v1alpha3`. Helm uses `networking.istio.io/v1beta1`. Two field managers clash on the same field.

**Fix:** Delete the conflicting resources before Helm upgrade:
```bash
kubectl delete destinationrule churn-prediction-api-destrule -n churn-mlops 2>/dev/null || true
kubectl delete virtualservice churn-prediction-api-vsvc -n churn-mlops 2>/dev/null || true
helm upgrade --install churn-mlops helm/churn-mlops/ --values helm/churn-mlops/values.yaml
```

This is automated in `bootstrap-new-cluster.sh`.

---

### 21. Helm Release in Wrong Namespace

**Symptom:** `helm list` shows no releases. `helm upgrade --install` creates release in `default` namespace instead of `churn-mlops`.

**Root Cause:** `helm upgrade --install churn-mlops helm/churn-mlops/` run without `-n churn-mlops` flag.

**Fix:**
```bash
helm upgrade --install churn-mlops helm/churn-mlops/ \
  -n churn-mlops \
  --values helm/churn-mlops/values.yaml
```

---

### 22. Helm `--force` Deprecated

**Error:**
```
Flag --force has been deprecated, use --force-replace instead
invalid operation: cannot use server-side apply and force replace together
```

**Root Cause:** `--force` was deprecated in Helm 3.14+. `--force-replace` is incompatible with ServerSideApply.

**Fix:** Delete conflicting resources and re-upgrade without `--force` (see Issue #20).

---

## ArgoCD Issues

### 23. ArgoCD Install — `stable` Tag Returns 404

**Error:**
```
error: unable to read URL "https://raw.githubusercontent.com/argoproj/argo-cd/stable/install.yaml",
server reported 404 Not Found
```

**Root Cause:** The `stable` branch tag on GitHub raw content no longer resolves.

**Fix:** Pin to explicit version:
```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.9/manifests/install.yaml
```

Update `bootstrap-new-cluster.sh` to always use pinned version.

---

### 24. Argo Rollouts Install — `latest` Tag Unpredictable

**Fix:** Pin to explicit version:
```bash
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/install.yaml
```

---

### 25. ArgoCD Application Stuck in Suspended State

**Symptom:** `kubectl get applications -n argocd` shows `churn-prediction-api` as `Suspended`.

**Root Cause:** Argo Rollouts canary is paused at a `pause: {}` step (indefinite pause) waiting for manual promotion.

**Fix:**
```bash
kubectl argo rollouts promote churn-prediction-api -n churn-mlops
```

**Long-term fix:** Replace indefinite pause with time-based pause in rollout spec:
```yaml
# In helm/churn-mlops/templates/rollout.yaml
steps:
  - pause: {duration: 120s}   # NOT pause: {}
```

---

## ArgoCD Image Updater Issues

### 26. Image Updater Install — `stable` Tag Returns 404

**Error:**
```
error: unable to read URL ".../argocd-image-updater/stable/manifests/install.yaml"
server reported 404 Not Found
```

**Fix:** Use Helm chart instead:
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set config.argocd.serverAddress=argocd-server \
  --set config.argocd.insecure=true \
  --wait
```

---

### 27. Image Updater Helm Install Fails — Orphaned Resources

**Error:**
```
unable to continue with install: ServiceAccount "argocd-image-updater" exists
and cannot be imported: invalid ownership metadata; missing key "app.kubernetes.io/managed-by"
```

**Root Cause:** Previous `kubectl apply` created resources without Helm ownership labels. Helm refuses to adopt them.

**Fix:** Delete all orphaned resources first:
```bash
kubectl delete serviceaccount argocd-image-updater -n argocd 2>/dev/null || true
kubectl delete clusterrole argocd-image-updater 2>/dev/null || true
kubectl delete clusterrolebinding argocd-image-updater 2>/dev/null || true
kubectl delete deployment argocd-image-updater -n argocd 2>/dev/null || true
kubectl delete role argocd-image-updater -n argocd 2>/dev/null || true
kubectl delete rolebinding argocd-image-updater -n argocd 2>/dev/null || true
kubectl delete configmap argocd-image-updater-config -n argocd 2>/dev/null || true
kubectl delete configmap argocd-image-updater-ssh-config -n argocd 2>/dev/null || true
kubectl delete secret argocd-image-updater-secret -n argocd 2>/dev/null || true
```

Then retry Helm install.

---

### 28. Image Updater — No Basic Auth Credentials for ECR

**Error:**
```
Could not get tags from registry: no basic auth credentials
```

**Root Cause:** Image Updater cannot authenticate to ECR. IRSA was annotated on service account but pod was not restarted, OR the `registries.conf` configmap was not configured.

**Fix:** Configure ECR registry in Image Updater configmap with `pullsecret` format:

```bash
# Create ECR credentials secret
AWS_ACCOUNT=011528270076
REGION=us-east-1
ECR_TOKEN=$(aws ecr get-authorization-token \
  --region $REGION \
  --query 'authorizationData[0].authorizationToken' \
  --output text | base64 -d | cut -d: -f2)

kubectl create secret docker-registry ecr-creds \
  --docker-server=${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=${ECR_TOKEN} \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# Configure registry in configmap (use pullsecret: not secret:)
kubectl patch configmap argocd-image-updater-config -n argocd --type merge -p '{
  "data": {
    "registries.conf": "registries:\n  - name: ECR\n    api_url: https://011528270076.dkr.ecr.us-east-1.amazonaws.com\n    prefix: 011528270076.dkr.ecr.us-east-1.amazonaws.com\n    ping: false\n    credentials: pullsecret:argocd/ecr-creds\n    credsexpire: 10h\n"
  }
}'

kubectl rollout restart deployment argocd-image-updater-controller -n argocd
```

**Note:** ECR token expires every 12 hours. Refresh with bootstrap script Step 15.

---

### 29. Image Updater — Invalid Secret Definition

**Error:**
```
Could not set registry endpoint credentials: invalid secret definition: argocd/ecr-creds
```

**Root Cause:** Wrong secret reference format. Used `secret:argocd/ecr-creds` instead of `pullsecret:argocd/ecr-creds` for a `kubernetes.io/dockerconfigjson` type secret.

**Fix:** Use `pullsecret:` prefix for docker-registry secrets (see Issue #28).

---

### 30. Image Updater — `latest` Strategy Renamed

**Warning:**
```
"latest" strategy has been renamed to "newest-build". Support for old naming will be removed.
```

**Fix:** Update `ImageUpdater` CR:
```yaml
commonUpdateSettings:
  updateStrategy: newest-build   # NOT: latest
```

---

### 31. Image Updater — `spec.images` Unknown Field

**Error:**
```
ImageUpdater cannot be handled: strict decoding error: unknown field "spec.images"
```

**Root Cause:** ArgoCD Image Updater v1.1.1 moved from top-level `spec.images` to `spec.applicationRefs[].images`. Breaking change from v0.x.

**Fix:** Use correct v1.1.1 schema:
```yaml
spec:
  applicationRefs:
    - namePattern: "churn-prediction-api"
      images:
        - alias: prediction-api
          imageName: <ECR_URL>:latest
          commonUpdateSettings:
            updateStrategy: newest-build
      writeBackConfig:
        method: argocd
```

---

## MLflow / Model Issues

### 32. Prediction API CrashLoop — MLflow Alias Not Found

**Error (from pod logs):**
```
mlflow.exceptions.RestException: INVALID_PARAMETER_VALUE: Registered model alias production not found.
```

**Root Cause:** New RDS is always empty after cluster rebuild. MLflow model registry has no registered models.

**Fix:** Run the migration script:
```bash
# Step 1 — Copy model artifact to new S3 bucket
aws s3 cp \
  s3://churn-mlops-artifacts/1/models/m-ffa760cc477d45ccaece4463910f6504/artifacts/ \
  s3://churn-mlops-nonprod-artifacts/1/models/m-ffa760cc477d45ccaece4463910f6504/artifacts/ \
  --recursive

# Step 2 — Upload migration script
aws s3 cp scripts/migrate-mlflow-model.py \
  s3://churn-mlops-nonprod-artifacts/scripts/migrate-mlflow-model.py

# Step 3 — Run via SSM
INSTANCE_ID=$(terraform -chdir=terraform/live/nonprod/30-compute/stacks output -raw mlflow_instance_id)
aws ssm start-session --target $INSTANCE_ID --region us-east-1
# Inside EC2:
# aws s3 cp s3://churn-mlops-nonprod-artifacts/scripts/migrate-mlflow-model.py /tmp/
# pip3 install mlflow boto3 --user --quiet
# python3 /tmp/migrate-mlflow-model.py
```

---

### 33. Prediction API — MLflow Connection Timeout

**Error (from pod logs):**
```
ConnectTimeoutError: Connection to 3.90.73.230 timed out (connect timeout=120)
```

**Root Cause:** Pod was connecting to MLflow via public EIP instead of private IP. Caused by Secrets Manager having the public IP in `churn-mlops/mlflow-tracking-uri`.

**Fix:**
```bash
# Always use private IP for MLflow URI
aws secretsmanager update-secret \
  --secret-id churn-mlops/mlflow-tracking-uri \
  --secret-string '{"MLFLOW_TRACKING_URI":"http://10.1.1.233:5000"}' \
  --region us-east-1

# Update NetworkPolicy in helm/churn-mlops/templates/networkpolicies.yaml
# cidr: 10.1.1.233/32  (NOT 10.0.1.225/32 old cluster)
```

---

## GitHub Actions CI/CD Issues

### 34. Git Conflict on Every Push — CI/CD Commits Back to main

**Symptom:** Every `git push` fails with `non-fast-forward` because CI/CD committed `values.yaml` image tag update to `main`.

**Root Cause:** CI/CD pipeline had a step that committed the SHA image tag to `values.yaml` and pushed to `main`. Creates conflicts with local commits.

**Fix:** Remove the git commit step from CI/CD. Use ArgoCD Image Updater instead:
- Image Updater polls ECR every 2 minutes
- Detects new image SHA on `latest` tag
- Updates ArgoCD Application spec directly (no git commits)
- No more conflicts

---

### 35. GitHub Actions OIDC Authentication Fails

**Error:**
```
Error: Credentials could not be loaded
```

**Root Cause:** OIDC provider not created in AWS, or trust policy condition does not match the GitHub Actions token subject.

**Fix:**
```bash
# Create OIDC provider (one-time)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Verify trust policy subject matches
# token.actions.githubusercontent.com:sub = repo:Himanshu9001/MLOps-Projects:*
```

---

### 36. GitHub Actions Terraform Plan Fails — Node.js 20 Deprecation

**Warning:**
```
Node.js 20 actions are deprecated. Actions will be forced to run with Node.js 24 starting June 2, 2026.
```

**This is a warning, not an error.** Will become a breaking error after June 2, 2026.

**Fix (before June 2026):** Update action versions in `.github/workflows/terraform.yml`:
```yaml
actions/checkout@v4      → actions/checkout@v5 (when available)
hashicorp/setup-terraform@v3  → check for v4
aws-actions/configure-aws-credentials@v4  → check for Node.js 24 compatible version
```

---

## AWS / Infrastructure Issues

### 37. ECR Repo Cannot Be Destroyed — RepositoryNotEmptyException

**Error:**
```
RepositoryNotEmptyException: The repository is not empty
```

**Root Cause:** `terraform destroy` on ECR repo that contains images.

**Fix:** Add `force_delete = true` to ECR module for nonprod:
```hcl
resource "aws_ecr_repository" "main" {
  force_delete = var.force_delete  # true for nonprod
}
```

---

### 38. ECR Repo Name Redundancy

**Issue:** Repos named `churn-mlops-nonprod-churn-prediction-api` — double `churn-` prefix.

**Root Cause:** `repositories` list in `20-data` stack used `churn-prediction-api` but module already prefixes with `${project}-${environment}-`.

**Fix:** Use short names in repositories list:
```hcl
repositories = [
  "prediction-api",      # NOT "churn-prediction-api"
  "stream-processor",
  "materialize"
]
# Results in: churn-mlops-nonprod-prediction-api ✅
```

---

## Shell / Git Issues

### 39. `!` in Password Breaks zsh

**Symptom:**
```
dquote>
```

**Root Cause:** zsh treats `!` as history expansion inside double quotes.

**Fix:** Always use single quotes for passwords:
```bash
export TF_VAR_db_password='MLflow1234!'      # ✅ single quotes
echo "export TF_VAR_db_password='MLflow1234!'" >> ~/.zshrc
```

---

### 40. git push Rejected — Non-Fast-Forward

**Error:**
```
error: failed to push some refs to 'https://github.com/...'
hint: Updates were rejected because the tip of your current branch is behind
```

**Root Cause:** CI/CD or another process committed to `main` between your last pull and push.

**Fix:**
```bash
git pull --rebase origin main
git push origin main

# Set as default to avoid this permanently
git config --global pull.rebase true
```

---

### 41. Heredoc Fails with Special Characters in zsh

**Symptom:** Heredoc content gets corrupted — `$`, `!`, `\` are interpreted by shell.

**Root Cause:** zsh processes special characters inside heredocs unless single-quoted delimiter is used.

**Fix:** Always use single-quoted delimiter:
```bash
cat << 'EOF'        # ✅ single quotes — no interpolation
  content with $vars and ! and \ safe
EOF

cat << EOF          # ❌ double quotes — shell interpolates
  content with $vars expanded
EOF
```

---

### 42. `cat >>` Creates Duplicate Content

**Root Cause:** Blindly appending without checking if content already exists.

**Fix:** Always check first:
```bash
grep -q "force_delete" variables.tf || cat >> variables.tf << 'EOF'
variable "force_delete" { ... }
EOF
```

---

# Phase 20 Best Practices — Troubleshooting

A log of real issues encountered during Phase 20 best practice improvements:
- terraform fmt-check CI/CD job
- pre-commit hooks
- SSE-KMS state encryption
- RDS manage_master_user_password
- EBS CSI IRSA role migration to Terraform
- 50-iam stack (single-pass apply)
- Scoped CI/CD IAM policy

Append these entries to your main `troubleshooting.md` before the `## Quick Reference` section.

---

### 43. `terraform fmt -check` Fails with Semicolons in Single-Line Block

**Symptom:**
```
Error: Invalid character — The ";" character is not valid
Error: Invalid single-argument block definition
  on terraform/live/prod/00-s3-backend/stacks/variables.tf line 3
```

**File:** `terraform/live/prod/00-s3-backend/stacks/variables.tf`

**Root Cause:** HCL does not allow semicolons to separate arguments in single-line blocks. Valid in some parsers but Terraform's HCL parser rejects it.

**Fix:** Expand to multi-line format:
```hcl
# Before (invalid — semicolons not allowed)
variable "region" { type = string; default = "us-east-1" }

# After (valid)
variable "region" {
  type    = string
  default = "us-east-1"
}
```

**Auto-fix all formatting issues at once:**
```bash
terraform fmt -recursive terraform/
terraform fmt -check -recursive terraform/ && echo "All clean"
```

**Lesson learned:** Always run `terraform fmt -recursive terraform/` before committing.
Add `terraform fmt -check` as a CI/CD job that blocks plan runs on bad formatting.

---

### 44. `pre-commit run --all-files` Always Fails `no-commit-to-branch` on Main

**Symptom:**
```
don't commit to branch...Failed
- hook id: no-commit-to-branch
- exit code: 1
```

**Root Cause:** Expected behavior — `--all-files` simulates a commit on the current branch.
When on `main`, the hook correctly fires. This is not a bug.

**Fix:** Not an error. The hook only blocks actual `git commit` on main, not test runs.
- For solo portfolio projects: use `--no-verify` for direct commits to main
- For team projects: always use feature branches

```bash
# Bypass for direct commit to main (solo project only)
git commit --no-verify -m "your message"
```

**Lesson learned:** `pre-commit run --all-files` is for testing hooks, not for committing.
The `no-commit-to-branch` hook works correctly — it will block `git commit` on main.

---

### 45. `terraform_validate` Pre-commit Hook Fails with `-backend` Flag

**Symptom:**
```
Validation failed: terraform/live/prod/40-kubernetes/stacks
Error: Failed to parse command-line flags
flag provided but not defined: -backend
```

**Root Cause:** The `pre-commit-terraform` hook passes flags differently.
Validate args go via `--args`, but init args (like `-backend=false`) go via `--init-args`.

**Fix:** Use `--init-args=-backend=false` not `--args=-backend=false`:
```yaml
# Wrong — passes to terraform validate directly
- id: terraform_validate
  args:
    - --args=-backend=false

# Correct — passes to terraform init
- id: terraform_validate
  args:
    - --init-args=-backend=false
```

**Lesson learned:** Read the pre-commit-terraform hook documentation carefully.
Each hook has its own argument passing convention.

---

### 46. `terraform import` Fails with `zsh: no matches found` on Indexed Resources

**Symptom:**
```
zsh: no matches found: module.iam.aws_iam_role.ebs_csi[0]
```

**Root Cause:** zsh interprets square brackets `[0]` as glob patterns for file matching.
The shell tries to expand `ebs_csi[0]` as a filename glob before passing it to Terraform.

**Fix:** Always wrap resource addresses containing `[index]` in single quotes:
```bash
# Wrong — zsh expands [0] as glob
terraform import module.iam.aws_iam_role.ebs_csi[0] role-name

# Correct — single quotes prevent glob expansion
terraform import 'module.iam.aws_iam_role.ebs_csi[0]' role-name
```

**Lesson learned:** Any Terraform resource address with count or for_each index
must be single-quoted in zsh. This applies to plan, apply, destroy, and state commands too:
```bash
terraform state show 'module.iam.aws_iam_role.ebs_csi[0]'
terraform taint 'module.iam.aws_iam_role.ebs_csi[0]'
```

---

### 47. `terraform init -reconfigure` Wipes Imported State

**Symptom:** After running `terraform import`, a subsequent `terraform init -reconfigure`
causes the imported resource to show as "will be created" in the next plan.

**Root Cause:** `-reconfigure` reinitializes the backend without migrating existing state.
The import IS preserved in S3 remote state, but the local `.terraform` cache is reset,
causing Terraform to re-read remote state fresh — which does reflect the import correctly.
The real issue: import was run BEFORE init, so it wrote to the wrong state location.

**Fix:** Always run import AFTER the final `terraform init`:
```bash
# Correct order — init first, import second
terraform init -reconfigure -backend-config=../backends/backend.hcl
terraform import 'module.iam.aws_iam_role.ebs_csi[0]' churn-mlops-nonprod-ebs-csi-role
terraform plan  # now shows correct diff
```

**Wrong order:**
```bash
terraform import ...          # imports to wrong state location
terraform init -reconfigure   # resets — import appears lost
terraform plan                # shows "will be created" — wrong
```

**Lesson learned:** `terraform init` must always come before `terraform import`.
Treat init as the mandatory first step before any Terraform operation.

---

### 48. `rds_master_user_secret_arn` Output Empty After First Apply

**Symptom:**
```
rds_master_user_secret_arn = ""
```
After applying `manage_master_user_password = true` on RDS.

**Root Cause:** AWS creates the Secrets Manager secret asynchronously after the RDS
modification completes. The `master_user_secret` attribute is an empty list `[]`
during the apply run. Terraform evaluates outputs at the end of apply — the secret
doesn't exist yet at that point.

**Fix — immediate:** Run a second apply after waiting 15-30 seconds:
```bash
terraform apply -var-file=../params/main.tfvars -auto-approve
sleep 20
terraform apply -var-file=../params/main.tfvars -auto-approve
# Second run: AWS has created the secret, ARN is now populated
```

**Fix — permanent:** Use `try()` in the output to avoid plan failure before first apply:
```hcl
# Before (fails if master_user_secret is empty list)
output "master_user_secret_arn" {
  value = aws_db_instance.mlflow.master_user_secret[0].secret_arn
}

# After (returns "" gracefully before secret is created)
output "master_user_secret_arn" {
  value = try(aws_db_instance.mlflow.master_user_secret[0].secret_arn, "")
}
```

**Lesson learned:** AWS async operations don't always complete within the Terraform
apply window. Use `try()` for outputs that reference attributes populated asynchronously.
Always verify with a second apply after async AWS operations.

---

### 49. `50-iam` Stack: IRSA Roles Show as `will be created` After Import

**Symptom:** After importing all three IRSA roles into 50-iam state, `terraform plan`
shows them as new resources to create instead of showing a diff.

**Root Cause:** `terraform init -reconfigure` was run AFTER the import, which reset
the backend configuration and caused Terraform to re-read remote state fresh.
Since the import had written to the correct remote state, the second init should
have preserved it — the real issue was that imports were run before final init.

**Fix:** Correct import order:
```bash
# Step 1 — init first (always)
terraform init -backend-config=../backends/backend.hcl

# Step 2 — import all resources
terraform import 'aws_iam_role.irsa' churn-mlops-nonprod-irsa-role
terraform import 'aws_iam_role.ebs_csi' churn-mlops-nonprod-ebs-csi-role
terraform import 'aws_iam_role.image_updater' churn-mlops-nonprod-image-updater-role

# Step 3 — plan (should show updates, not creates)
terraform plan -var-file=../params/main.tfvars
```

**Verification after import:**
```bash
terraform state list | grep aws_iam_role
# Should show:
# aws_iam_role.ebs_csi
# aws_iam_role.image_updater
# aws_iam_role.irsa
```

**Lesson learned:** Never run `terraform init -reconfigure` after `terraform import`.
The `-reconfigure` flag is for changing backend configuration, not for routine init.

---

### 50. Inline Policies Not Imported with `terraform import` on IAM Role

**Symptom:** After importing IAM roles into 50-iam, `terraform plan` shows inline
policies as `will be created` even though they already exist in AWS.

**Root Cause:** `terraform import` on `aws_iam_role` only imports the role itself —
not its attached managed policies or inline policies. Each policy is a separate
Terraform resource requiring a separate import command.

**Fix — option A:** Let Terraform create the policies (they already exist with same
content → Terraform updates them in-place, no outage):
```bash
terraform apply -var-file=../params/main.tfvars
# Plan shows: 4 to add, 3 to change, 0 to destroy — safe to apply
```

**Fix — option B:** Import each policy separately:
```bash
# Inline policy import format: role-name:policy-name
terraform import 'aws_iam_role_policy.irsa_s3' \
  churn-mlops-nonprod-irsa-role:s3-access
terraform import 'aws_iam_role_policy.irsa_secrets' \
  churn-mlops-nonprod-irsa-role:secrets-access
terraform import 'aws_iam_role_policy.image_updater_ecr' \
  churn-mlops-nonprod-image-updater-role:ecr-read
```

**Lesson learned:** `terraform import` is resource-level, not hierarchy-level.
IAM role import ≠ import of all its policies. Each child resource needs its own import.
For inline policies that match the Terraform config exactly, letting Terraform
"create" them is safe — it actually updates the existing policy in-place.

---

### 51. GitHub Actions Terraform Plan Fails After Scoping CI/CD IAM Role

**Symptom:** After replacing `AdministratorAccess` with scoped policy on
`github-actions-terraform` role, a GitHub Actions run fails with `AccessDenied`.

**Root Cause:** The scoped policy is missing an action that Terraform needs.
Common missing actions: `sts:GetCallerIdentity`, specific `ec2:Describe*` actions,
or `logs:CreateLogGroup` for EKS control plane logging.

**Fix:** Identify the missing action from the error, add it to the policy:
```bash
# Find the specific AccessDenied action in GitHub Actions logs
# Example error:
# Error: User: arn:aws:sts::...:assumed-role/github-actions-terraform/...
# is not authorized to perform: ec2:DescribeAvailabilityZones

# Add missing action to policy document
# Re-create the policy version:
aws iam create-policy-version \
  --policy-arn arn:aws:iam::011528270076:policy/churn-mlops-terraform-ci-policy \
  --policy-document file:///tmp/updated-policy.json \
  --set-as-default
```

**Prevention:** Run `terraform plan` locally with your personal IAM user first
(which has broader permissions) to catch all required actions before switching
the CI/CD role to the scoped policy.

**Lesson learned:** Scope CI/CD IAM policies iteratively — start broad, then tighten.
Use CloudTrail to identify exactly which actions Terraform calls during a full apply.

---

### 52. `dynamodb_table` Deprecation Warning on Every Terraform Command

**Symptom:**
```
Warning: Deprecated Parameter
The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile" instead.
```

**Root Cause:** Terraform 1.10+ introduced native S3 file locking (`use_lockfile = true`)
which replaces DynamoDB-based locking. The `dynamodb_table` parameter still works
but is deprecated.

**Fix:** Update all `backend.hcl` files to use `use_lockfile` instead:
```hcl
# Before (deprecated)
bucket         = "churn-mlops-nonprod-terraform-state"
key            = "nonprod/10-network/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "churn-mlops-nonprod-terraform-locks"
encrypt        = true

# After (current)
bucket       = "churn-mlops-nonprod-terraform-state"
key          = "nonprod/10-network/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
```

**Note:** `use_lockfile` requires Terraform >= 1.10. GitHub Actions runner uses
Terraform 1.9.8 — keep `dynamodb_table` until the runner is upgraded.
The warning is informational only and does not affect functionality.

**Lesson learned:** Pin Terraform version in CI/CD (`TF_VERSION: "1.9.8"`) and
only upgrade after testing locally first. Deprecation warnings are safe to ignore
until you upgrade.

---

## Quick Reference — Phase 20 Commands

```bash
# Terraform single-pass rebuild (new apply order with 50-iam)
export TF_VAR_db_password='YourPassword123!'
cd terraform/live/nonprod/10-network/stacks && terraform apply -var-file=../params/main.tfvars
cd ../20-data/stacks                        && terraform apply -var-file=../params/main.tfvars
cd ../30-compute/stacks                     && terraform apply -var-file=../params/main.tfvars
cd ../40-kubernetes/stacks                  && terraform apply -var-file=../params/main.tfvars
cd ../50-iam/stacks                         && terraform apply -var-file=../params/main.tfvars
# No re-apply needed — 50-iam reads OIDC from 40-kubernetes remote state

# Import existing IAM role into Terraform state (zsh-safe)
terraform import 'aws_iam_role.irsa' churn-mlops-nonprod-irsa-role
terraform import 'aws_iam_role.ebs_csi' churn-mlops-nonprod-ebs-csi-role
terraform import 'aws_iam_role.image_updater' churn-mlops-nonprod-image-updater-role

# Verify RDS secret ARN after manage_master_user_password apply
aws secretsmanager list-secrets \
  --filter Key=name,Values=rds \
  --region us-east-1 \
  --query 'SecretList[*].{Name:Name,ARN:ARN}' \
  --output table

# Check EBS CSI IRSA is wired correctly
aws eks describe-addon \
  --cluster-name churn-mlops-nonprod \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query 'addon.{Status:status,ServiceAccountRoleArn:serviceAccountRoleArn}' \
  --output table

# Verify scoped CI/CD policy is attached
aws iam list-attached-role-policies \
  --role-name github-actions-terraform \
  --query 'AttachedPolicies[*].PolicyName' \
  --output table

# Run pre-commit on all files (test hooks without committing)
pre-commit run --all-files 2>&1 | tail -20

# Fix terraform formatting locally
terraform fmt -recursive terraform/
terraform fmt -check -recursive terraform/ && echo "All clean"

# Clear stale S3 state lock (50-iam stack)
aws s3 rm s3://churn-mlops-nonprod-terraform-state/nonprod/50-iam/terraform.tfstate.tflock
```

---

## Common Recovery Commands

```bash
# Clear stale S3 state lock
aws s3 rm s3://churn-mlops-nonprod-terraform-state/nonprod/<stack>/terraform.tfstate.tflock

# Force unlock local state
rm -f terraform/live/nonprod/00-s3-backend/stacks/.terraform.tfstate.lock.info

# Scale EKS nodes
aws eks update-nodegroup-config \
  --cluster-name churn-mlops-nonprod \
  --nodegroup-name churn-mlops-nonprod-node-group \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --region us-east-1

# Promote stuck Argo Rollouts canary
kubectl argo rollouts promote churn-prediction-api -n churn-mlops

# Abort stuck rollout
kubectl argo rollouts abort churn-prediction-api -n churn-mlops
kubectl argo rollouts undo churn-prediction-api -n churn-mlops

# Refresh ECR credentials for Image Updater (expires every 12h)
AWS_ACCOUNT=011528270ువు REGION=us-east-1
ECR_TOKEN=$(aws ecr get-authorization-token --region $REGION \
  --query 'authorizationData[0].authorizationToken' \
  --output text | base64 -d | cut -d: -f2)
kubectl create secret docker-registry ecr-creds \
  --docker-server=${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com \
  --docker-username=AWS --docker-password=${ECR_TOKEN} \
  -n argocd --dry-run=client -o yaml | kubectl apply -f -

# Restart Image Updater after config change
kubectl rollout restart deployment argocd-image-updater-controller -n argocd

# Check Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20

# Delete Helm-Argo Rollouts conflicting resources before upgrade
kubectl delete destinationrule churn-prediction-api-destrule -n churn-mlops 2>/dev/null || true
kubectl delete virtualservice churn-prediction-api-vsvc -n churn-mlops 2>/dev/null || true
```
---

# Phase 21 — Distributed Training (Ray + Karpenter) Troubleshooting

Real issues encountered during Phase 21 implementation.
Append these entries to your main `troubleshooting.md` before the `## Quick Reference` section.

---

### 53. `ray.train.sklearn.SklearnTrainer` — ModuleNotFoundError

**Symptom:**
```
ModuleNotFoundError: No module named 'ray.train.sklearn'
```

**Root Cause:** `ray.train.sklearn.SklearnTrainer` existed only in Ray 1.x.
Ray 2.x removed it — the correct pattern is `@ray.remote` functions for sklearn models.

**Fix:** Remove the import and use `@ray.remote` decorated functions directly:
```python
# Wrong (Ray 1.x only)
from ray.train.sklearn import SklearnTrainer

# Correct (Ray 2.x)
@ray.remote
def train_worker(worker_id, data, params):
    from sklearn.ensemble import RandomForestClassifier
    model = RandomForestClassifier(**params)
    model.fit(X, y)
    return model
```

**Lesson learned:** Always check Ray version compatibility. Ray 2.x is a major API break from 1.x.
Check available modules: `python -c "import ray.train; print(dir(ray.train))"`

---

### 54. Ray Tune CPU Deadlock on t3.medium

**Symptom:**
```
Warning: The following resource request cannot be scheduled right now: {'CPU': 1.0}
Trial status: 3 RUNNING — stuck for 7+ minutes
```

**Root Cause:** Passing entire DataFrames (5634 rows x 19 cols x 2 splits) as config dicts
caused massive serialization overhead in Ray's object store. Each trial consumed
all available CPU deserializing data instead of training.

**Fix:** Load data from S3 directly inside each trial function — not through config:
```python
# Wrong — serializes 2MB+ DataFrame through Ray object store
search_space = {
    "train_data": train_df.to_dict(),   # 2MB per trial x 20 trials = 40MB
    "test_data": test_df.to_dict(),
}

# Correct — each trial loads its own data (~0.5s S3 read)
search_space = {
    "s3_bucket": "churn-mlops-nonprod-artifacts",
    "s3_key": "data/raw/churn.csv",
}
# Inside trial function:
obj = s3.get_object(Bucket=config["s3_bucket"], Key=config["s3_key"])
df = pd.read_csv(io.BytesIO(obj["Body"].read()))
```

**Lesson learned:** Never pass large DataFrames through Ray Tune config.
Ray serializes config to every trial worker — at scale this causes network and memory saturation.

---

### 55. Ray Worker OOM Kill on t3.medium (768Mi limit)

**Symptom:**
```
ray.exceptions.OutOfMemoryError: Task was killed due to the node running low on memory.
Memory on the node: 0.72GB / 0.75GB (0.95489), which exceeds threshold of 0.95
```

**Root Cause:** Ray pods had 768Mi memory limit. Ray's own processes
(dashboard, GCS, autoscaler, raylet) consumed 0.53GB, leaving only 220MB for tasks.
Any task allocation triggered Ray's OOM killer at 95% threshold.

**Fix (temporary):** Disable Ray OOM monitor via env var:
```yaml
env:
  - name: RAY_memory_monitor_refresh_ms
    value: "0"
  - name: RAY_DISABLE_MEMORY_MONITOR
    value: "1"
```

**Fix (proper):** Use Karpenter to provision memory-optimized nodes (r6i.large = 16GB RAM)
instead of squeezing Ray into t3.medium nodes already running 60+ pods.

**Lesson learned:** t3.medium (3.8GB RAM) with 60+ existing pods has ~0.75GB available
for Ray. Ray needs minimum 2GB to run head + 1 task comfortably. Always provision
dedicated nodes for Ray workloads.

---

### 56. Karpenter CrashLoopBackOff — SQS Queue Not Found

**Symptom:**
```
panic: operation error SQS: GetQueueUrl
AWS.SimpleQueueService.NonExistentQueue: The specified queue does not exist
```

**Root Cause:** Karpenter requires an SQS queue for EC2 spot interruption handling.
The `--set settings.interruptionQueue=churn-mlops-nonprod` flag was passed during
Helm install but the SQS queue did not exist.

**Fix:** Create the SQS queue before installing Karpenter:
```bash
aws sqs create-queue \
  --queue-name churn-mlops-nonprod \
  --region us-east-1 \
  --attributes '{"MessageRetentionPeriod": "300"}'
```

Also add SQS permissions to Karpenter IAM role:
```json
{
  "Action": ["sqs:DeleteMessage", "sqs:GetQueueAttributes",
             "sqs:GetQueueUrl", "sqs:ReceiveMessage"],
  "Resource": "arn:aws:sqs:us-east-1:011528270076:churn-mlops-nonprod"
}
```

**Lesson learned:** Karpenter's interruption queue is mandatory even for non-SPOT workloads.
Create it as part of the Karpenter IAM setup, not after Helm install.

---

### 57. Karpenter EC2NodeClass `InstanceProfileReady=Unknown` — IAM Permission Missing

**Symptom:**
```
AccessDenied: User: arn:aws:sts::...:assumed-role/churn-mlops-nonprod-karpenter-role/...
is not authorized to perform: iam:CreateInstanceProfile
```

**Root Cause:** The Karpenter controller policy had `iam:CreateInstanceProfile` in
a conditional statement requiring specific resource tags. Karpenter tries to create
the instance profile before tags exist, so the condition never matches.

**Fix:** Add unconditional `iam:CreateInstanceProfile` as an inline policy:
```bash
aws iam put-role-policy \
  --role-name churn-mlops-nonprod-karpenter-role \
  --policy-name karpenter-iam-fix \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile"
      ],
      "Resource": "*"
    }]
  }'

# Restart Karpenter to pick up new permissions
kubectl rollout restart deployment karpenter -n karpenter
```

**Lesson learned:** IAM policy propagation takes 10-30 seconds. After adding permissions,
always restart the pod to force IRSA token refresh.

---

### 58. Ray Worker Pod Stuck in `Init:0/1` — GCS Port 6379 Blocked

**Symptom:**
```
ray.exceptions.RpcError: RPC Error message: Deadline Exceeded
Failed to connect to GCS at address churn-ray-cluster-head-svc.ray-system.svc.cluster.local:6379
```

**Root Cause:** The Ray head node (on existing EKS node) and the Ray worker
(on Karpenter-provisioned node) had different security groups:
- Existing EKS node: `sg-0ee94d71ee1bfe45c` (EKS cluster SG — allows all internal traffic)
- Karpenter node: `sg-03b45698e809841f0` (EKS nodes SG — self-referencing only)

The self-referencing rule only allows traffic within the same SG. Cross-SG traffic
on port 6379 was blocked.

**Diagnosis:**
```bash
# Check which SG each node has
aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=<node-ip>" \
  --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId'

# Test port connectivity
kubectl exec -n ray-system $HEAD_POD -- \
  timeout 5 bash -c "echo > /dev/tcp/<worker-ip>/6379" && echo "OPEN" || echo "BLOCKED"
```

**Fix:** Add the EKS cluster SG to the Karpenter EC2NodeClass:
```yaml
securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: churn-mlops-nonprod
  # Also include EKS cluster SG — existing nodes have this SG
  # which allows all internal cluster traffic including Ray GCS port 6379
  - id: sg-0ee94d71ee1bfe45c
```

**Lesson learned:** Karpenter nodes only get SGs matching `securityGroupSelectorTerms`.
Always include the EKS cluster SG so Karpenter nodes can communicate with existing
nodes on all ports. The nodes SG self-referencing rule does NOT cover cross-SG traffic.

---

### 59. Ray Tune Trial Stuck for 14+ Minutes — `max_depth=None`

**Symptom:** First Ray Tune trial runs for 14+ minutes with near-zero CPU usage.

**Root Cause:** `max_depth=None` in the search space means unlimited tree depth.
RandomForest with 100 estimators and unlimited depth on 5634 samples creates
extremely deep trees that can take hours to train on a single CPU.

**Fix:** Remove `None` from `max_depth` choices:
```python
# Wrong — None causes unbounded tree depth, can run indefinitely
"max_depth": tune.choice([5, 10, 15, 20, None])

# Correct — all depths are bounded
"max_depth": tune.choice([5, 10, 15, 20, 25])
```

**Lesson learned:** Always bound hyperparameter search spaces. Unbounded values
like `max_depth=None` can cause individual trials to run indefinitely, blocking
all subsequent trials when `MAX_CONCURRENT=1`.

---

### 60. MLflow `log_model()` — `name` Parameter Not Found

**Symptom:**
```
TypeError: log_model() got an unexpected keyword argument 'name'
```

**Root Cause:** The `name` parameter was renamed to `artifact_path` in MLflow 2.x.

**Fix:**
```python
# Wrong (MLflow 1.x)
mlflow.sklearn.log_model(model, name="distributed_random_forest")

# Correct (MLflow 2.x)
mlflow.sklearn.log_model(model, artifact_path="distributed_random_forest")
```

**Lesson learned:** MLflow 2.x has several breaking API changes from 1.x.
Key changes:
- `name` -> `artifact_path` in `log_model()`
- Model stages deprecated -> use aliases instead
- `transition_model_version_stage()` -> `set_registered_model_alias()`

---

### 61. MLflow Server Down After RDS Password Rotation

**Symptom:**
```
psycopg2.OperationalError: FATAL: password authentication failed for user "mlflow"
```
MLflow EC2 systemd service fails. EC2 is running but MLflow health check times out.

**Root Cause:** After enabling `manage_master_user_password = true` on RDS,
AWS generates a new password in Secrets Manager. The EC2 `/opt/mlflow/start.sh`
still had the old hardcoded password.

**Fix:** Update `/opt/mlflow/start.sh` via SSM to fetch password dynamically:
```bash
export PATH=$PATH:/usr/local/sessionmanagerplugin/bin
aws ssm start-session --target i-063cfab3185b59739 --region us-east-1

# Inside EC2:
cat > /opt/mlflow/start.sh << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/home/ec2-user/.local/bin
export AWS_DEFAULT_REGION=us-east-1

DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "<SECRET_ARN>" \
  --region us-east-1 \
  --query SecretString \
  --output text)

DB_PASSWORD=$(echo $DB_SECRET | python3 -c "
import sys, json, urllib.parse
secret = json.load(sys.stdin)
print(urllib.parse.quote(secret['password'], safe=''))
")
DB_USERNAME=$(echo $DB_SECRET | python3 -c "
import sys, json; print(json.load(sys.stdin)['username'])
")

mlflow server \
  --backend-store-uri "postgresql://${DB_USERNAME}:${DB_PASSWORD}@<RDS_ENDPOINT>:5432/mlflow" \
  --default-artifact-root s3://churn-mlops-nonprod-artifacts \
  --host 0.0.0.0 --port 5000 \
  --gunicorn-opts "--timeout 120 -w 2"
SCRIPT

chmod +x /opt/mlflow/start.sh
sudo systemctl restart mlflow
```

**Lesson learned:** `manage_master_user_password = true` rotates the RDS password every 7 days.
MLflow startup MUST fetch the password dynamically. Always URL-encode — AWS passwords
contain special characters that break PostgreSQL connection URIs.

---

### 62. MLflow PostgreSQL `Invalid IPv6 URL` Error

**Symptom:**
```
ValueError: Invalid IPv6 URL
```

**Root Cause:** Secrets Manager-generated passwords contain special characters
(`!`, `@`, `/`) that PostgreSQL URI parser interprets as URL delimiters.
Example: password `abc!def@ghi` breaks `postgresql://mlflow:abc!def@ghi@hostname/db`
because `@ghi@hostname` is parsed as an IPv6 address.

**Fix:** URL-encode the password using `urllib.parse.quote()`:
```python
import urllib.parse
encoded_password = urllib.parse.quote(raw_password, safe='')
# "abc!def@ghi" -> "abc%21def%40ghi"
```

**Lesson learned:** Always URL-encode database passwords in connection strings.
Never build PostgreSQL URIs with raw passwords from Secrets Manager.

---

### 63. Ray IRSA `NoCredentialsError` — Wrong Namespace in Trust Policy

**Symptom:**
```
botocore.exceptions.NoCredentialsError: Unable to locate credentials
```

**Root Cause:** The IRSA trust policy was scoped to `churn-mlops:churn-prediction-sa`
but Ray pods run in `ray-system` namespace using `ray-worker-sa` ServiceAccount.

**Fix 1:** Update trust policy to include Ray ServiceAccount:
```json
"Condition": {
  "StringLike": {
    "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:sub": [
      "system:serviceaccount:churn-mlops:churn-prediction-sa",
      "system:serviceaccount:ray-system:ray-worker-sa"
    ]
  }
}
```

**Fix 2:** Create dedicated ServiceAccount with IRSA annotation in `ray-system`:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ray-worker-sa
  namespace: ray-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::011528270076:role/churn-mlops-nonprod-irsa-role
```

**Fix 3:** Reference in RayCluster spec:
```yaml
spec:
  headGroupSpec:
    template:
      spec:
        serviceAccountName: ray-worker-sa
```

**Verify IRSA injection:**
```bash
kubectl exec -n ray-system $POD -- env | grep AWS_ROLE_ARN
# Must show: AWS_ROLE_ARN=arn:aws:iam::...:role/churn-mlops-nonprod-irsa-role
```

---

### 64. Ray Head Pod OOM Killed During Training (Exit Code 137)

**Symptom:**
```
command terminated with exit code 137
```

**Root Cause:** Exit code 137 = OOM kill (SIGKILL). Head pod had 768Mi limit.
Driver process uses ~200MB + Ray head processes = total exceeds limit.

**Fix:** Increase head pod memory limit:
```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "1"
    memory: "2Gi"   # increased from 768Mi
```

**Ray head memory budget:**
- GCS server: ~100MB
- Dashboard: ~60MB
- Autoscaler: ~40MB
- Raylet: ~60MB
- Driver process: ~200MB
- Total minimum: ~500MB — allocate 2Gi for comfortable operation

---

## Phase 21 — Quick Reference Commands

```bash
# ── Ray cluster ───────────────────────────────────────────────────────────
HEAD_POD=$(kubectl get pod -n ray-system -l component=head \
  -o jsonpath='{.items[0].metadata.name}')
WORKER_POD=$(kubectl get pod -n ray-system -l component=worker \
  -o jsonpath='{.items[0].metadata.name}')

# Check cluster status
kubectl exec -n ray-system $HEAD_POD -- ray status

# Run distributed training
kubectl cp src/distributed_training.py ray-system/$HEAD_POD:/tmp/distributed_training.py
kubectl exec -n ray-system $HEAD_POD -- python /tmp/distributed_training.py

# Test MLflow reachable from Ray
kubectl exec -n ray-system $HEAD_POD -- python -c "
import urllib.request
r = urllib.request.urlopen('http://10.1.1.233:5000/health', timeout=5)
print('MLflow OK:', r.read())"

# Test GCS port from worker
kubectl exec -n ray-system $WORKER_POD -- \
  timeout 5 bash -c "echo > /dev/tcp/<head-ip>/6379" && echo "OPEN" || echo "BLOCKED"

# Check IRSA credentials
kubectl exec -n ray-system $HEAD_POD -- env | grep AWS_ROLE_ARN

# ── Karpenter ─────────────────────────────────────────────────────────────
kubectl get nodepool
kubectl get ec2nodeclass
kubectl get nodeclaims
kubectl get nodes -l karpenter.sh/nodepool=ray-workloads
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20 \
  | grep -i "error\|launched\|terminated"

# ── MLflow recovery ───────────────────────────────────────────────────────
export PATH=$PATH:/usr/local/sessionmanagerplugin/bin
aws ssm start-session --target i-063cfab3185b59739 --region us-east-1
# Inside EC2:
# sudo systemctl restart mlflow
# sudo systemctl status mlflow --no-pager | tail -5

# Get RDS secret ARN
aws secretsmanager list-secrets \
  --filter Key=name,Values=rds \
  --region us-east-1 \
  --query 'SecretList[*].{Name:Name,ARN:ARN}' \
  --output table

# ── Restart Ray cluster ───────────────────────────────────────────────────
kubectl delete pod -n ray-system -l ray.io/cluster=churn-ray-cluster
kubectl get pods -n ray-system -w

# Scale Ray workers
kubectl patch raycluster churn-ray-cluster -n ray-system \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/workerGroupSpecs/0/replicas","value":2}]'
```
---
# Phase 22 — KEDA Event-Driven Autoscaling Troubleshooting

Append these entries to your main `troubleshooting.md` before the `## Quick Reference` section.

---

### 65. KEDA ScaledObject `Ready=False` — `scaleTargetRef` Missing apiVersion/kind

**Symptom:**
```
Message: ScaledObject doesn't have correct scaleTargetRef specification
Reason:  ScaledObjectCheckFailed
Status:  False
```

**Root Cause:** KEDA admission webhook requires explicit `apiVersion` and `kind`
in `scaleTargetRef` when it cannot auto-detect the resource type.

**Fix:**
```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1        # required — do not omit
    kind: Deployment
    name: churn-stream-processor
```

**Lesson learned:** Always specify `apiVersion` and `kind` in `scaleTargetRef`.
KEDA supports Deployments, StatefulSets, and custom resources (Argo Rollouts).

---

### 66. KEDA Cannot Manage Argo Rollout — Already Managed by HPA

**Symptom:**
```
admission webhook "vscaledobject.kb.io" denied the request:
the workload 'churn-prediction-api' of type 'argoproj.io/v1alpha1.Rollout'
is already managed by the hpa 'churn-prediction-api'
```

**Root Cause:** The Helm chart had `autoscaling.enabled: true` which created a
CPU-based HPA for the Argo Rollout. KEDA refuses to manage a resource already
owned by another HPA — two controllers would conflict.

**Fix (3 steps):**

Step 1 — Disable HPA in Helm values:
```yaml
# helm/churn-mlops/values.yaml
autoscaling:
  enabled: false    # KEDA manages scaling via ScaledObject
```

Step 2 — Push to Git and force ArgoCD sync (ArgoCD recreates the HPA from Git):
```bash
git add helm/churn-mlops/values.yaml
git push origin main

kubectl annotate application churn-prediction-api -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

Step 3 — Wait for ArgoCD to delete the HPA, then apply ScaledObject:
```bash
kubectl get hpa -n churn-mlops   # verify HPA is gone
kubectl apply -f k8s/keda/scaledobject-prediction-api.yaml
```

**Lesson learned:** Never manually delete resources managed by ArgoCD — it
recreates them immediately from Git. Always update Git first and let ArgoCD sync.
KEDA and Helm-managed HPAs cannot coexist on the same target.

---

### 67. Stream Processor Stuck in Pending — t3.medium 17-Pod ENI Limit

**Symptom:**
```
0/5 nodes are available: 1 Insufficient cpu, 1 node(s) had untolerated taint(s),
3 Too many pods.
```

**Root Cause:** AWS t3.medium supports maximum 17 pods per node (ENI limit).
All 4 existing nodes were at capacity. The Karpenter `ray-workloads` NodePool
has `workload-type=ray:NoSchedule` taint — general workloads can't schedule there.

**Fix:** Add a general-purpose Karpenter NodePool without taints:
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general-purpose
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: churn-mlops-nodeclass   # reuse same EC2NodeClass
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

**Lesson learned:** AWS ENI limits cap pods per node regardless of CPU/memory.
t3.medium = 17 pods, t3.large = 35, r6i.large = 58. Always plan for pod density
limits when running many small services. Karpenter general-purpose NodePool
handles overflow automatically.

---

### 68. KEDA Kafka Scaler — Lag Not Increasing Despite Messages Published

**Symptom:** Published 500 messages via `kafka-console-producer.sh` loop but
lag only shows 8-10 messages. KEDA doesn't scale beyond current replicas.

**Root Cause:** `kafka-console-producer.sh` loop opens a new TCP connection
per message — extremely slow. The stream processor was consuming messages
faster than they were being produced, keeping lag low.

**Fix:** Pipe all messages in a single producer connection:
```bash
# Wrong — new connection per message, very slow
for i in $(seq 1 500); do
  echo "message-$i" | kafka-console-producer.sh --bootstrap-server ... --topic ...
done

# Correct — single connection, all messages sent at once
for i in $(seq 1 2000); do
  echo "{\"customerID\":\"$i\",...}"
done | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic customer-events
```

**Lesson learned:** For load testing Kafka, always pipe messages through a
single producer connection. Each connection has ~50ms overhead — 500 connections
= 25 seconds just for connection setup, during which the consumer catches up.

---

### 69. Kafka Consumer Group Shows Only 1 Consumer After Scaling to 3 Pods

**Symptom:** KEDA scaled stream-processor to 3 pods but `kafka-consumer-groups.sh`
shows only 1 active consumer-id consuming all 3 partitions.

**Root Cause:** Kafka rebalance takes 10-30 seconds after new consumer joins.
During rebalance, the existing consumer temporarily handles all partitions.
After rebalance completes, partitions are distributed 1:1 to consumers.

**Expected behavior after rebalance:**
```
Partition 0 → consumer pod 1 (10.1.2.42)
Partition 1 → consumer pod 2 (10.1.3.157)
Partition 2 → consumer pod 3 (10.1.3.197)
```

**Lesson learned:** Kafka partition rebalance is triggered when consumers
join or leave a consumer group. Maximum parallelism = number of partitions.
Having more consumers than partitions wastes resources — idle consumers
receive no messages. Plan partition count based on max expected consumers.

---

### 70. KEDA Scales to 5 Pods but Only 3 Consume — Partition Limit

**Symptom:** KEDA scaled `stream-processor` to 5 pods (maxReplicaCount).
`kafka-consumer-groups.sh` shows only 3 active consumers, 2 pods are idle.

**Root Cause:** `customer-events` topic has 3 partitions. Kafka assigns
at most 1 partition per consumer in a consumer group. With 3 partitions
and 5 consumers, 2 consumers receive no partition assignment and are idle.

**Fix:** Increase partition count to match maxReplicaCount:
```bash
kubectl edit kafkatopic customer-events -n kafka
# spec.partitions: 3 → 5
```

**Warning:** Kafka partition count can only be increased, never decreased.
Plan partition count carefully — it's a permanent architectural decision.

**Rule of thumb:** `partitions >= maxReplicaCount` for full parallelism.
For your setup: `maxReplicaCount=5` → `partitions=5` minimum.

**Lesson learned:** KEDA calculates desired replicas from total lag regardless
of partition count. Always set `partitions >= maxReplicaCount` to avoid
idle consumer pods wasting resources.

---

## Phase 22 — Quick Reference Commands

```bash
# ── KEDA status ───────────────────────────────────────────────────────────
kubectl get scaledobject -n churn-mlops
kubectl get hpa -n churn-mlops
kubectl describe scaledobject stream-processor-scaler -n churn-mlops | grep -A 10 "Conditions:"

# ── Kafka consumer lag ────────────────────────────────────────────────────
kubectl exec -n kafka churn-kafka-combined-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group churn-stream-processor 2>/dev/null

# ── Produce test messages (batch — single connection) ─────────────────────
kubectl exec -n kafka churn-kafka-combined-0 -- bash -c '
for i in $(seq 1 2000); do
  echo "{\"customerID\":\"test-$i\",\"tenure\":12,\"MonthlyCharges\":65.5,\"TotalCharges\":786.0,\"Contract\":\"Month-to-month\",\"InternetService\":\"Fiber optic\",\"PaymentMethod\":\"Electronic check\"}"
done | bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic customer-events
echo "Published 2000 messages"'

# ── Watch KEDA scaling live ───────────────────────────────────────────────
watch -n 2 "
echo '── LAG ──'
kubectl exec -n kafka churn-kafka-combined-0 -- \
  bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group churn-stream-processor 2>/dev/null

echo '── HPA ──'
kubectl get hpa keda-hpa-stream-processor-scaler -n churn-mlops

echo '── PODS ──'
kubectl get pods -n churn-mlops --no-headers | grep stream
"

# ── Check KEDA operator logs ──────────────────────────────────────────────
kubectl logs -n keda \
  $(kubectl get pod -n keda -l app=keda-operator -o jsonpath='{.items[0].metadata.name}') \
  --tail=20 | grep -i "error\|scaled\|trigger"

# ── Manually pause ScaledObject (maintenance) ─────────────────────────────
kubectl patch scaledobject stream-processor-scaler -n churn-mlops \
  --type merge -p '{"spec":{"paused":true}}'

# ── Resume ScaledObject ───────────────────────────────────────────────────
kubectl patch scaledobject stream-processor-scaler -n churn-mlops \
  --type merge -p '{"spec":{"paused":false}}'

# ── Check Karpenter general-purpose NodePool ──────────────────────────────
kubectl get nodepool general-purpose
kubectl get nodes -l karpenter.sh/nodepool=general-purpose

# ── KEDA + ArgoCD ─────────────────────────────────────────────────────────
kubectl get application keda-config -n argocd
kubectl get application karpenter-config -n argocd
```

---
# Phase 23 — Observability (Loki + Tempo) Troubleshooting

Append these entries to your main `troubleshooting.md` before the `## Quick Reference` section.

---

### 71. Loki 7.x Installation Fails — `deploymentMode` Conflict

**Symptom:**
```
Error: execution error at (loki/templates/validate.yaml:31:4):
You have more than zero replicas configured for both the single binary
and simple scalable targets.
```

**Root Cause:** Loki 7.x requires explicitly zeroing out SimpleScalable
components when using SingleBinary mode. The chart defaults have conflicting
replica counts.

**Fix:** Add explicit zero replicas for SimpleScalable components:
```yaml
deploymentMode: SingleBinary

# Required by Loki 7.x — explicitly disable SimpleScalable components
read:
    replicas: 0
write:
    replicas: 0
backend:
    replicas: 0
```

**Lesson learned:** Loki 7.x is stricter than 6.x — use `grafana/loki-stack`
v2.10.3 for simpler single-node deployments. The `loki-stack` chart bundles
Loki + Promtail with sane defaults and no validation conflicts.

---

### 72. Promtail DaemonSet Pods Stuck Pending — Node Pod Limit (ENI)

**Symptom:**
```
Warning FailedScheduling: 0/7 nodes are available:
1 Too many pods, 6 node(s) didn't satisfy plugin(s) [NodeAffinity]
```

**Root Cause:** DaemonSet pods must run on every node. When a node hits the
AWS ENI pod limit (17 pods for t3.medium), the DaemonSet pod for that node
can't schedule — even if other nodes have capacity.

**Fix:** Recycle the full node to free a pod slot:
```bash
# Identify full node
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get pods -A --field-selector spec.nodeName=$node --no-headers | wc -l)
  limit=$(kubectl get node $node -o jsonpath='{.status.allocatable.pods}')
  echo "$node: $count/$limit"
done

# Cordon + drain + terminate full node
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force
INSTANCE_ID=$(kubectl get node <node-name> \
  -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-east-1
```

**Long-term fix:** Enable prefix delegation (17 → 110 pods/node):
```bash
kubectl set env daemonset aws-node -n kube-system \
  ENABLE_PREFIX_DELEGATION=true \
  WARM_PREFIX_TARGET=1
kubectl rollout restart daemonset aws-node -n kube-system
```

**Note:** Existing nodes keep old limit until recycled. New nodes pick up
prefix delegation automatically.

---

### 73. EKS Node Group `CREATE_FAILED` — Invalid Launch Template UserData

**Symptom:**
```
Ec2LaunchTemplateInvalidConfiguration:
User data was not in the MIME multipart format.
```

**Root Cause:** AL2023 AMI uses `nodeadm` YAML format for bootstrap, not the
old bash script format used by AL2 (`/etc/eks/bootstrap.sh`). Adding a launch
template with bash user_data breaks AL2023 node initialization.

**AL2 (old) bootstrap format:**
```bash
#!/bin/bash
/etc/eks/bootstrap.sh <cluster-name> \
  --use-max-pods false \
  --kubelet-extra-args '--max-pods=110'
```

**AL2023 (new) bootstrap format — MIME multipart:**
```
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  kubelet:
    config:
      maxPods: 110
--==BOUNDARY==--
```

**Fix (immediate):** Delete the failed node group and recreate without launch template:
```bash
aws eks delete-nodegroup \
  --cluster-name <cluster> \
  --nodegroup-name <nodegroup> \
  --region us-east-1

# Wait for deletion
aws eks wait nodegroup-deleted \
  --cluster-name <cluster> \
  --nodegroup-name <nodegroup> \
  --region us-east-1

# Recreate without launch template
aws eks create-nodegroup \
  --cluster-name <cluster> \
  --nodegroup-name <nodegroup> \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --instance-types t3.medium \
  --node-role <node-role-arn> \
  --subnets <subnet-ids> \
  --capacity-type SPOT \
  --ami-type AL2023_x86_64_STANDARD \
  --region us-east-1
```

**Lesson learned:** Never use AL2 bash bootstrap scripts with AL2023 AMI.
Check AMI type before adding launch template user_data. AL2023 is the default
for EKS 1.29+ and requires MIME multipart format.

---

### 74. Terraform State Lock Stuck After Failed Plan

**Symptom:**
```
Error: Error acquiring the state lock
ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID: <uuid>
  Operation: OperationTypePlan
```

**Root Cause:** A previous `terraform plan` or `terraform apply` failed or
was interrupted, leaving a lock entry in DynamoDB. Terraform uses DynamoDB
for distributed locking to prevent concurrent state modifications.

**Fix Option 1 — terraform force-unlock:**
```bash
terraform force-unlock -force <lock-id-from-error-message>
```

**Fix Option 2 — delete DynamoDB lock directly:**
```bash
# List all locks
aws dynamodb scan \
  --table-name <terraform-lock-table> \
  --query 'Items[*].LockID.S' \
  --output text

# Delete specific lock
aws dynamodb delete-item \
  --table-name <terraform-lock-table> \
  --key '{"LockID": {"S": "<state-path>/terraform.tfstate"}}' \
  --region us-east-1
```

**When to use Option 2:** When the lock ID in the error doesn't match what
`force-unlock` expects (happens when multiple failed attempts create new locks).

**Lesson learned:** Always check for stale locks before running Terraform in
a shared environment. Set up lock timeout in backend config:
```hcl
backend "s3" {
  dynamodb_table = "terraform-locks"
  # Locks auto-expire after 10 minutes if not explicitly released
}
```

---

### 75. EKS Node Group Subnets Don't Belong to Cluster VPC

**Symptom:**
```
InvalidParameterException: Subnets specified must belong to the VPC: vpc-xxx
```

**Root Cause:** The subnets stored in memory/notes were from a different cluster
or VPC. The cluster was recreated in a new VPC but the old subnet IDs were used.

**Fix:** Always get subnets from the cluster itself:
```bash
aws eks describe-cluster \
  --name <cluster-name> \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.{VPC:vpcId,Subnets:subnetIds}' \
  --output json
```

**Lesson learned:** Never hardcode subnet/VPC IDs. Always query them dynamically
from the cluster or Terraform outputs. Add them to a central config file:
```bash
# Get and save cluster network config
aws eks describe-cluster --name $CLUSTER \
  --query 'cluster.resourcesVpcConfig' > cluster-network.json
```

---

### 76. Tempo Datasource — Grafana Shows `Tempo` but No Traces

**Symptom:** Tempo datasource added successfully in Grafana but no traces appear
when searching. TraceQL queries return empty results.

**Root Cause:** No services are instrumented with OpenTelemetry yet. Tempo
receives traces via push (OTLP protocol) — it only has data if something sends
traces to it. Unlike Prometheus (which scrapes), Tempo is passive.

**Fix:** Instrument services with OpenTelemetry SDK:
```python
# FastAPI example
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="http://tempo.monitoring:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
```

**Or use OpenTelemetry Collector as a sidecar/DaemonSet** to collect traces
from multiple services and forward to Tempo.

**Verify Tempo is receiving traces:**
```bash
kubectl logs -n monitoring tempo-0 --tail=20 | grep -i "received\|traces\|push"
```

---

## Phase 23 — Quick Reference Commands

```bash
# ── Loki status ───────────────────────────────────────────────────────────
kubectl get pods -n monitoring | grep -E "loki|promtail"
kubectl logs -n monitoring loki-0 --tail=10
kubectl logs -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=promtail \
  -o jsonpath='{.items[0].metadata.name}') --tail=10

# ── Query logs via Loki API ───────────────────────────────────────────────
LOKI_IP=$(kubectl get svc loki -n monitoring -o jsonpath='{.spec.clusterIP}')
curl -G "http://$LOKI_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="churn-mlops"}' \
  --data-urlencode 'limit=5'

# ── Tempo status ──────────────────────────────────────────────────────────
kubectl get pods -n monitoring | grep tempo
kubectl logs -n monitoring tempo-0 --tail=10

# ── Grafana datasources ───────────────────────────────────────────────────
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -s http://$GRAFANA_URL/api/datasources \
  -u admin:admin123 | python3 -m json.tool | grep -E "name|type|url"

# ── Add Loki datasource (after cluster rebuild) ───────────────────────────
curl -s -X POST http://$GRAFANA_URL/api/datasources \
  -H "Content-Type: application/json" -u "admin:admin123" \
  -d '{"name":"Loki","type":"loki","url":"http://loki:3100","access":"proxy","isDefault":false}'

# ── Add Tempo datasource (after cluster rebuild) ──────────────────────────
curl -s -X POST http://$GRAFANA_URL/api/datasources \
  -H "Content-Type: application/json" -u "admin:admin123" \
  -d '{"name":"Tempo","type":"tempo","url":"http://tempo:3100","access":"proxy","isDefault":false}'

# ── Node group recovery ───────────────────────────────────────────────────
# Get cluster subnets
aws eks describe-cluster --name churn-mlops-nonprod --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.{VPC:vpcId,Subnets:subnetIds}'

# Recreate node group
aws eks create-nodegroup \
  --cluster-name churn-mlops-nonprod \
  --nodegroup-name churn-mlops-nonprod-node-group \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --instance-types t3.medium \
  --node-role arn:aws:iam::011528270076:role/churn-mlops-nonprod-eks-node-role \
  --subnets subnet-0019307f263563bc8 subnet-0f3f3c198af07b34b \
  --capacity-type SPOT \
  --ami-type AL2023_x86_64_STANDARD \
  --region us-east-1

# ── Terraform state lock cleanup ──────────────────────────────────────────
aws dynamodb delete-item \
  --table-name churn-mlops-nonprod-terraform-locks \
  --key '{"LockID":{"S":"churn-mlops-nonprod-terraform-state/nonprod/40-kubernetes/terraform.tfstate"}}' \
  --region us-east-1
```

*This document was built iteratively throughout the project — every error was a learning opportunity.*

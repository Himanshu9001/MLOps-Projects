# 🔧 Troubleshooting Guide — Issues Faced & Solutions

A comprehensive log of every issue encountered during the MLOps project setup, with root cause analysis and solutions. This serves as a reference for future debugging and learning.

---

## Table of Contents

1. [Python Virtual Environment Issues](#1-python-virtual-environment-issues)
2. [DVC Issues](#2-dvc-issues)
3. [MLflow Issues](#3-mlflow-issues)
4. [Docker Issues](#4-docker-issues)
5. [FastAPI Issues](#5-fastapi-issues)
6. [CI/CD Issues](#6-cicd-issues)
7. [AWS Infrastructure Issues](#7-aws-infrastructure-issues)
8. [Kubernetes Issues](#8-kubernetes-issues)
9. [Helm Issues](#9-helm-issues)
10. [Prometheus & Grafana Issues](#10-prometheus--grafana-issues)
11. [Evidently AI Issues](#11-evidently-ai-issues)

---

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

*This document was built iteratively throughout the project — every error was a learning opportunity.*
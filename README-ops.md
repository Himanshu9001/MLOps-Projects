
## Daily Cluster Rebuild Sequence (New Terraform Cluster)

Every time you delete and rebuild the nonprod cluster:

### Step 1 — Start MLflow infrastructure
```bash
./scripts/setup-mlflow-infra.sh
```

### Step 2 — Apply Terraform stacks
```bash
# Set password
export TF_VAR_db_password="MLflow1234!"

cd terraform/live/nonprod/00-s3-backend/stacks && terraform init && terraform apply -var-file=../params/main.tfvars
cd ../../10-network/stacks && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../20-data/stacks && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../30-compute/stacks && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
cd ../../40-kubernetes/stacks && terraform init -backend-config=../backends/backend.hcl && terraform apply -var-file=../params/main.tfvars
# Re-apply 30-compute with OIDC values
cd ../../30-compute/stacks && terraform apply -var-file=../params/main.tfvars
```

### Step 3 — Bootstrap application stack
```bash
cd ~/Documents/MyProjects/MLOps-Projects
aws eks update-kubeconfig --name churn-mlops-nonprod --region us-east-1
./scripts/bootstrap-new-cluster.sh
```

### Step 4 — Migrate MLflow model (REQUIRED — new RDS is always empty)
```bash
# Copy model artifact to new S3 bucket
aws s3 cp \
  s3://churn-mlops-nonprod-artifacts/1/models/m-ffa760cc477d45ccaece4463910f6504/artifacts/ \
  s3://churn-mlops-nonprod-artifacts/1/models/m-ffa760cc477d45ccaece4463910f6504/artifacts/ \
  --recursive

# Upload migration script to S3
aws s3 cp scripts/migrate-mlflow-model.py \
  s3://churn-mlops-nonprod-artifacts/scripts/migrate-mlflow-model.py

# Run migration via SSM
aws ssm start-session --target <NEW_EC2_INSTANCE_ID> --region us-east-1
# Inside EC2:
#   aws s3 cp s3://churn-mlops-nonprod-artifacts/scripts/migrate-mlflow-model.py /tmp/
#   pip3 install mlflow boto3 --user --quiet
#   python3 /tmp/migrate-mlflow-model.py
```

### Step 5 — Restart prediction API pods
```bash
kubectl argo rollouts restart churn-prediction-api -n churn-mlops
kubectl get pods -n churn-mlops -w
```

### Step 6 — Verify
```bash
# Get ALB URL
kubectl get svc -n churn-mlops

# Test prediction API
curl http://<ALB_URL>/health
```

### Evening Teardown
```bash
./scripts/teardown-networking.sh
cd terraform/live/nonprod/40-kubernetes/stacks && terraform destroy -var-file=../params/main.tfvars
cd ../../30-compute/stacks && terraform destroy -var-file=../params/main.tfvars
cd ../../20-data/stacks && terraform destroy -var-file=../params/main.tfvars
cd ../../10-network/stacks && terraform destroy -var-file=../params/main.tfvars
./scripts/teardown-mlflow-infra.sh
```

## Important Notes
- New RDS is ALWAYS empty after rebuild — always run migrate-mlflow-model.py
- Model artifact in S3 persists across rebuilds — no need to retrain
- Update NEW_EC2_INSTANCE_ID in Step 4 after each terraform apply (changes every rebuild)
- SSH IP may change — update allowed_ssh_cidrs in 10-network/params/main.tfvars

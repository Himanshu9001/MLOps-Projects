"""
migrate-mlflow-model.py
=======================
One-time script to migrate MLflow model registry from old cluster to new cluster.

WHEN TO RUN:
  - During blue-green cutover when new MLflow RDS is empty
  - After rebuilding MLflow infrastructure from scratch

HOW TO RUN:
  1. Copy model artifact to new S3 bucket first (from laptop):
       aws s3 cp \
         s3://<OLD_ARTIFACTS_BUCKET>/<model_path>/artifacts/ \
         s3://<NEW_ARTIFACTS_BUCKET>/<model_path>/artifacts/ \
         --recursive

  2. SSH or SSM into new MLflow EC2:
       aws ssm start-session --target <NEW_EC2_INSTANCE_ID> --region us-east-1

  3. Run this script inside EC2:
       python3 /tmp/migrate-mlflow-model.py

PREREQUISITES:
  - Old MLflow must be running and reachable
  - New MLflow must be running and reachable
  - Model artifact must already be copied to new S3 bucket (Step 1 above)
  - MLflow and boto3 must be installed:
       pip3 install mlflow boto3 --user

VALUES TO UPDATE FOR EACH MIGRATION:
  - OLD_MLFLOW_URI     : tracking URI of old MLflow server
  - NEW_MLFLOW_URI     : tracking URI of new MLflow server
  - OLD_ARTIFACTS_BUCKET : source S3 bucket name
  - NEW_ARTIFACTS_BUCKET : destination S3 bucket name
  - MODEL_NAME         : registered model name in MLflow registry

CURRENT MIGRATION (May 2026 - nonprod blue-green):
  Old cluster : churn-mlops (eksctl)
  New cluster : churn-mlops-nonprod (Terraform)
  Old MLflow  : http://98.86.0.163:5000 (i-0d3ebb196f1ed53b8)
  New MLflow  : http://10.1.1.233:5000  (i-063cfab3185b59739)
  Old bucket  : churn-mlops-artifacts
  New bucket  : churn-mlops-nonprod-artifacts
"""

import mlflow
from mlflow.tracking import MlflowClient
import time

# ─────────────────────────────────────────
# UPDATE THESE VALUES FOR EACH MIGRATION
# ─────────────────────────────────────────

# Old MLflow tracking server URI
# UPDATE: change to current old cluster MLflow URI
OLD_MLFLOW_URI = "http://98.86.0.163:5000"

# New MLflow tracking server URI
# UPDATE: change to current new cluster MLflow URI (use private IP when running from EC2)
NEW_MLFLOW_URI = "http://10.1.1.233:5000"

# S3 bucket names
# UPDATE: change to current old and new bucket names
OLD_ARTIFACTS_BUCKET = "churn-mlops-artifacts"
NEW_ARTIFACTS_BUCKET = "churn-mlops-nonprod-artifacts"

# Model name in MLflow registry
# UPDATE: change if model name differs
MODEL_NAME = "churn-prediction-model"

# Alias to migrate (usually "production")
# UPDATE: add more aliases if needed
ALIAS = "production"

# ─────────────────────────────────────────
# MIGRATION LOGIC — do not modify below
# ─────────────────────────────────────────

def migrate():
    print(f"Connecting to OLD MLflow: {OLD_MLFLOW_URI}")
    old_client = MlflowClient(tracking_uri=OLD_MLFLOW_URI)

    # Get current production model version from old MLflow
    alias_info = old_client.get_model_version_by_alias(
        name=MODEL_NAME,
        alias=ALIAS
    )
    print(f"Found version  : {alias_info.version}")
    print(f"Old S3 source  : {alias_info.source}")
    print(f"Run ID         : {alias_info.run_id}")

    # Replace old bucket with new bucket in S3 path
    new_source = alias_info.source.replace(
        f"s3://{OLD_ARTIFACTS_BUCKET}",
        f"s3://{NEW_ARTIFACTS_BUCKET}"
    )
    print(f"New S3 source  : {new_source}")

    print(f"\nConnecting to NEW MLflow: {NEW_MLFLOW_URI}")
    new_client = MlflowClient(tracking_uri=NEW_MLFLOW_URI)

    # Create registered model in new MLflow
    try:
        new_client.create_registered_model(MODEL_NAME)
        print(f"Registered model created: {MODEL_NAME}")
    except Exception as e:
        print(f"Model already exists (ok): {e}")

    # Create model version pointing to new S3 path
    # Note: run_id will be a dangling reference (run does not exist in new RDS)
    # This is acceptable - model loads fine, run lineage just not visible in UI
    new_version = new_client.create_model_version(
        name=MODEL_NAME,
        source=new_source,
        run_id=alias_info.run_id
    )
    print(f"New version created: {new_version.version}")

    # Wait for version to reach READY state
    print("Waiting for version to be ready...")
    time.sleep(5)

    # Set production alias on new MLflow
    new_client.set_registered_model_alias(
        name=MODEL_NAME,
        alias=ALIAS,
        version=new_version.version
    )
    print(f"\nDone - '{ALIAS}' alias set to version {new_version.version} on new MLflow")
    print(f"Verify: curl {NEW_MLFLOW_URI}/api/2.0/mlflow/registered-models/alias?name={MODEL_NAME}&alias={ALIAS}")

if __name__ == "__main__":
    migrate()

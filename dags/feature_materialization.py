"""
DAG 1: Feature Materialization
Runs daily to materialize features from S3 to Redis online store.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from kubernetes.client import models as k8s

default_args = {
    "owner": "mlops",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="feature_materialization",
    description="Daily feature materialization from S3 to Redis",
    default_args=default_args,
    schedule="0 1 * * *",  # Every day at 1 AM
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["mlops", "feast", "features"],
) as dag:

    materialize_features = KubernetesPodOperator(
        task_id="materialize_features",
        name="feast-materialize",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "-c"],
        arguments=["""
import subprocess
import sys

# Install feast
subprocess.run([sys.executable, "-m", "pip", "install", "feast[redis,aws]==0.40.1", "s3fs"], check=True)

import os
os.chdir("/app")

# Run materialization
from feast import FeatureStore
from datetime import datetime, timezone

store = FeatureStore(repo_path="feature_store/churn_feature_repo/feature_repo")
store.materialize_incremental(end_date=datetime.now(timezone.utc))
print("Feature materialization complete!")
"""],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=True,
        get_logs=True,
    )

    materialize_features

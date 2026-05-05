"""
DAG 1: Feature Materialization
Runs daily to materialize features from S3 to Redis online store.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator

default_args = {
    "owner": "mlops",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="feature_materialization",
    description="Daily feature materialization from S3 to Redis",
    default_args=default_args,
    schedule="0 1 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["mlops", "feast", "features"],
) as dag:

    materialize_features = KubernetesPodOperator(
        task_id="materialize_features",
        name="feast-materialize",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-stream-processor:latest",
        cmds=["python", "-c"],
        arguments=[
            """
import boto3
import pandas as pd
import redis
import json
import os
from datetime import datetime, timezone

print("Starting feature materialization...")

# Connect to Redis
r = redis.Redis(host="redis-master.redis.svc.cluster.local", port=6379)

# Load features from S3
s3 = boto3.client("s3", region_name="us-east-1")
obj = s3.get_object(Bucket="churn-mlops-artifacts", Key="feast/customer_features.parquet")

import io
df = pd.read_parquet(io.BytesIO(obj["Body"].read()))
print(f"Loaded {len(df)} customer records from S3")

# Write to Redis
pipe = r.pipeline()
count = 0
for _, row in df.iterrows():
    key = f"feast:customer:{row['customer_id']}"
    features = {col: str(row[col]) for col in df.columns if col not in ["customer_id", "event_timestamp"]}
    pipe.hset(key, mapping=features)
    pipe.expire(key, 7 * 24 * 3600)
    count += 1
    if count % 500 == 0:
        pipe.execute()
        pipe = r.pipeline()
        print(f"Materialized {count} records...")

pipe.execute()
print(f"Feature materialization complete! {count} customers updated in Redis.")
"""
        ],
        env_vars={
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    materialize_features

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
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-materialize:latest",
        env_vars={
            "AWS_DEFAULT_REGION": "us-east-1",
            "REDIS_HOST": "redis-master.redis.svc.cluster.local",
            "REDIS_PORT": "6379",
            "S3_BUCKET": "churn-mlops-artifacts",
            "S3_KEY": "feast/customer_features.parquet",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    materialize_features

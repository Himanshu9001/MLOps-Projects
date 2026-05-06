"""
DAG 2: Churn Model Auto-Retraining
Runs weekly. Validates data quality first, then retrains if data is clean.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator

default_args = {
    "owner": "mlops",
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
    "email_on_failure": False,
}

with DAG(
    dag_id="churn_retraining",
    description="Weekly churn model retraining pipeline with data quality validation",
    default_args=default_args,
    schedule="0 2 * * 0",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["mlops", "retraining", "model", "data-quality"],
) as dag:

    # Step 0 — Validate data quality before anything else
    # Fails fast if data doesn't meet expectations — stops bad data reaching model
    validate_data = KubernetesPodOperator(
        task_id="validate_data",
        name="validate-data",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "src/validate_data.py"],
        arguments=["--data-path", "data/processed/train.csv",
                   "--s3-bucket", "churn-mlops-artifacts"],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # Step 1 — Check drift
    check_drift = KubernetesPodOperator(
        task_id="check_drift",
        name="drift-check",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "src/drift_detection.py"],
        arguments=["--threshold", "0.3"],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # Step 2 — Preprocess data
    preprocess = KubernetesPodOperator(
        task_id="preprocess",
        name="preprocess",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "src/preprocess.py"],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # Step 3 — Train model
    train = KubernetesPodOperator(
        task_id="train",
        name="train",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "src/train.py"],
        arguments=["--n_estimators", "100", "--max_depth", "10", "--min_samples_split", "2"],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # Step 4 — Register and promote model
    register = KubernetesPodOperator(
        task_id="register_model",
        name="register-model",
        namespace="churn-mlops",
        image="011528270076.dkr.ecr.us-east-1.amazonaws.com/churn-prediction-api:latest",
        cmds=["python", "src/register_model.py"],
        env_vars={
            "MLFLOW_TRACKING_URI": "http://10.0.1.225:5000",
            "AWS_DEFAULT_REGION": "us-east-1",
        },
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # Step 5 — Restart API to load new model
    restart_api = KubernetesPodOperator(
        task_id="restart_api",
        name="restart-api",
        namespace="churn-mlops",
        image="bitnami/kubectl:latest",
        cmds=["kubectl", "rollout", "restart",
              "rollout/churn-prediction-api", "-n", "churn-mlops"],
        service_account_name="churn-prediction-sa",
        is_delete_operator_pod=False,
        get_logs=True,
    )

    # DAG dependency chain
    validate_data >> check_drift >> preprocess >> train >> register >> restart_api

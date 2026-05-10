"""
distributed_training.py — Phase 21: Distributed Training with Ray
==================================================================

Three-phase distributed ML pipeline on Ray cluster (EKS):

Phase 1 — Ray Data:
  Distributed preprocessing of Telco Churn dataset across Ray workers.
  Each worker processes a shard of data in parallel.

Phase 2 — Ray Tune:
  Parallel hyperparameter search across 20 trials.
  Each trial loads data from S3 directly (no serialization overhead).
  ASHA scheduler kills bad trials early.
  All trials logged to MLflow.

Phase 3 — Ray Train:
  Distributed training using best params from Tune.
  Data parallelism across workers.
  Ensemble aggregated via soft voting.

Fix from v1: data loaded inside each trial from S3 instead of
passing DataFrames through config — eliminates serialization bottleneck
that caused CPU deadlock on t3.medium nodes.
"""

import ray
from ray import tune
from ray.tune.schedulers import ASHAScheduler

import pandas as pd
import numpy as np
import mlflow
import mlflow.sklearn
import boto3
import io
import os
import logging
import time
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    roc_auc_score,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://10.1.1.233:5000")
S3_BUCKET           = os.getenv("S3_BUCKET", "churn-mlops-nonprod-artifacts")
S3_DATA_KEY         = os.getenv("S3_DATA_KEY", "data/raw/churn.csv")
AWS_REGION          = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
RAY_ADDRESS         = os.getenv("RAY_ADDRESS", "auto")

# Tune config — reduced concurrent to avoid CPU deadlock on t3.medium
NUM_TRIALS      = 10   # reduced from 20 for faster demo — increase for production
MAX_CONCURRENT  = 2    # 2 concurrent — Karpenter node has 8GB RAM
TUNE_CPUS       = 1
TUNE_EXPERIMENT = "distributed-hyperparameter-search"
TRAIN_EXPERIMENT = "distributed-model-training"
NUM_WORKERS      = 2

FEATURE_COLUMNS = [
    "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
    "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
    "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
    "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
    "MonthlyCharges", "TotalCharges",
]

# ─────────────────────────────────────────
# Shared data loading utility
# ─────────────────────────────────────────

def load_and_preprocess() -> tuple:
    """
    Load raw data from S3 and preprocess.
    Called on driver and inside each worker — S3 read is fast (~0.5s).
    Avoids passing large DataFrames through Ray object store.
    """
    s3 = boto3.client("s3", region_name=AWS_REGION)
    obj = s3.get_object(Bucket=S3_BUCKET, Key=S3_DATA_KEY)
    df = pd.read_csv(io.BytesIO(obj["Body"].read()))

    # Preprocess
    df = df.drop(columns=["customerID"])
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df["TotalCharges"] = df["TotalCharges"].fillna(df["TotalCharges"].median())
    df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})

    le = LabelEncoder()
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = le.fit_transform(df[col].astype(str))

    train_df, test_df = train_test_split(
        df, test_size=0.2, random_state=42, stratify=df["Churn"]
    )
    return train_df, test_df


# ─────────────────────────────────────────
# Phase 1 — Ray Data: Distributed Preprocessing
# ─────────────────────────────────────────

@ray.remote(num_cpus=0.5)  # schedule on worker, share CPU
def preprocess_shard(shard_records: list) -> list:
    """
    Preprocess a single data shard on a Ray worker.
    Accepts list of dicts (JSON-serializable) instead of DataFrame.
    Returns list of dicts for easy aggregation.
    """
    import pandas as pd
    from sklearn.preprocessing import LabelEncoder

    df = pd.DataFrame(shard_records)

    if "customerID" in df.columns:
        df = df.drop(columns=["customerID"])

    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df["TotalCharges"] = df["TotalCharges"].fillna(df["TotalCharges"].median())
    df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})

    le = LabelEncoder()
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = le.fit_transform(df[col].astype(str))

    return df.to_dict(orient="records")


def distributed_preprocess(df: pd.DataFrame, num_shards: int = 4) -> pd.DataFrame:
    """Preprocess data in parallel across Ray workers."""
    logger.info(f"Distributing preprocessing across {num_shards} shards...")
    start = time.time()

    # Convert to records (JSON-serializable) for Ray serialization
    records = df.to_dict(orient="records")
    shard_size = len(records) // num_shards
    shards = [
        records[i * shard_size:(i + 1) * shard_size]
        for i in range(num_shards - 1)
    ]
    shards.append(records[(num_shards - 1) * shard_size:])

    # Process all shards in parallel
    futures = [preprocess_shard.remote(shard) for shard in shards]
    processed_shards = ray.get(futures)

    result = pd.DataFrame([
        record
        for shard in processed_shards
        for record in shard
    ])

    elapsed = time.time() - start
    logger.info(
        f"Distributed preprocessing complete: {len(result)} rows "
        f"in {elapsed:.2f}s across {num_shards} shards"
    )
    return result


# ─────────────────────────────────────────
# Phase 2 — Ray Tune: Parallel Hyperparameter Search
# ─────────────────────────────────────────

def tune_training_function(config: dict) -> None:
    """
    Training function for each Ray Tune trial.
    Loads data from S3 directly — no serialization through Ray config.
    Each trial is independent and stateless.
    """
    import boto3
    import pandas as pd
    import io
    import os
    import mlflow
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, roc_auc_score
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import LabelEncoder
    from ray import train as ray_train

    # Load data fresh in each trial — faster than deserializing large config
    s3 = boto3.client("s3", region_name=config["aws_region"])
    obj = s3.get_object(Bucket=config["s3_bucket"], Key=config["s3_key"])
    df = pd.read_csv(io.BytesIO(obj["Body"].read()))

    # Preprocess
    df = df.drop(columns=["customerID"])
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df["TotalCharges"] = df["TotalCharges"].fillna(df["TotalCharges"].median())
    df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})
    from sklearn.preprocessing import LabelEncoder
    le = LabelEncoder()
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = le.fit_transform(df[col].astype(str))

    feature_cols = [
        "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
        "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
        "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
        "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
        "MonthlyCharges", "TotalCharges",
    ]

    train_df, test_df = train_test_split(
        df, test_size=0.2, random_state=42, stratify=df["Churn"]
    )

    X_train = train_df[feature_cols].values
    y_train = train_df["Churn"].values
    X_test  = test_df[feature_cols].values
    y_test  = test_df["Churn"].values

    # Train
    model = RandomForestClassifier(
        n_estimators      = config["n_estimators"],
        max_depth         = config["max_depth"],
        min_samples_split = config["min_samples_split"],
        max_features      = config["max_features"],
        random_state      = 42,
        n_jobs            = -1,
    )
    model.fit(X_train, y_train)

    # Evaluate
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]
    accuracy = accuracy_score(y_test, y_pred)
    roc_auc  = roc_auc_score(y_test, y_prob)

    # Log to MLflow
    mlflow.set_tracking_uri(config["mlflow_uri"])
    mlflow.set_experiment(config["experiment_name"])
    with mlflow.start_run(
        run_name=f"tune_n{config['n_estimators']}_d{str(config['max_depth'])[:3]}"
    ):
        mlflow.log_params({
            "n_estimators"     : config["n_estimators"],
            "max_depth"        : config["max_depth"],
            "min_samples_split": config["min_samples_split"],
            "max_features"     : config["max_features"],
        })
        mlflow.log_metrics({"accuracy": accuracy, "roc_auc": roc_auc})
        mlflow.set_tag("run_type", "ray_tune_trial")

    # Report to Tune
    ray_train.report({"accuracy": accuracy, "roc_auc": roc_auc})


def run_hyperparameter_search(train_df: pd.DataFrame, test_df: pd.DataFrame) -> dict:
    """Run parallel hyperparameter search using Ray Tune."""
    logger.info(
        f"Starting hyperparameter search: {NUM_TRIALS} trials, "
        f"max {MAX_CONCURRENT} concurrent..."
    )

    search_space = {
        # Pass only lightweight config — no DataFrames
        "s3_bucket"        : S3_BUCKET,
        "s3_key"           : S3_DATA_KEY,
        "aws_region"       : AWS_REGION,
        "mlflow_uri"       : MLFLOW_TRACKING_URI,
        "experiment_name"  : TUNE_EXPERIMENT,
        # Hyperparameters
        "n_estimators"     : tune.choice([50, 100, 150, 200, 300]),
        "max_depth"        : tune.choice([5, 10, 15, 20, 25]),  # removed None — unbounded trees hang
        "min_samples_split": tune.choice([2, 5, 10]),
        "max_features"     : tune.choice(["sqrt", "log2", 0.5]),
    }

    scheduler = ASHAScheduler(
        metric="roc_auc",
        mode="max",
        grace_period=1,
        reduction_factor=3,
    )

    tuner = tune.Tuner(
        tune.with_resources(
            tune_training_function,
            resources={"cpu": TUNE_CPUS}
        ),
        param_space=search_space,
        tune_config=tune.TuneConfig(
            scheduler=scheduler,
            num_samples=NUM_TRIALS,
            max_concurrent_trials=MAX_CONCURRENT,
        ),
    )

    results = tuner.fit()
    best_result  = results.get_best_result(metric="roc_auc", mode="max")
    best_config  = best_result.config
    best_metrics = best_result.metrics

    logger.info(
        f"Best trial — ROC AUC: {best_metrics['roc_auc']:.4f}, "
        f"Accuracy: {best_metrics['accuracy']:.4f}"
    )
    logger.info(
        f"Best params: n_estimators={best_config['n_estimators']}, "
        f"max_depth={best_config['max_depth']}, "
        f"min_samples_split={best_config['min_samples_split']}, "
        f"max_features={best_config['max_features']}"
    )
    return best_config


# ─────────────────────────────────────────
# Phase 3 — Ray Train: Distributed Training
# ─────────────────────────────────────────

@ray.remote(num_cpus=0.5)  # schedule on worker, share CPU
def train_worker(worker_id: int, shard_records: list, best_params: dict) -> dict:
    """
    Train a RandomForest on a single data shard.
    Accepts list of dicts — avoids DataFrame serialization issues.
    """
    import pandas as pd
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, roc_auc_score
    import logging

    feature_cols = [
        "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
        "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
        "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
        "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
        "MonthlyCharges", "TotalCharges",
    ]

    shard_df = pd.DataFrame(shard_records)
    X = shard_df[feature_cols].values
    y = shard_df["Churn"].values

    model = RandomForestClassifier(
        n_estimators      = best_params["n_estimators"],
        max_depth         = best_params["max_depth"],
        min_samples_split = best_params["min_samples_split"],
        max_features      = best_params["max_features"],
        random_state      = 42 + worker_id,
        n_jobs            = -1,
    )
    model.fit(X, y)

    y_pred = model.predict(X)
    y_prob = model.predict_proba(X)[:, 1]

    return {
        "worker_id"     : worker_id,
        "model"         : model,
        "n_samples"     : len(shard_df),
        "train_accuracy": accuracy_score(y, y_pred),
        "train_roc_auc" : roc_auc_score(y, y_prob),
    }


def run_distributed_training(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
    best_params: dict,
) -> tuple:
    """Train models across Ray workers and ensemble them."""
    logger.info(f"Starting distributed training across {NUM_WORKERS} workers...")
    start = time.time()

    # Convert to records for Ray serialization
    train_records = train_df.to_dict(orient="records")
    shard_size = len(train_records) // NUM_WORKERS
    shards = [
        train_records[i * shard_size:(i + 1) * shard_size]
        for i in range(NUM_WORKERS - 1)
    ]
    shards.append(train_records[(NUM_WORKERS - 1) * shard_size:])

    # Extract only hyperparams — not S3/MLflow config keys
    hp = {
        "n_estimators"     : best_params["n_estimators"],
        "max_depth"        : best_params["max_depth"],
        "min_samples_split": best_params["min_samples_split"],
        "max_features"     : best_params["max_features"],
    }

    # Launch parallel training
    futures = [
        train_worker.remote(i, shard, hp)
        for i, shard in enumerate(shards)
    ]
    worker_results = ray.get(futures)
    elapsed = time.time() - start

    logger.info(f"All {NUM_WORKERS} workers completed in {elapsed:.2f}s")
    for r in worker_results:
        logger.info(
            f"  Worker {r['worker_id']}: {r['n_samples']} samples, "
            f"train ROC AUC = {r['train_roc_auc']:.4f}"
        )

    # Evaluate ensemble on full test set
    X_test = test_df[FEATURE_COLUMNS].values
    y_test = test_df["Churn"].values

    y_prob = np.mean(
        [r["model"].predict_proba(X_test)[:, 1] for r in worker_results],
        axis=0
    )
    y_pred = (y_prob >= 0.5).astype(int)

    metrics = {
        "accuracy" : accuracy_score(y_test, y_pred),
        "roc_auc"  : roc_auc_score(y_test, y_prob),
        "f1_score" : f1_score(y_test, y_pred),
        "precision": precision_score(y_test, y_pred),
        "recall"   : recall_score(y_test, y_pred),
    }

    logger.info("Distributed ensemble metrics on full test set:")
    for k, v in metrics.items():
        logger.info(f"  {k}: {v:.4f}")

    # Log to MLflow
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    mlflow.set_experiment(TRAIN_EXPERIMENT)

    with mlflow.start_run(run_name="distributed_ensemble_training") as run:
        mlflow.log_params({
            **hp,
            "num_workers"  : NUM_WORKERS,
            "training_type": "distributed_data_parallel",
        })
        mlflow.log_metrics(metrics)
        mlflow.log_metrics({
            f"worker_{r['worker_id']}_train_roc_auc": r["train_roc_auc"]
            for r in worker_results
        })
        mlflow.set_tags({
            "run_type"       : "distributed_training",
            "framework"      : "ray",
            "model_validated": "true",
        })

        best_worker = max(worker_results, key=lambda r: r["train_roc_auc"])
        mlflow.sklearn.log_model(
            best_worker["model"],
            artifact_path="distributed_random_forest"
        )
        logger.info(f"MLflow run ID: {run.info.run_id}")

    return worker_results, metrics


# ─────────────────────────────────────────
# Main Pipeline
# ─────────────────────────────────────────

def main():
    logger.info("=" * 60)
    logger.info("Phase 21 — Distributed Training with Ray")
    logger.info("=" * 60)

    ray.init(address=RAY_ADDRESS, ignore_reinit_error=True)
    cluster_resources = ray.cluster_resources()
    logger.info(f"Cluster resources: {cluster_resources}")

    try:
        # ── Phase 1: Distributed Preprocessing ──
        logger.info("\n--- Phase 1: Ray Data — Distributed Preprocessing ---")
        s3 = boto3.client("s3", region_name=AWS_REGION)
        obj = s3.get_object(Bucket=S3_BUCKET, Key=S3_DATA_KEY)
        raw_df = pd.read_csv(io.BytesIO(obj["Body"].read()))
        logger.info(f"Loaded {len(raw_df)} rows from S3")

        processed_df = distributed_preprocess(raw_df, num_shards=2)

        train_df, test_df = train_test_split(
            processed_df,
            test_size=0.2,
            random_state=42,
            stratify=processed_df["Churn"],
        )
        logger.info(f"Train: {len(train_df)} rows, Test: {len(test_df)} rows")

        # ── Phase 2: Hyperparameter Search ──
        logger.info("\n--- Phase 2: Ray Tune — Parallel Hyperparameter Search ---")
        best_config = run_hyperparameter_search(train_df, test_df)

        # ── Phase 3: Distributed Training ──
        logger.info("\n--- Phase 3: Ray Train — Distributed Model Training ---")
        worker_results, final_metrics = run_distributed_training(
            train_df, test_df, best_config
        )

        # ── Summary ──
        logger.info("\n" + "=" * 60)
        logger.info("DISTRIBUTED TRAINING COMPLETE")
        logger.info("=" * 60)
        logger.info(f"Final ROC AUC  : {final_metrics['roc_auc']:.4f}")
        logger.info(f"Final Accuracy : {final_metrics['accuracy']:.4f}")
        logger.info(f"Final F1 Score : {final_metrics['f1_score']:.4f}")
        logger.info(f"MLflow Tune    : {TUNE_EXPERIMENT}")
        logger.info(f"MLflow Train   : {TRAIN_EXPERIMENT}")

    finally:
        ray.shutdown()
        logger.info("Ray cluster connection closed")


if __name__ == "__main__":
    main()

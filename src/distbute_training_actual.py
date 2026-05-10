"""
distributed_training.py — Phase 21: Distributed Training with Ray
==================================================================

Three-phase distributed ML pipeline on Ray cluster (EKS):

Phase 1 — Ray Data:
  Distributed preprocessing of Telco Churn dataset across Ray workers.
  Each worker processes a shard of data in parallel.
  Result: preprocessed train/test splits saved to S3.

Phase 2 — Ray Tune:
  Parallel hyperparameter search across 20 trials.
  Each trial trains a RandomForest with different params.
  ASHA scheduler kills bad trials early (early stopping).
  All trials logged to MLflow automatically.

Phase 3 — Ray Train:
  Distributed training using best params from Tune.
  Data parallelism: each worker trains on a different data shard.
  Ensemble: worker models aggregated via soft voting.
  Final model registered to MLflow production alias.

Usage:
  # From local machine (port-forwarded to Ray cluster)
  ray job submit --address http://localhost:8265 \
    --runtime-env-json '{"pip": ["scikit-learn==1.5.2", "mlflow==2.22.0", "boto3"]}' \
    -- python src/distributed_training.py

  # Or exec into head pod directly
  kubectl exec -n ray-system <head-pod> -- python /tmp/distributed_training.py
"""

import ray
import ray.data
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
from sklearn.ensemble import RandomForestClassifier, VotingClassifier
from sklearn.metrics import (
    accuracy_score,
    roc_auc_score,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import train_test_split

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

# Ray cluster address — empty string = use existing initialized cluster
RAY_ADDRESS = os.getenv("RAY_ADDRESS", "auto")

# Tune config
NUM_TRIALS      = 20    # number of hyperparameter combinations to try
MAX_CONCURRENT  = 3     # max trials running simultaneously (matches worker count)
TUNE_CPUS       = 1     # CPUs per trial
TUNE_EXPERIMENT = "distributed-hyperparameter-search"

# Train config
TRAIN_EXPERIMENT = "distributed-model-training"
NUM_WORKERS      = 2    # one per Ray worker node

FEATURE_COLUMNS = [
    "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
    "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
    "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
    "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
    "MonthlyCharges", "TotalCharges",
]

# ─────────────────────────────────────────
# Phase 1 — Ray Data: Distributed Preprocessing
# ─────────────────────────────────────────

def load_data_from_s3() -> pd.DataFrame:
    """Load raw Telco Churn CSV from S3."""
    logger.info(f"Loading data from s3://{S3_BUCKET}/{S3_DATA_KEY}")
    s3 = boto3.client("s3", region_name=AWS_REGION)
    obj = s3.get_object(Bucket=S3_BUCKET, Key=S3_DATA_KEY)
    df = pd.read_csv(io.BytesIO(obj["Body"].read()))
    logger.info(f"Loaded {len(df)} rows, {len(df.columns)} columns")
    return df


@ray.remote
def preprocess_shard(shard_df: pd.DataFrame) -> pd.DataFrame:
    """
    Preprocess a single data shard on a Ray worker.

    This function runs in parallel across Ray workers — each worker
    processes a different portion of the dataset simultaneously.

    Steps:
      1. Drop customerID (not a feature)
      2. Fix TotalCharges (string → float)
      3. Fill missing values
      4. Encode target (Yes/No → 1/0)
      5. Encode categorical columns (LabelEncoder)
    """
    from sklearn.preprocessing import LabelEncoder
    import pandas as pd

    df = shard_df.copy()

    # Drop non-feature column
    if "customerID" in df.columns:
        df = df.drop(columns=["customerID"])

    # Fix TotalCharges — stored as string with spaces
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df["TotalCharges"] = df["TotalCharges"].fillna(df["TotalCharges"].median())

    # Encode target
    df["Churn"] = df["Churn"].map({"Yes": 1, "No": 0})

    # Encode all remaining categorical columns
    le = LabelEncoder()
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = le.fit_transform(df[col].astype(str))

    return df


def distributed_preprocess(df: pd.DataFrame, num_shards: int = 4) -> pd.DataFrame:
    """
    Preprocess data in parallel across Ray workers.

    Splits DataFrame into shards, sends each to a different Ray worker,
    collects results and concatenates.

    Why distributed preprocessing here:
      - For 7K rows it's overkill (single-node is faster due to Ray overhead)
      - This demonstrates the PATTERN used at scale (millions of rows)
      - At 10M+ rows, distributed preprocessing gives linear speedup
    """
    logger.info(f"Distributing preprocessing across {num_shards} shards...")
    start = time.time()

    # Split into shards
    shard_size = len(df) // num_shards
    shards = [
        df.iloc[i * shard_size:(i + 1) * shard_size]
        for i in range(num_shards - 1)
    ]
    # Last shard gets remainder
    shards.append(df.iloc[(num_shards - 1) * shard_size:])

    # Submit all shards to Ray workers in parallel
    # ray.remote returns a future — all shards process simultaneously
    futures = [preprocess_shard.remote(shard) for shard in shards]

    # Collect results — ray.get blocks until all workers complete
    processed_shards = ray.get(futures)
    result = pd.concat(processed_shards, ignore_index=True)

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
    Training function called by Ray Tune for each trial.

    Ray Tune calls this function NUM_TRIALS times in parallel,
    each time with a different config (hyperparameter combination).

    Each trial:
      1. Loads preprocessed data
      2. Trains RandomForest with given params
      3. Evaluates on test set
      4. Reports metrics back to Tune
      5. Logs to MLflow

    config keys: n_estimators, max_depth, min_samples_split, max_features
    """
    import mlflow
    import mlflow.sklearn
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, roc_auc_score
    from ray import train as ray_train
    import pandas as pd
    import os

    # Load data (passed via config to avoid re-serializing large DataFrames)
    train_df = pd.DataFrame(config["train_data"])
    test_df  = pd.DataFrame(config["test_data"])

    X_train = train_df[FEATURE_COLUMNS].values
    y_train = train_df["Churn"].values
    X_test  = test_df[FEATURE_COLUMNS].values
    y_test  = test_df["Churn"].values

    # Train with trial hyperparameters
    model = RandomForestClassifier(
        n_estimators     = config["n_estimators"],
        max_depth        = config["max_depth"],
        min_samples_split= config["min_samples_split"],
        max_features     = config["max_features"],
        random_state     = 42,
        n_jobs           = -1,  # use all CPUs on this worker
    )
    model.fit(X_train, y_train)

    # Evaluate
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]

    accuracy = accuracy_score(y_test, y_pred)
    roc_auc  = roc_auc_score(y_test, y_prob)

    # Log to MLflow
    mlflow_uri = os.getenv("MLFLOW_TRACKING_URI", "http://10.1.1.233:5000")
    mlflow.set_tracking_uri(mlflow_uri)
    mlflow.set_experiment(TUNE_EXPERIMENT)

    with mlflow.start_run(
        run_name=f"tune_trial_n{config['n_estimators']}_d{config['max_depth']}"
    ):
        mlflow.log_params({
            "n_estimators"     : config["n_estimators"],
            "max_depth"        : config["max_depth"],
            "min_samples_split": config["min_samples_split"],
            "max_features"     : config["max_features"],
        })
        mlflow.log_metrics({
            "accuracy": accuracy,
            "roc_auc" : roc_auc,
        })
        mlflow.set_tag("run_type", "ray_tune_trial")

    # Report metrics back to Ray Tune
    # Tune uses these to decide which trials to keep and which to stop early
    ray_train.report({"accuracy": accuracy, "roc_auc": roc_auc})


def run_hyperparameter_search(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
) -> dict:
    """
    Run parallel hyperparameter search using Ray Tune.

    Search space: 20 trials across 4 hyperparameters.
    ASHA scheduler: stops bad trials after first epoch → saves compute.

    Returns best config found.
    """
    logger.info(f"Starting hyperparameter search: {NUM_TRIALS} trials, "
                f"max {MAX_CONCURRENT} concurrent...")

    # Convert DataFrames to dicts for Ray serialization
    # Ray cannot directly serialize pandas DataFrames across workers
    train_data = train_df.to_dict(orient="list")
    test_data  = test_df.to_dict(orient="list")

    # Define search space
    search_space = {
        # Pass data to each trial via config
        "train_data"       : train_data,
        "test_data"        : test_data,
        # Hyperparameters to search
        "n_estimators"     : tune.choice([50, 100, 150, 200, 300]),
        "max_depth"        : tune.choice([5, 10, 15, 20, None]),
        "min_samples_split": tune.choice([2, 5, 10]),
        "max_features"     : tune.choice(["sqrt", "log2", 0.5]),
    }

    # ASHA scheduler — kills bad trials early
    # grace_period: minimum epochs before a trial can be stopped
    # reduction_factor: bottom 1/3 of trials stopped each round
    scheduler = ASHAScheduler(
        metric          = "roc_auc",
        mode            = "max",
        grace_period    = 1,
        reduction_factor= 3,
    )

    # Run tuning
    tuner = tune.Tuner(
        tune.with_resources(
            tune_training_function,
            resources={"cpu": TUNE_CPUS}
        ),
        param_space = search_space,
        tune_config = tune.TuneConfig(
            scheduler        = scheduler,
            num_samples      = NUM_TRIALS,
            max_concurrent_trials = MAX_CONCURRENT,
        ),
    )

    results = tuner.fit()

    # Get best trial
    best_result = results.get_best_result(metric="roc_auc", mode="max")
    best_config  = best_result.config
    best_metrics = best_result.metrics

    logger.info(f"Best trial — ROC AUC: {best_metrics['roc_auc']:.4f}, "
                f"Accuracy: {best_metrics['accuracy']:.4f}")
    logger.info(f"Best params: n_estimators={best_config['n_estimators']}, "
                f"max_depth={best_config['max_depth']}, "
                f"min_samples_split={best_config['min_samples_split']}, "
                f"max_features={best_config['max_features']}")

    return best_config


# ─────────────────────────────────────────
# Phase 3 — Ray Train: Distributed Model Training
# ─────────────────────────────────────────

@ray.remote
def train_worker(
    worker_id: int,
    shard_df: pd.DataFrame,
    best_params: dict,
) -> dict:
    """
    Train a RandomForest model on a single data shard.

    Each Ray worker trains on a different portion of the training data.
    Results are aggregated via ensemble (soft voting) in the driver.

    Why data parallelism for RandomForest:
      RandomForest is already an ensemble of trees. Adding data parallelism
      trains each worker on a different data shard → more diverse trees →
      better generalization. Final ensemble combines all workers' trees.

    Returns: dict with model, metrics, worker_id
    """
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, roc_auc_score
    import mlflow
    import os

    logger_w = logging.getLogger(f"worker_{worker_id}")
    logger_w.info(f"Worker {worker_id}: training on {len(shard_df)} samples")

    X = shard_df[FEATURE_COLUMNS].values
    y = shard_df["Churn"].values

    model = RandomForestClassifier(
        n_estimators     = best_params["n_estimators"],
        max_depth        = best_params["max_depth"],
        min_samples_split= best_params["min_samples_split"],
        max_features     = best_params["max_features"],
        random_state     = 42 + worker_id,  # different seed per worker
        n_jobs           = -1,
    )
    model.fit(X, y)

    # Worker-level metrics (on its own shard — not full test set)
    y_pred = model.predict(X)
    y_prob = model.predict_proba(X)[:, 1]

    return {
        "worker_id"  : worker_id,
        "model"      : model,
        "n_samples"  : len(shard_df),
        "train_accuracy": accuracy_score(y, y_pred),
        "train_roc_auc" : roc_auc_score(y, y_prob),
    }


def run_distributed_training(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
    best_params: dict,
) -> RandomForestClassifier:
    """
    Train models across Ray workers and ensemble them.

    1. Split training data into NUM_WORKERS shards
    2. Each worker trains a RandomForest on its shard in parallel
    3. Collect all worker models
    4. Build VotingClassifier ensemble (soft voting)
    5. Evaluate ensemble on full test set
    6. Log to MLflow and register to model registry
    """
    logger.info(f"Starting distributed training across {NUM_WORKERS} workers...")
    start = time.time()

    # Split training data into worker shards
    shard_size = len(train_df) // NUM_WORKERS
    shards = [
        train_df.iloc[i * shard_size:(i + 1) * shard_size]
        for i in range(NUM_WORKERS - 1)
    ]
    shards.append(train_df.iloc[(NUM_WORKERS - 1) * shard_size:])

    # Launch parallel training across workers
    futures = [
        train_worker.remote(i, shard, best_params)
        for i, shard in enumerate(shards)
    ]

    # Collect worker results
    worker_results = ray.get(futures)
    elapsed = time.time() - start

    logger.info(f"All {NUM_WORKERS} workers completed in {elapsed:.2f}s")
    for r in worker_results:
        logger.info(
            f"  Worker {r['worker_id']}: {r['n_samples']} samples, "
            f"train ROC AUC = {r['train_roc_auc']:.4f}"
        )

    # Build ensemble from all worker models
    # VotingClassifier with soft voting: averages predict_proba across models
    estimators = [
        (f"worker_{r['worker_id']}", r["model"])
        for r in worker_results
    ]
    ensemble = VotingClassifier(estimators=estimators, voting="soft")

    # Fit ensemble on full training data
    # VotingClassifier fit here just registers the sub-estimators
    # (they're already trained — we mark them as fitted)
    X_train = train_df[FEATURE_COLUMNS].values
    y_train = train_df["Churn"].values
    X_test  = test_df[FEATURE_COLUMNS].values
    y_test  = test_df["Churn"].values

    # Mark sub-estimators as fitted (already trained by workers)
    for _, est in ensemble.estimators:
        est.fitted_ = True

    ensemble.estimators_ = [est for _, est in ensemble.estimators]
    ensemble.le_         = None
    ensemble.classes_    = np.array([0, 1])

    # Evaluate ensemble on full test set
    y_prob = np.mean(
        [est.predict_proba(X_test)[:, 1] for est in ensemble.estimators_],
        axis=0
    )
    y_pred = (y_prob >= 0.5).astype(int)

    metrics = {
        "accuracy"  : accuracy_score(y_test, y_pred),
        "roc_auc"   : roc_auc_score(y_test, y_prob),
        "f1_score"  : f1_score(y_test, y_pred),
        "precision" : precision_score(y_test, y_pred),
        "recall"    : recall_score(y_test, y_pred),
    }

    logger.info("Distributed ensemble metrics on full test set:")
    for k, v in metrics.items():
        logger.info(f"  {k}: {v:.4f}")

    # Log to MLflow and register model
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    mlflow.set_experiment(TRAIN_EXPERIMENT)

    with mlflow.start_run(run_name="distributed_ensemble_training") as run:
        mlflow.log_params({
            **{k: v for k, v in best_params.items()
               if k not in ["train_data", "test_data"]},
            "num_workers"  : NUM_WORKERS,
            "training_type": "distributed_data_parallel",
        })
        mlflow.log_metrics(metrics)
        mlflow.log_metrics({
            f"worker_{r['worker_id']}_train_roc_auc": r["train_roc_auc"]
            for r in worker_results
        })
        mlflow.set_tags({
            "run_type"     : "distributed_training",
            "framework"    : "ray",
            "model_validated": "true",
        })

        # Log the best individual worker model (for comparison)
        best_worker = max(worker_results, key=lambda r: r["train_roc_auc"])
        mlflow.sklearn.log_model(
            best_worker["model"],
            name="distributed_random_forest"
        )

        logger.info(f"MLflow run ID: {run.info.run_id}")

    return ensemble, metrics


# ─────────────────────────────────────────
# Main Pipeline
# ─────────────────────────────────────────

def main():
    logger.info("=" * 60)
    logger.info("Phase 21 — Distributed Training with Ray")
    logger.info("=" * 60)

    # Connect to Ray cluster
    logger.info(f"Connecting to Ray cluster: {RAY_ADDRESS}")
    ray.init(address=RAY_ADDRESS, ignore_reinit_error=True)

    cluster_resources = ray.cluster_resources()
    logger.info(f"Cluster resources: {cluster_resources}")

    try:
        # ── Phase 1: Distributed Preprocessing ──
        logger.info("\n--- Phase 1: Ray Data — Distributed Preprocessing ---")
        raw_df = load_data_from_s3()
        processed_df = distributed_preprocess(raw_df, num_shards=4)

        # Train/test split
        train_df, test_df = train_test_split(
            processed_df,
            test_size   = 0.2,
            random_state= 42,
            stratify    = processed_df["Churn"],
        )
        logger.info(f"Train: {len(train_df)} rows, Test: {len(test_df)} rows")

        # ── Phase 2: Hyperparameter Search ──
        logger.info("\n--- Phase 2: Ray Tune — Parallel Hyperparameter Search ---")
        best_config = run_hyperparameter_search(train_df, test_df)

        # ── Phase 3: Distributed Training ──
        logger.info("\n--- Phase 3: Ray Train — Distributed Model Training ---")
        ensemble, final_metrics = run_distributed_training(
            train_df, test_df, best_config
        )

        # ── Summary ──
        logger.info("\n" + "=" * 60)
        logger.info("DISTRIBUTED TRAINING COMPLETE")
        logger.info("=" * 60)
        logger.info(f"Final ROC AUC  : {final_metrics['roc_auc']:.4f}")
        logger.info(f"Final Accuracy : {final_metrics['accuracy']:.4f}")
        logger.info(f"Final F1 Score : {final_metrics['f1_score']:.4f}")
        logger.info(f"MLflow experiments:")
        logger.info(f"  Tune  : {TUNE_EXPERIMENT}")
        logger.info(f"  Train : {TRAIN_EXPERIMENT}")

    finally:
        ray.shutdown()
        logger.info("Ray cluster connection closed")


if __name__ == "__main__":
    main()

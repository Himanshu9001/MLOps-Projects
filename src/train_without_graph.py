import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
    confusion_matrix
)
import mlflow
import mlflow.sklearn
import logging
import os
import json

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def load_data(train_path, test_path):
    logger.info("Loading processed data...")
    train_df = pd.read_csv(train_path)
    test_df = pd.read_csv(test_path)

    X_train = train_df.drop(columns=['Churn'])
    y_train = train_df['Churn']
    X_test = test_df.drop(columns=['Churn'])
    y_test = test_df['Churn']

    logger.info(f"Train: {X_train.shape}, Test: {X_test.shape}")
    return X_train, X_test, y_train, y_test

def evaluate_model(model, X_test, y_test):
    logger.info("Evaluating model...")
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]

    metrics = {
        "accuracy":  accuracy_score(y_test, y_pred),
        "f1_score":  f1_score(y_test, y_pred),
        "precision": precision_score(y_test, y_pred),
        "recall":    recall_score(y_test, y_pred),
        "roc_auc":   roc_auc_score(y_test, y_prob)
    }

    for name, value in metrics.items():
        logger.info(f"{name}: {value:.4f}")

    return metrics

def train(params):
    # Set MLflow experiment name
    mlflow.set_experiment("churn-prediction")

    with mlflow.start_run():
        logger.info("Starting training run...")

        # Log parameters to MLflow
        mlflow.log_params(params)

        # Load data
        X_train, X_test, y_train, y_test = load_data(
            "data/processed/train.csv",
            "data/processed/test.csv"
        )

        # Train model
        logger.info(f"Training RandomForest with params: {params}")
        model = RandomForestClassifier(
            n_estimators=params["n_estimators"],
            max_depth=params["max_depth"],
            min_samples_split=params["min_samples_split"],
            random_state=42
        )
        model.fit(X_train, y_train)

        # Evaluate model
        metrics = evaluate_model(model, X_test, y_test)

        # Log metrics to MLflow
        mlflow.log_metrics(metrics)

        # Log model artifact to MLflow
        mlflow.sklearn.log_model(model, "random_forest_model")

        # Log feature importance as artifact
        feature_importance = dict(zip(
            X_train.columns.tolist(),
            model.feature_importances_.tolist()
        ))
        
        # Save feature importance to file and log it
        os.makedirs("models", exist_ok=True)
        fi_path = "models/feature_importance.json"
        with open(fi_path, "w") as f:
            json.dump(feature_importance, f, indent=2)
        mlflow.log_artifact(fi_path)

        # Add tags
        mlflow.set_tags({
            "model_type": "RandomForest",
            "dataset": "telco-churn",
            "developer": "heman"
        })

        logger.info("Training complete!")
        logger.info(f"MLflow Run ID: {mlflow.active_run().info.run_id}")

        return metrics

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--n_estimators", type=int, default=100)
    parser.add_argument("--max_depth", type=int, default=10)
    parser.add_argument("--min_samples_split", type=int, default=2)
    args = parser.parse_args()

    params = {
        "n_estimators": args.n_estimators,
        "max_depth": args.max_depth,
        "min_samples_split": args.min_samples_split
    }

    metrics = train(params)
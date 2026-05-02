import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
    confusion_matrix,
    roc_curve,
    precision_recall_curve
)
import mlflow
import mlflow.sklearn
import matplotlib.pyplot as plt
import seaborn as sns
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

def plot_confusion_matrix(y_test, y_pred, output_dir):
    logger.info("Plotting confusion matrix...")
    cm = confusion_matrix(y_test, y_pred)

    plt.figure(figsize=(8, 6))
    sns.heatmap(
        cm,
        annot=True,
        fmt='d',
        cmap='Blues',
        xticklabels=['No Churn', 'Churn'],
        yticklabels=['No Churn', 'Churn']
    )
    plt.title('Confusion Matrix', fontsize=16)
    plt.ylabel('Actual', fontsize=12)
    plt.xlabel('Predicted', fontsize=12)
    plt.tight_layout()

    path = os.path.join(output_dir, "confusion_matrix.png")
    plt.savefig(path)
    plt.close()
    logger.info(f"Confusion matrix saved to {path}")
    return path

def plot_roc_curve(y_test, y_prob, output_dir):
    logger.info("Plotting ROC curve...")
    fpr, tpr, _ = roc_curve(y_test, y_prob)
    auc = roc_auc_score(y_test, y_prob)

    plt.figure(figsize=(8, 6))
    plt.plot(fpr, tpr, color='blue', lw=2, label=f'ROC Curve (AUC = {auc:.4f})')
    plt.plot([0, 1], [0, 1], color='gray', linestyle='--', label='Random Classifier')
    plt.xlim([0.0, 1.0])
    plt.ylim([0.0, 1.05])
    plt.xlabel('False Positive Rate', fontsize=12)
    plt.ylabel('True Positive Rate', fontsize=12)
    plt.title('ROC Curve', fontsize=16)
    plt.legend(loc='lower right')
    plt.tight_layout()

    path = os.path.join(output_dir, "roc_curve.png")
    plt.savefig(path)
    plt.close()
    logger.info(f"ROC curve saved to {path}")
    return path

def plot_precision_recall_curve(y_test, y_prob, output_dir):
    logger.info("Plotting Precision-Recall curve...")
    precision, recall, _ = precision_recall_curve(y_test, y_prob)

    plt.figure(figsize=(8, 6))
    plt.plot(recall, precision, color='green', lw=2)
    plt.xlabel('Recall', fontsize=12)
    plt.ylabel('Precision', fontsize=12)
    plt.title('Precision-Recall Curve', fontsize=16)
    plt.tight_layout()

    path = os.path.join(output_dir, "precision_recall_curve.png")
    plt.savefig(path)
    plt.close()
    logger.info(f"Precision-Recall curve saved to {path}")
    return path

def plot_feature_importance(model, feature_names, output_dir):
    logger.info("Plotting feature importance...")
    importance_df = pd.DataFrame({
        'feature': feature_names,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)

    plt.figure(figsize=(10, 8))
    sns.barplot(
    data=importance_df,
    x='importance',
    y='feature',
    hue='feature',
    palette='viridis',
    legend=False
)
    plt.title('Feature Importance', fontsize=16)
    plt.xlabel('Importance Score', fontsize=12)
    plt.ylabel('Feature', fontsize=12)
    plt.tight_layout()

    path = os.path.join(output_dir, "feature_importance.png")
    plt.savefig(path)
    plt.close()
    logger.info(f"Feature importance saved to {path}")
    return path

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

    return metrics, y_pred, y_prob

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
        metrics, y_pred, y_prob = evaluate_model(model, X_test, y_test)

        # Log metrics to MLflow
        mlflow.log_metrics(metrics)

        # Create plots output directory
        plots_dir = "models/plots"
        os.makedirs(plots_dir, exist_ok=True)

        # Generate and log all plots
        cm_path = plot_confusion_matrix(y_test, y_pred, plots_dir)
        roc_path = plot_roc_curve(y_test, y_prob, plots_dir)
        pr_path = plot_precision_recall_curve(y_test, y_prob, plots_dir)
        fi_path = plot_feature_importance(model, X_train.columns.tolist(), plots_dir)

        # Log all plots as artifacts to MLflow
        mlflow.log_artifact(cm_path)
        mlflow.log_artifact(roc_path)
        mlflow.log_artifact(pr_path)
        mlflow.log_artifact(fi_path)

        # Log feature importance as JSON too
        feature_importance = dict(zip(
            X_train.columns.tolist(),
            model.feature_importances_.tolist()
        ))
        fi_json_path = "models/feature_importance.json"
        with open(fi_json_path, "w") as f:
            json.dump(feature_importance, f, indent=2)
        mlflow.log_artifact(fi_json_path)

        # Log model artifact to MLflow
        try:
            mlflow.sklearn.log_model(model, name="random_forest_model")
            logger.info("Model logged successfully to MLflow")
        except Exception as e:
            logger.error(f"Failed to log model: {e}")
            raise

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
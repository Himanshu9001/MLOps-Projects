"""
Model explainability using SHAP and LIME.
Generates feature importance explanations for individual predictions
and global feature importance across the entire dataset.
Used in: FastAPI /explain endpoint, post-training Airflow task, MLflow logging.
"""
import shap
import lime
import lime.lime_tabular
import numpy as np
import pandas as pd
import mlflow
import mlflow.sklearn
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend — required for server-side plot generation
import matplotlib.pyplot as plt
import logging
import os
import json
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

FEATURE_COLUMNS = [
    'gender', 'SeniorCitizen', 'Partner', 'Dependents', 'tenure',
    'PhoneService', 'MultipleLines', 'InternetService', 'OnlineSecurity',
    'OnlineBackup', 'DeviceProtection', 'TechSupport', 'StreamingTV',
    'StreamingMovies', 'Contract', 'PaperlessBilling', 'PaymentMethod',
    'MonthlyCharges', 'TotalCharges'
]

def load_model_and_data():
    """Loads production model from MLflow and training data for explainer initialization."""
    logger.info("Loading model from MLflow registry...")
    model = mlflow.sklearn.load_model("models:/churn-prediction-model@production")

    train_df = pd.read_csv("data/processed/train.csv")
    X_train = train_df[FEATURE_COLUMNS].values
    y_train = train_df['Churn'].values

    logger.info(f"Model loaded. Training data shape: {X_train.shape}")
    return model, X_train, y_train

# ─────────────────────────────────────────
# SHAP Explainer
# ─────────────────────────────────────────

def build_shap_explainer(model, X_train):
    """
    Builds a TreeSHAP explainer for the Random Forest model.
    TreeSHAP computes exact Shapley values in O(TLD^2) instead of exponential time
    by exploiting the tree structure — making it practical for production use.
    """
    logger.info("Building SHAP TreeExplainer...")
    explainer = shap.TreeExplainer(model)
    logger.info("SHAP explainer ready!")
    return explainer

def explain_prediction_shap(explainer, instance: np.ndarray) -> dict:
    """
    Computes SHAP values for a single prediction instance.
    Returns feature contributions showing why the model made this prediction.
    SHAP values sum to: prediction - base_value (expected model output).
    """
    shap_values = explainer.shap_values(instance.reshape(1, -1))

    # For binary classification, shap_values is a list [class_0, class_1]
    # We want class_1 (churn=1) contributions — flatten to 1D array
    # shap_values shape: (1, 19, 2) — samples x features x classes
    # Index [:, :, 1] gives churn class (class 1) contributions
    shap_vals = np.array(shap_values)[:, :, 1].flatten()

    explanation = {
        "base_value": float(np.array(explainer.expected_value).flatten()[1]
            if isinstance(explainer.expected_value, (list, np.ndarray))
            else explainer.expected_value),
        "feature_contributions": {
            feature: float(shap_val)
            for feature, shap_val in sorted(
                zip(FEATURE_COLUMNS, shap_vals.tolist()),
                key=lambda x: abs(x[1]),
                reverse=True
            )
        },
        "top_3_reasons": []
    }

    # Extract top 3 positive contributors (reasons for churn prediction)
    positive_contribs = [
        (feat, val) for feat, val in explanation["feature_contributions"].items()
        if val > 0
    ][:3]
    explanation["top_3_reasons"] = [
        {"feature": feat, "contribution": round(val, 4)}
        for feat, val in positive_contribs
    ]

    return explanation

def generate_shap_summary_plot(explainer, X_data: np.ndarray, output_path: str):
    """
    Generates SHAP beeswarm summary plot showing global feature importance.
    Each dot = one prediction. X-axis = SHAP value. Color = feature value (red=high, blue=low).
    This is the standard plot used in MLflow experiment tracking and model audits.
    """
    logger.info("Generating SHAP summary plot...")
    shap_values = explainer.shap_values(X_data)

    # shap_values shape: (n, 19, 2) — extract class 1 (churn)
    shap_vals = np.array(shap_values)[:, :, 1]

    plt.figure(figsize=(10, 8))
    shap.summary_plot(
        shap_vals,
        pd.DataFrame(X_data, columns=FEATURE_COLUMNS),
        show=False,
        plot_type="beeswarm"
    )
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    logger.info(f"SHAP summary plot saved to {output_path}")

def generate_shap_bar_plot(explainer, X_data: np.ndarray, output_path: str):
    """
    Generates SHAP bar plot showing mean absolute feature importance globally.
    Simpler than beeswarm — used for executive/business stakeholder reports.
    """
    logger.info("Generating SHAP bar plot...")
    shap_values = explainer.shap_values(X_data)

    # shap_values shape: (n, 19, 2) — extract class 1 (churn)
    shap_vals = np.array(shap_values)[:, :, 1]

    mean_shap = np.abs(shap_vals).mean(axis=0)  # shape: (19,)
    importance_df = pd.DataFrame({
        'feature': FEATURE_COLUMNS,
        'importance': mean_shap.tolist()
    }).sort_values('importance', ascending=True)

    plt.figure(figsize=(10, 8))
    plt.barh(importance_df['feature'], importance_df['importance'], color='steelblue')
    plt.xlabel('Mean |SHAP Value|')
    plt.title('Global Feature Importance (SHAP)')
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    logger.info(f"SHAP bar plot saved to {output_path}")

# ─────────────────────────────────────────
# LIME Explainer
# ─────────────────────────────────────────

def build_lime_explainer(X_train: np.ndarray):
    """
    Builds a LIME tabular explainer using training data distribution.
    LIME needs training data to understand the feature space and
    generate meaningful perturbations around a prediction instance.
    """
    logger.info("Building LIME explainer...")
    explainer = lime.lime_tabular.LimeTabularExplainer(
        training_data=X_train,
        feature_names=FEATURE_COLUMNS,
        class_names=['No Churn', 'Churn'],
        mode='classification',
        discretize_continuous=True   # bins continuous features for interpretability
    )
    logger.info("LIME explainer ready!")
    return explainer

def explain_prediction_lime(explainer, model, instance: np.ndarray, num_features: int = 10) -> dict:
    """
    Generates LIME explanation for a single prediction.
    Builds 1000 perturbed samples around the instance, gets RF predictions,
    fits a local linear model, and returns coefficients as feature importances.
    Less stable than SHAP but truly model-agnostic.
    """
    explanation = explainer.explain_instance(
        data_row=instance,
        predict_fn=model.predict_proba,
        num_features=num_features,
        num_samples=1000
    )

    # Extract feature importances for the churn class (index 1)
    lime_weights = explanation.as_list(label=1)

    return {
        "method": "LIME",
        "feature_importances": {
            feature: round(float(weight), 4)
            for feature, weight in lime_weights
        },
        "top_3_reasons": [
            {"feature": feat, "weight": round(float(w), 4)}
            for feat, w in sorted(lime_weights, key=lambda x: float(abs(x[1])), reverse=True)[:3]
        ]
    }

# ─────────────────────────────────────────
# MLflow logging
# ─────────────────────────────────────────

def log_explanations_to_mlflow(shap_summary_path: str, shap_bar_path: str,
                                global_importance: dict):
    """
    Logs SHAP plots and global feature importance to MLflow as artifacts.
    Called after model training to attach explainability artifacts to the run.
    """
    logger.info("Logging explanations to MLflow...")
    with mlflow.start_run(run_name=f"explainability_{datetime.now().strftime('%Y%m%d_%H%M%S')}"):
        mlflow.set_tag("run_type", "explainability")
        mlflow.log_artifact(shap_summary_path)
        mlflow.log_artifact(shap_bar_path)

        # Log top feature importances as metrics for easy comparison across runs
        for feature, importance in list(global_importance.items())[:10]:
            mlflow.log_metric(f"shap_importance_{feature}", importance)

    logger.info("Explanations logged to MLflow!")

if __name__ == "__main__":
    os.makedirs("reports/explainability", exist_ok=True)

    # Load model and data
    model, X_train, y_train = load_model_and_data()

    # Build explainers
    shap_explainer = build_shap_explainer(model, X_train)
    lime_explainer = build_lime_explainer(X_train)

    # ── Test on a single instance ──
    test_instance = X_train[0]
    logger.info(f"Explaining prediction for instance: {dict(zip(FEATURE_COLUMNS, test_instance))}")

    # SHAP explanation
    shap_explanation = explain_prediction_shap(shap_explainer, test_instance)
    logger.info(f"SHAP base value: {shap_explanation['base_value']:.4f}")
    logger.info("Top 3 SHAP reasons for churn prediction:")
    for reason in shap_explanation['top_3_reasons']:
        logger.info(f"  {reason['feature']}: {reason['contribution']:+.4f}")

    # LIME explanation
    lime_explanation = explain_prediction_lime(lime_explainer, model, test_instance)
    logger.info("Top 3 LIME reasons:")
    for reason in lime_explanation['top_3_reasons']:
        logger.info(f"  {reason['feature']}: {reason['weight']:+.4f}")

    # Generate global SHAP plots (use subset for speed)
    sample_size = min(500, len(X_train))
    X_sample = X_train[:sample_size]

    summary_path = "reports/explainability/shap_summary.png"
    bar_path = "reports/explainability/shap_bar.png"

    generate_shap_summary_plot(shap_explainer, X_sample, summary_path)
    generate_shap_bar_plot(shap_explainer, X_sample, bar_path)

    # Compute global importance dict for MLflow
    shap_values = shap_explainer.shap_values(X_sample)
    shap_vals = np.array(shap_values)[:, :, 1]  # class 1 (churn)
    global_importance = dict(zip(
        FEATURE_COLUMNS,
        np.abs(shap_vals).mean(axis=0).tolist()
    ))

    # Log to MLflow
    log_explanations_to_mlflow(summary_path, bar_path, global_importance)

    print("\n" + "="*50)
    print("EXPLAINABILITY SUMMARY")
    print("="*50)
    print(f"SHAP base value (avg prediction): {shap_explanation['base_value']:.4f}")
    print("\nTop features by global SHAP importance:")
    for feat, imp in sorted(global_importance.items(), key=lambda x: x[1], reverse=True)[:5]:
        print(f"  {feat:20s}: {imp:.4f}")
    print("="*50)

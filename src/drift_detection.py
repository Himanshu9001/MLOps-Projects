import pandas as pd
import numpy as np
from evidently import Dataset, DataDefinition, Report
from evidently.presets import DataDriftPreset, DataSummaryPreset
import mlflow
import logging
import os
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

NUMERICAL_FEATURES = ['tenure', 'MonthlyCharges', 'TotalCharges']
CATEGORICAL_FEATURES = [f for f in FEATURE_COLUMNS if f not in NUMERICAL_FEATURES]

def load_reference_data():
    logger.info("Loading reference data...")
    df = pd.read_csv("data/processed/train.csv")
    return df[FEATURE_COLUMNS]

def generate_production_data(n_samples=200):
    logger.info(f"Generating {n_samples} production samples with drift...")
    np.random.seed(42)
    df = pd.read_csv("data/processed/train.csv")
    production_df = df[FEATURE_COLUMNS].sample(n=n_samples, replace=True).copy()

    # Introduce drift
    production_df['tenure'] = production_df['tenure'] * 0.7
    production_df['MonthlyCharges'] = production_df['MonthlyCharges'] * 1.3
    production_df['TotalCharges'] = production_df['TotalCharges'] * 0.9
    production_df['Contract'] = np.random.choice([0, 1, 2], size=n_samples, p=[0.8, 0.1, 0.1])

    return production_df

def run_drift_report(reference_data, production_data, output_dir="reports"):
    logger.info("Running drift detection...")
    os.makedirs(output_dir, exist_ok=True)

    # Define data schema
    data_definition = DataDefinition(
        numerical_columns=NUMERICAL_FEATURES,
        categorical_columns=CATEGORICAL_FEATURES
    )

    # Create datasets
    reference_dataset = Dataset.from_pandas(
        reference_data,
        data_definition=data_definition
    )
    production_dataset = Dataset.from_pandas(
        production_data,
        data_definition=data_definition
    )

    # Run report
    report = Report(metrics=[
        DataDriftPreset(),
        DataSummaryPreset()
    ])

    my_run = report.run(
        reference_data=reference_dataset,
        current_data=production_dataset
    )

    # Save report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    html_path = f"{output_dir}/drift_report_{timestamp}.html"

    # Evidently 0.7.x uses run object to save
    my_run.save_html(html_path)
    logger.info(f"Drift report saved to {html_path}")

    return my_run, html_path

def check_drift_threshold(run, threshold=0.5):
    try:
        result = run.dict()
        drift_detected = False

        for metric in result.get('metrics', []):
            metric_name = metric.get('metric_name', '')
            value = metric.get('value', {})

            if 'DriftedColumnsCount' in metric_name:
                drift_share = value.get('share', 0)
                drift_count = value.get('count', 0)
                logger.info(f"Drifted columns: {int(drift_count)}, share: {drift_share:.3f} (threshold: {threshold})")

                if drift_share > threshold:
                    drift_detected = True
                    logger.warning(f"🚨 DRIFT DETECTED! {int(drift_count)} columns drifted ({drift_share:.1%})")
                else:
                    logger.info(f"✅ No significant drift. {int(drift_count)} columns drifted ({drift_share:.1%})")

        return drift_detected

    except Exception as e:
        logger.warning(f"Could not parse drift threshold: {e}")
        return False
    
def log_drift_to_mlflow(drift_detected, html_path):
    logger.info("Logging drift results to MLflow...")
    with mlflow.start_run(run_name=f"drift_check_{datetime.now().strftime('%Y%m%d_%H%M%S')}"):
        mlflow.set_tag("run_type", "drift_detection")
        mlflow.log_metric("drift_detected", int(drift_detected))
        mlflow.log_artifact(html_path)
    logger.info("Drift results logged to MLflow!")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--mlflow-uri", type=str, default="http://98.86.0.163:5000")
    parser.add_argument("--threshold", type=float, default=0.5)
    args = parser.parse_args()

    mlflow.set_tracking_uri(args.mlflow_uri)
    mlflow.set_experiment("drift-detection")

    reference_data = load_reference_data()
    production_data = generate_production_data(n_samples=200)

    logger.info(f"Reference shape: {reference_data.shape}")
    logger.info(f"Production shape: {production_data.shape}")

    my_run, html_path = run_drift_report(reference_data, production_data)
    drift_detected = check_drift_threshold(my_run, args.threshold)
    log_drift_to_mlflow(drift_detected, html_path)

    print("\n" + "="*50)
    print("DRIFT DETECTION SUMMARY")
    print("="*50)
    print(f"Drift Detected: {'🚨 YES' if drift_detected else '✅ NO'}")
    print(f"Report: {html_path}")
    print("="*50)
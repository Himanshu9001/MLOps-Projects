import mlflow
from mlflow.tracking import MlflowClient
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Model name in registry
MODEL_NAME = "churn-prediction-model"

def get_best_run(experiment_name, metric="roc_auc"):
    logger.info(f"Finding best run from experiment: {experiment_name}")
    client = MlflowClient()

    experiment = client.get_experiment_by_name(experiment_name)
    if not experiment:
        raise ValueError(f"Experiment '{experiment_name}' not found")

    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=[f"metrics.{metric} DESC"],
        filter_string="attributes.status = 'FINISHED' AND tags.model_validated = 'true'"
    )

    if not runs:
        raise ValueError("No validated runs found in experiment")

    best_run = runs[0]
    logger.info(f"Best run ID: {best_run.info.run_id}")
    logger.info(f"Best {metric}: {best_run.data.metrics[metric]:.4f}")
    logger.info(f"Best params: {best_run.data.params}")
    return best_run

# def register_model(run_id, model_name):
#     logger.info(f"Registering model from run: {run_id}")

#     # New MLflow 2.x URI format
#     model_uri = f"runs:/{run_id}/random_forest_model"

#     model_version = mlflow.register_model(
#         model_uri=model_uri,
#         name=model_name
#     )

#     logger.info(f"Model registered: {model_name} v{model_version.version}")
#     return model_version
# def register_model(run_id, model_name):
#     logger.info(f"Registering model from run: {run_id}")
#     client = MlflowClient()

#     model_version = client.create_model_version(
#         name=model_name,
#         source=f"s3://churn-mlops-artifacts/1/models/m-ffa760cc477d45ccaece4463910f6504/artifacts",
#         run_id=run_id,
#         await_creation_for=300
#     )

#     logger.info(f"Model registered: {model_name} v{model_version.version}")
#     return model_version
def register_model(run_id, model_name):
    logger.info(f"Registering model from run: {run_id}")
    client = MlflowClient()

    # Get model artifact path from run
    run = client.get_run(run_id)
    experiment_id = run.info.experiment_id

    # Find model in S3
    artifacts = client.list_artifacts(run_id)
    model_artifacts = [a for a in artifacts if 'models' in a.path or 'model' in a.path.lower()]
    
    # Build S3 source path dynamically
    tracking_uri = mlflow.get_tracking_uri()
    s3_source = f"s3://churn-mlops-artifacts/{experiment_id}/models"
    
    # Find the exact model path
    import boto3
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(
        Bucket='churn-mlops-artifacts',
        Prefix=f"{experiment_id}/models/"
    )
    
    model_prefix = None
    for obj in response.get('Contents', []):
        if 'MLmodel' in obj['Key']:
            model_prefix = '/'.join(obj['Key'].split('/')[:-1])
            break
    
    if not model_prefix:
        raise ValueError(f"No model found in S3 for run {run_id}")

    s3_source = f"s3://churn-mlops-artifacts/{model_prefix}"
    logger.info(f"Model source: {s3_source}")

    model_version = client.create_model_version(
        name=model_name,
        source=s3_source,
        run_id=run_id,
        await_creation_for=300
    )

    logger.info(f"Model registered: {model_name} v{model_version.version}")
    return model_version

def promote_to_staging(model_name, version):
    """Promote model version to Staging using alias."""
    client = MlflowClient()
    client.set_registered_model_alias(
        name=model_name,
        alias="staging",
        version=version
    )
    logger.info(f"Model {model_name} v{version} aliased as 'staging'")

def promote_to_production(model_name, version):
    """Promote model version to Production using alias."""
    client = MlflowClient()
    client.set_registered_model_alias(
        name=model_name,
        alias="production",
        version=version
    )
    logger.info(f"Model {model_name} v{version} aliased as 'production'")

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--run_id", type=str, default=None,
                        help="Specific run ID to register. If not provided, auto-selects best run.")
    args = parser.parse_args()

    if args.run_id:
        # Manual mode — register specific run
        logger.info(f"Manual mode: registering run {args.run_id}")
        model_version = register_model(
            run_id=args.run_id,
            model_name=MODEL_NAME
        )
    else:
        # Auto mode — find best run with artifacts
        logger.info("Auto mode: finding best run...")
        best_run = get_best_run(
            experiment_name="churn-prediction",
            metric="roc_auc"
        )
        model_version = register_model(
            run_id=best_run.info.run_id,
            model_name=MODEL_NAME
        )

    promote_to_staging(MODEL_NAME, model_version.version)
    promote_to_production(MODEL_NAME, model_version.version)

    logger.info("Model registration complete!")
    logger.info("Check MLflow UI → Models tab to see registered model")
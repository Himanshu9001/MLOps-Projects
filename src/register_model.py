import mlflow
from mlflow.tracking import MlflowClient
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Model name in registry
MODEL_NAME = "churn-prediction-model"

def get_best_run(experiment_name, metric="roc_auc"):
    """Find the best run from an experiment based on a metric."""
    logger.info(f"Finding best run from experiment: {experiment_name}")

    client = MlflowClient()

    # Get experiment by name
    experiment = client.get_experiment_by_name(experiment_name)
    if not experiment:
        raise ValueError(f"Experiment '{experiment_name}' not found")

    # Search all runs in experiment, order by metric descending
    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=[f"metrics.{metric} DESC"]
    )

    if not runs:
        raise ValueError("No runs found in experiment")

    best_run = runs[0]
    logger.info(f"Best run ID: {best_run.info.run_id}")
    logger.info(f"Best {metric}: {best_run.data.metrics[metric]:.4f}")
    logger.info(f"Best params: {best_run.data.params}")

    return best_run

def register_model(run_id, model_name):
    """Register a model from a run to the Model Registry."""
    logger.info(f"Registering model from run: {run_id}")

    # Model URI points to the logged model inside the run
    model_uri = f"runs:/{run_id}/random_forest_model"

    # Register the model
    model_version = mlflow.register_model(
        model_uri=model_uri,
        name=model_name
    )

    logger.info(f"Model registered: {model_name} v{model_version.version}")
    return model_version

def promote_to_staging(model_name, version):
    """Promote model version to Staging using alias."""
    client = MlflowClient()

    # New way — use aliases instead of stages
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
    # Step 1: Find best run
    best_run = get_best_run(
        experiment_name="churn-prediction",
        metric="roc_auc"
    )

    # Step 2: Register the best model
    model_version = register_model(
        run_id=best_run.info.run_id,
        model_name=MODEL_NAME
    )

    # Step 3: Promote to Staging first
    promote_to_staging(
        model_name=MODEL_NAME,
        version=model_version.version
    )

    # Step 4: Promote to Production
    promote_to_production(
        model_name=MODEL_NAME,
        version=model_version.version
    )

    logger.info("Model registration complete!")
    logger.info(f"Check MLflow UI → Models tab to see registered model")
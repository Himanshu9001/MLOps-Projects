"""
Data quality validation using Great Expectations.
Called as the first task in the churn_retraining Airflow DAG.
Validates raw/processed data before it enters the training pipeline.
Saves validation report to S3 for audit trail.
"""
import great_expectations as gx
import pandas as pd
import boto3
import json
import os
import logging
from datetime import datetime

logging.getLogger("great_expectations").setLevel(logging.WARNING)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

S3_BUCKET = os.getenv("S3_BUCKET", "churn-mlops-artifacts")
DATA_PATH = os.getenv("DATA_PATH", "data/processed/train.csv")

def build_expectation_suite(context):
    """Builds and returns the churn data quality expectation suite."""
    suite = context.suites.add(
        gx.ExpectationSuite(name="churn_data_quality_suite")
    )

    REQUIRED_COLUMNS = [
        "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
        "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
        "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
        "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
        "MonthlyCharges", "TotalCharges", "Churn"
    ]
    for col in REQUIRED_COLUMNS:
        suite.add_expectation(gx.expectations.ExpectColumnToExist(column=col))

    for col in ["tenure", "MonthlyCharges", "TotalCharges", "Churn"]:
        suite.add_expectation(gx.expectations.ExpectColumnValuesToNotBeNull(column=col))

    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeBetween(
        column="tenure", min_value=0, max_value=100))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeBetween(
        column="MonthlyCharges", min_value=0, max_value=200))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeBetween(
        column="TotalCharges", min_value=0, max_value=10000))

    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeInSet(
        column="Contract", value_set=[0, 1, 2]))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeInSet(
        column="Churn", value_set=[0, 1]))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeInSet(
        column="gender", value_set=[0, 1]))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeInSet(
        column="InternetService", value_set=[0, 1, 2]))
    suite.add_expectation(gx.expectations.ExpectColumnValuesToBeInSet(
        column="PaymentMethod", value_set=[0, 1, 2, 3]))

    suite.add_expectation(gx.expectations.ExpectTableRowCountToBeBetween(
        min_value=1000, max_value=None))
    suite.add_expectation(gx.expectations.ExpectTableColumnCountToEqual(value=20))

    return suite

def save_report_to_s3(validation_result, s3_bucket):
    """Saves validation result summary as JSON to S3 for audit trail."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    s3_key = f"great_expectations/validation_results/result_{timestamp}.json"

    # Build summary report
    results = validation_result.results
    report = {
        "timestamp": timestamp,
        "success": validation_result.success,
        "statistics": {
            "evaluated_expectations": len(results),
            "successful_expectations": sum(1 for r in results if r.success),
            "unsuccessful_expectations": sum(1 for r in results if not r.success),
        },
        "failed_expectations": [
            {
                "expectation_type": r.expectation_config.type,
                "column": r.expectation_config.kwargs.get("column", "table"),
                "kwargs": r.expectation_config.kwargs,
            }
            for r in results if not r.success
        ]
    }

    s3 = boto3.client("s3", region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
    s3.put_object(
        Bucket=s3_bucket,
        Key=s3_key,
        Body=json.dumps(report, indent=2),
        ContentType="application/json"
    )
    logger.info(f"Validation report saved to s3://{s3_bucket}/{s3_key}")
    return s3_key

def validate_data(data_path=DATA_PATH, s3_bucket=S3_BUCKET):
    """
    Main validation function — loads data, runs GE suite, saves report to S3.
    Raises ValueError if validation fails, stopping the pipeline.
    """
    logger.info(f"Starting data validation for: {data_path}")

    # Load data
    if data_path.startswith("s3://"):
        # Load from S3
        parts = data_path.replace("s3://", "").split("/", 1)
        s3 = boto3.client("s3", region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
        obj = s3.get_object(Bucket=parts[0], Key=parts[1])
        df = pd.read_csv(obj["Body"])
    else:
        df = pd.read_csv(data_path)

    logger.info(f"Loaded data: {df.shape[0]} rows, {df.shape[1]} columns")

    # Build GE context and suite
    context = gx.get_context(mode="ephemeral")
    data_source = context.data_sources.add_pandas("churn_datasource")
    data_asset = data_source.add_dataframe_asset("churn_data")
    batch_definition = data_asset.add_batch_definition_whole_dataframe("full_batch")

    suite = build_expectation_suite(context)

    validation_definition = context.validation_definitions.add(
        gx.ValidationDefinition(
            name="churn_validation",
            data=batch_definition,
            suite=suite
        )
    )

    # Run validation
    validation_result = validation_definition.run(
        batch_parameters={"dataframe": df}
    )

    # Save report to S3
    results = validation_result.results
    passed = sum(1 for r in results if r.success)
    failed = sum(1 for r in results if not r.success)

    logger.info(f"Validation complete — Passed: {passed}/{len(results)}, Failed: {failed}/{len(results)}")

    try:
        save_report_to_s3(validation_result, s3_bucket)
    except Exception as e:
        logger.warning(f"Could not save report to S3: {e}")

    # Fail fast — raise exception to stop Airflow pipeline
    if not validation_result.success:
        failed_details = [
            f"{r.expectation_config.type} on '{r.expectation_config.kwargs.get('column', 'table')}'"
            for r in results if not r.success
        ]
        raise ValueError(
            f"Data validation failed! {failed} expectations failed:\n" +
            "\n".join(f"  ❌ {d}" for d in failed_details)
        )

    logger.info("✅ Data validation passed — pipeline can proceed")
    return validation_result

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-path", type=str, default=DATA_PATH)
    parser.add_argument("--s3-bucket", type=str, default=S3_BUCKET)
    args = parser.parse_args()

    validate_data(data_path=args.data_path, s3_bucket=args.s3_bucket)

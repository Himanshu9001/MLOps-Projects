"""
Creates and saves a Great Expectations suite for the Telco Churn dataset.
Defines expectations for all 19 features + target column.
Run once to generate the suite, then use validate.py for ongoing validation.
"""
import great_expectations as gx
import pandas as pd

def create_churn_expectation_suite():
    # Initialize GE Data Context — manages suites, checkpoints, and data docs
    context = gx.get_context(mode="ephemeral")

    # Load sample data to build expectations against
    df = pd.read_csv("data/processed/train.csv")

    # Create a Data Source pointing to pandas dataframe
    data_source = context.data_sources.add_pandas("churn_datasource")
    data_asset = data_source.add_dataframe_asset("churn_train")
    batch_definition = data_asset.add_batch_definition_whole_dataframe("full_batch")

    # Create expectation suite
    suite = context.suites.add(
        gx.ExpectationSuite(name="churn_data_quality_suite")
    )

    # ─────────────────────────────────────────
    # Schema expectations — columns must exist
    # ─────────────────────────────────────────
    REQUIRED_COLUMNS = [
        "gender", "SeniorCitizen", "Partner", "Dependents", "tenure",
        "PhoneService", "MultipleLines", "InternetService", "OnlineSecurity",
        "OnlineBackup", "DeviceProtection", "TechSupport", "StreamingTV",
        "StreamingMovies", "Contract", "PaperlessBilling", "PaymentMethod",
        "MonthlyCharges", "TotalCharges", "Churn"
    ]
    for col in REQUIRED_COLUMNS:
        suite.add_expectation(
            gx.expectations.ExpectColumnToExist(column=col)
        )

    # ─────────────────────────────────────────
    # Null checks — critical columns must be complete
    # ─────────────────────────────────────────
    NOT_NULL_COLUMNS = ["tenure", "MonthlyCharges", "TotalCharges", "Churn"]
    for col in NOT_NULL_COLUMNS:
        suite.add_expectation(
            gx.expectations.ExpectColumnValuesToNotBeNull(column=col)
        )

    # ─────────────────────────────────────────
    # Range checks — numerical columns
    # ─────────────────────────────────────────
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeBetween(
            column="tenure", min_value=0, max_value=100
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeBetween(
            column="MonthlyCharges", min_value=0, max_value=200
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeBetween(
            column="TotalCharges", min_value=0, max_value=10000
        )
    )

    # ─────────────────────────────────────────
    # Categorical checks — encoded columns must have valid values
    # ─────────────────────────────────────────
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="Contract", value_set=[0, 1, 2]
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="Churn", value_set=[0, 1]
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="gender", value_set=[0, 1]
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="InternetService", value_set=[0, 1, 2]
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToBeInSet(
            column="PaymentMethod", value_set=[0, 1, 2, 3]
        )
    )

    # ─────────────────────────────────────────
    # Dataset-level checks
    # ─────────────────────────────────────────
    suite.add_expectation(
        gx.expectations.ExpectTableRowCountToBeBetween(
            min_value=1000, max_value=None
        )
    )
    suite.add_expectation(
        gx.expectations.ExpectTableColumnCountToEqual(value=20)
    )

    # ─────────────────────────────────────────
    # Create validation definition and run
    # ─────────────────────────────────────────
    validation_definition = context.validation_definitions.add(
        gx.ValidationDefinition(
            name="churn_validation",
            data=batch_definition,
            suite=suite
        )
    )

    # Run validation against the training data
    batch = batch_definition.get_batch(
        batch_parameters={"dataframe": df}
    )
    validation_result = validation_definition.run(
        batch_parameters={"dataframe": df}
    )

    return validation_result, suite

if __name__ == "__main__":
    validation_result, suite = create_churn_expectation_suite()

    print(f"\n{'='*50}")
    print("VALIDATION RESULTS")
    print(f"{'='*50}")
    print(f"Success: {validation_result.success}")
    results = validation_result.results
    passed = sum(1 for r in results if r.success)
    failed = sum(1 for r in results if not r.success)
    print(f"Passed:  {passed}/{len(results)}")
    print(f"Failed:  {failed}/{len(results)}")
    if not validation_result.success:
        print("\nFailed expectations:")
        for r in results:
            if not r.success:
                print(f"  ❌ {r.expectation_config.type} on "
                      f"column '{r.expectation_config.kwargs.get('column', 'table')}'")
    else:
        print("\n✅ All expectations passed — data is valid!")

import os
import logging
from feast import FeatureStore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

FEATURE_REPO_PATH = os.getenv(
    "FEATURE_REPO_PATH",
    "feature_store/churn_feature_repo/feature_repo"
)

CUSTOMER_FEATURES = [
    "customer_churn_features:gender",
    "customer_churn_features:SeniorCitizen",
    "customer_churn_features:Partner",
    "customer_churn_features:Dependents",
    "customer_churn_features:tenure",
    "customer_churn_features:PhoneService",
    "customer_churn_features:MultipleLines",
    "customer_churn_features:InternetService",
    "customer_churn_features:OnlineSecurity",
    "customer_churn_features:OnlineBackup",
    "customer_churn_features:DeviceProtection",
    "customer_churn_features:TechSupport",
    "customer_churn_features:StreamingTV",
    "customer_churn_features:StreamingMovies",
    "customer_churn_features:Contract",
    "customer_churn_features:PaperlessBilling",
    "customer_churn_features:PaymentMethod",
    "customer_churn_features:MonthlyCharges",
    "customer_churn_features:TotalCharges",
]

def get_customer_features(customer_ids: list[str]) -> list[dict]:
    """
    Retrieve features for a list of customer IDs from the online store.
    Returns a list of feature dicts ready for model prediction.
    """
    store = FeatureStore(repo_path=FEATURE_REPO_PATH)

    feature_vector = store.get_online_features(
        features=CUSTOMER_FEATURES,
        entity_rows=[{"customer_id": cid} for cid in customer_ids]
    ).to_dict()

    results = []
    for i, customer_id in enumerate(customer_ids):
        features = {
            key.replace("customer_churn_features:", ""): values[i]
            for key, values in feature_vector.items()
            if key != "customer_id"
        }
        results.append({
            "customer_id": customer_id,
            "features": features
        })
        logger.info(f"Retrieved features for {customer_id}: tenure={features.get('tenure')}")

    return results

if __name__ == "__main__":
    # Test retrieval
    customers = ["cust_0000", "cust_0001", "cust_0002"]
    results = get_customer_features(customers)
    for r in results:
        print(f"Customer {r['customer_id']}: {r['features']}")

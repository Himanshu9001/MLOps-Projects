from datetime import timedelta
from feast import Entity, FeatureView, Field, FileSource, PushSource
from feast.types import Float32, Int32

# ─────────────────────────────────────────
# Entity
# ─────────────────────────────────────────
customer = Entity(
    name="customer_id",
    description="Unique customer identifier"
)

# ─────────────────────────────────────────
# Offline Source — S3 parquet
# ─────────────────────────────────────────
customer_stats_source = FileSource(
    path="s3://churn-mlops-artifacts/feast/customer_features.parquet",
    timestamp_field="event_timestamp"
)

# ─────────────────────────────────────────
# Push Source — for real-time feature updates
# Used when customer data changes and needs
# immediate update in online store (Redis)
# ─────────────────────────────────────────
customer_push_source = PushSource(
    name="customer_push_source",
    batch_source=customer_stats_source
)

# ─────────────────────────────────────────
# Feature View
# ─────────────────────────────────────────
customer_churn_features = FeatureView(
    name="customer_churn_features",
    entities=[customer],
    ttl=timedelta(days=7),
    schema=[
        Field(name="gender", dtype=Int32),
        Field(name="SeniorCitizen", dtype=Int32),
        Field(name="Partner", dtype=Int32),
        Field(name="Dependents", dtype=Int32),
        Field(name="tenure", dtype=Int32),
        Field(name="PhoneService", dtype=Int32),
        Field(name="MultipleLines", dtype=Int32),
        Field(name="InternetService", dtype=Int32),
        Field(name="OnlineSecurity", dtype=Int32),
        Field(name="OnlineBackup", dtype=Int32),
        Field(name="DeviceProtection", dtype=Int32),
        Field(name="TechSupport", dtype=Int32),
        Field(name="StreamingTV", dtype=Int32),
        Field(name="StreamingMovies", dtype=Int32),
        Field(name="Contract", dtype=Int32),
        Field(name="PaperlessBilling", dtype=Int32),
        Field(name="PaymentMethod", dtype=Int32),
        Field(name="MonthlyCharges", dtype=Float32),
        Field(name="TotalCharges", dtype=Float32),
    ],
    source=customer_push_source,
    description="Customer features for churn prediction"
)

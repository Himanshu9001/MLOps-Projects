import boto3
import pandas as pd
import redis
import io
import os

print("Starting feature materialization...")

REDIS_HOST = os.getenv("REDIS_HOST", "redis-master.redis.svc.cluster.local")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
S3_BUCKET = os.getenv("S3_BUCKET", "churn-mlops-artifacts")
S3_KEY = os.getenv("S3_KEY", "feast/customer_features.parquet")

# Connect to Redis
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)
r.ping()
print(f"Redis connected at {REDIS_HOST}:{REDIS_PORT}")

# Load from S3
s3 = boto3.client("s3", region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
obj = s3.get_object(Bucket=S3_BUCKET, Key=S3_KEY)
df = pd.read_parquet(io.BytesIO(obj["Body"].read()))
print(f"Loaded {len(df)} records from s3://{S3_BUCKET}/{S3_KEY}")

# Write to Redis
pipe = r.pipeline()
count = 0
for _, row in df.iterrows():
    key = f"feast:customer:{row['customer_id']}"
    features = {
        col: str(row[col])
        for col in df.columns
        if col not in ["customer_id", "event_timestamp"]
    }
    pipe.hset(key, mapping=features)
    pipe.expire(key, 7 * 24 * 3600)
    count += 1
    if count % 500 == 0:
        pipe.execute()
        pipe = r.pipeline()
        print(f"Progress: {count}/{len(df)} records materialized...")

pipe.execute()
print(f"Feature materialization complete! {count} customers updated in Redis.")

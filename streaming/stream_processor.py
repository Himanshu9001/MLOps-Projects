import os
import json
import time
import logging
import requests
import redis
from confluent_kafka import Consumer, Producer, KafkaError, KafkaException

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────
# Configuration from environment variables
# ─────────────────────────────────────────
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "churn-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092")
REDIS_HOST = os.getenv("REDIS_HOST", "redis-master.redis.svc.cluster.local")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
API_URL = os.getenv("API_URL", "http://churn-prediction-api.churn-mlops.svc.cluster.local:8000")
INPUT_TOPIC = os.getenv("INPUT_TOPIC", "customer-events")
OUTPUT_TOPIC = os.getenv("OUTPUT_TOPIC", "churn-alerts")
CONSUMER_GROUP = os.getenv("CONSUMER_GROUP", "churn-stream-processor")
HIGH_RISK_THRESHOLD = float(os.getenv("HIGH_RISK_THRESHOLD", "0.7"))

def connect_producer():
    logger.info(f"Connecting Kafka producer to {KAFKA_BOOTSTRAP}")
    producer = Producer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "client.id": "churn-stream-producer",
        "acks": "all",
        "retries": 3
    })
    logger.info("Kafka producer ready!")
    return producer

def connect_consumer():
    logger.info(f"Connecting Kafka consumer to {KAFKA_BOOTSTRAP}")
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": CONSUMER_GROUP,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": True,
        "client.id": "churn-stream-consumer"
    })
    consumer.subscribe([INPUT_TOPIC])
    logger.info(f"Kafka consumer subscribed to {INPUT_TOPIC}")
    return consumer

def connect_redis():
    logger.info(f"Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}")
    while True:
        try:
            r = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                decode_responses=True,
                socket_connect_timeout=5
            )
            r.ping()
            logger.info("Redis connected!")
            return r
        except Exception as e:
            logger.warning(f"Redis not ready: {e}. Retrying in 5s...")
            time.sleep(5)

def predict(customer_data):
    try:
        response = requests.post(
            f"{API_URL}/predict",
            json=customer_data,
            timeout=5
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        logger.error(f"Prediction failed: {e}")
        return None

def cache_prediction(r, customer_id, prediction):
    key = f"churn:prediction:{customer_id}"
    r.setex(key, 3600, json.dumps(prediction))

def delivery_report(err, msg):
    if err is not None:
        logger.error(f"Message delivery failed: {err}")
    else:
        logger.info(f"Alert delivered to {msg.topic()} partition {msg.partition()}")

def process_stream():
    producer = connect_producer()
    consumer = connect_consumer()
    r = connect_redis()

    logger.info("Starting stream processing...")
    processed = 0
    alerts = 0

    try:
        while True:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.info(f"Reached end of partition {msg.partition()}")
                else:
                    raise KafkaException(msg.error())
                continue

            try:
                event = json.loads(msg.value().decode("utf-8"))
                customer_id = event.get("customer_id", "unknown")
                customer_data = event.get("features", {})

                logger.info(f"Processing customer: {customer_id}")

                prediction = predict(customer_data)
                if not prediction:
                    continue

                cache_prediction(r, customer_id, prediction)
                processed += 1

                if prediction.get("probability", 0) >= HIGH_RISK_THRESHOLD:
                    alert = {
                        "customer_id": customer_id,
                        "churn_probability": prediction["probability"],
                        "risk_level": prediction["risk_level"],
                        "timestamp": time.time(),
                        "action": "IMMEDIATE_RETENTION_REQUIRED"
                    }
                    producer.produce(
                        OUTPUT_TOPIC,
                        value=json.dumps(alert).encode("utf-8"),
                        callback=delivery_report
                    )
                    producer.poll(0)
                    alerts += 1
                    logger.warning(
                        f"HIGH RISK ALERT: customer {customer_id} "
                        f"- probability {prediction['probability']:.2%}"
                    )

                if processed % 10 == 0:
                    logger.info(f"Stats: processed={processed}, alerts={alerts}")

            except json.JSONDecodeError as e:
                logger.error(f"Failed to decode message: {e}")
            except Exception as e:
                logger.error(f"Error processing message: {e}")

    except KeyboardInterrupt:
        logger.info("Shutting down stream processor...")
    finally:
        producer.flush()
        consumer.close()
        logger.info("Stream processor stopped cleanly")

if __name__ == "__main__":
    process_stream()

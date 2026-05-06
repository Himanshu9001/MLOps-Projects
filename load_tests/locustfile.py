"""
Load testing for Churn Prediction API using Locust.
Tests four scenarios: baseline, normal load, stress, and spike.

Run:
  locust -f load_tests/locustfile.py --host http://<ALB_URL>
  Then open http://localhost:8089 for the web UI.

Headless (CI/CD):
  locust -f load_tests/locustfile.py --host http://<ALB_URL> \
    --headless --users 50 --spawn-rate 5 --run-time 60s \
    --csv load_tests/results/normal_load
"""
import random
import json
from locust import HttpUser, task, between, events
from locust.runners import MasterRunner
import logging

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────
# Realistic customer payload generator
# Generates varied customer profiles to simulate real traffic
# Using fixed ranges based on actual Telco Churn dataset distributions
# ─────────────────────────────────────────

def generate_high_risk_customer() -> dict:
    """Generates a customer profile likely to churn — Month-to-month, high charges, short tenure."""
    return {
        "gender": random.randint(0, 1),
        "SeniorCitizen": random.randint(0, 1),
        "Partner": 0,
        "Dependents": 0,
        "tenure": random.randint(1, 12),          # short tenure = higher churn risk
        "PhoneService": 1,
        "MultipleLines": random.randint(0, 2),
        "InternetService": 1,                      # fiber optic = higher charges
        "OnlineSecurity": 0,                       # no security = higher churn
        "OnlineBackup": 0,
        "DeviceProtection": 0,
        "TechSupport": 0,                          # no support = higher churn
        "StreamingTV": random.randint(0, 2),
        "StreamingMovies": random.randint(0, 2),
        "Contract": 0,                             # month-to-month = highest churn
        "PaperlessBilling": 1,
        "PaymentMethod": 2,                        # electronic check = higher churn
        "MonthlyCharges": round(random.uniform(70, 110), 2),
        "TotalCharges": round(random.uniform(70, 1320), 2),
    }

def generate_low_risk_customer() -> dict:
    """Generates a customer profile unlikely to churn — long tenure, annual contract."""
    return {
        "gender": random.randint(0, 1),
        "SeniorCitizen": 0,
        "Partner": 1,
        "Dependents": random.randint(0, 1),
        "tenure": random.randint(24, 72),          # long tenure = lower churn risk
        "PhoneService": 1,
        "MultipleLines": random.randint(0, 2),
        "InternetService": random.randint(0, 2),
        "OnlineSecurity": 2,                       # has security = lower churn
        "OnlineBackup": random.randint(0, 2),
        "DeviceProtection": random.randint(0, 2),
        "TechSupport": 2,                          # has support = lower churn
        "StreamingTV": random.randint(0, 2),
        "StreamingMovies": random.randint(0, 2),
        "Contract": random.randint(1, 2),          # annual/two-year = lower churn
        "PaperlessBilling": random.randint(0, 1),
        "PaymentMethod": random.randint(0, 3),
        "MonthlyCharges": round(random.uniform(20, 60), 2),
        "TotalCharges": round(random.uniform(500, 5000), 2),
    }

def generate_random_customer() -> dict:
    """Generates a random customer profile for mixed traffic simulation."""
    return random.choice([generate_high_risk_customer, generate_low_risk_customer])()


# ─────────────────────────────────────────
# User behavior classes
# Each class = one type of simulated user
# task weight = relative frequency of that task
# between(min, max) = think time between requests (simulates real user behavior)
# ─────────────────────────────────────────

class PredictionUser(HttpUser):
    """
    Simulates a typical API consumer — mostly predictions, occasional health checks.
    wait_time = simulates think time between requests (1-3 seconds).
    This is the primary user type for normal load and stress tests.
    """
    wait_time = between(1, 3)

    @task(10)
    def predict_random(self):
        """Makes a prediction request with a random customer profile."""
        payload = generate_random_customer()
        with self.client.post(
            "/predict",
            json=payload,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                result = response.json()
                # Validate response structure — catches silent API regressions
                if "churn" not in result or "probability" not in result:
                    response.failure("Response missing required fields")
                else:
                    response.success()
            else:
                response.failure(f"HTTP {response.status_code}: {response.text[:100]}")

    @task(3)
    def predict_high_risk(self):
        """Sends high-risk customer profiles — tests model behavior under skewed input."""
        payload = generate_high_risk_customer()
        with self.client.post(
            "/predict",
            json=payload,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                result = response.json()
                response.success()
                # Log if high-risk customer not flagged — model sanity check
                if result.get("risk_level") == "LOW":
                    logger.warning(f"High-risk profile returned LOW risk: {result['probability']}")
            else:
                response.failure(f"HTTP {response.status_code}")

    @task(1)
    def health_check(self):
        """Periodic health checks — simulates monitoring probes."""
        with self.client.get("/health", catch_response=True) as response:
            if response.status_code == 200:
                data = response.json()
                if not data.get("model_loaded"):
                    response.failure("Model not loaded!")
                else:
                    response.success()
            else:
                response.failure(f"Health check failed: {response.status_code}")


class HeavyPredictionUser(HttpUser):
    """
    Simulates a batch scoring client — rapid predictions with minimal think time.
    Used for stress testing — represents downstream systems calling the API in bulk.
    """
    wait_time = between(0.1, 0.5)

    @task
    def rapid_predict(self):
        """Rapid-fire predictions with minimal delay — stress test scenario."""
        payload = generate_random_customer()
        with self.client.post(
            "/predict",
            json=payload,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            elif response.status_code == 503:
                response.failure("Service unavailable — model not loaded or pod restarting")
            else:
                response.failure(f"HTTP {response.status_code}")


# ─────────────────────────────────────────
# Event hooks — custom logging at test start/end
# ─────────────────────────────────────────

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    logger.info("="*50)
    logger.info("Load test starting...")
    logger.info(f"Target: {environment.host}")
    logger.info("="*50)

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    stats = environment.stats.total
    logger.info("="*50)
    logger.info("LOAD TEST RESULTS")
    logger.info(f"Total requests:    {stats.num_requests}")
    logger.info(f"Failed requests:   {stats.num_failures}")
    logger.info(f"Failure rate:      {stats.fail_ratio*100:.2f}%")
    logger.info(f"Avg response time: {stats.avg_response_time:.2f}ms")
    logger.info(f"p95 response time: {stats.get_response_time_percentile(0.95):.2f}ms")
    logger.info(f"p99 response time: {stats.get_response_time_percentile(0.99):.2f}ms")
    logger.info(f"Max RPS achieved:  {stats.max_rps:.2f}")
    logger.info("="*50)

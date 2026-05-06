# Load Tests — Churn Prediction API

## Running tests

### Web UI (interactive)
```bash
locust -f load_tests/locustfile.py \
  --host http://a3bb3c740fb3747d88b007cade5f9bd4-405783512.us-east-1.elb.amazonaws.com
```
Open http://localhost:8089

### Headless (CI/CD)
```bash
# Baseline — 10 users
locust -f load_tests/locustfile.py \
  --host http://<ALB_URL> \
  --headless --users 10 --spawn-rate 2 --run-time 30s \
  --csv load_tests/results/baseline

# Normal load — 50 users
locust -f load_tests/locustfile.py \
  --host http://<ALB_URL> \
  --headless --users 50 --spawn-rate 5 --run-time 60s \
  --csv load_tests/results/normal_load

# Stress — 200 users
locust -f load_tests/locustfile.py \
  --host http://<ALB_URL> \
  --headless --users 200 --spawn-rate 10 --run-time 120s \
  --csv load_tests/results/stress
```

## SLA targets
| Metric | Target |
|--------|--------|
| p95 latency | < 500ms |
| p99 latency | < 1000ms |
| Failure rate | < 1% |
| Min RPS | > 20 |

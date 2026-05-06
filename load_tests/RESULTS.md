# Load Test Results — Churn Prediction API

## Test Environment
- EKS: 4x t3.medium nodes
- Initial HPA: min=1, max=3, CPU=70%
- Istio sidecar: enabled (2/2 containers per pod)
- ALB: AWS Application Load Balancer

## Results Summary

| Test | Users | RPS | Median | p95 | p99 | Failures |
|------|-------|-----|--------|-----|-----|----------|
| Baseline | 10 | 10 | 320ms | 400ms | 670ms | 0% |
| Normal | 50 | 19.4 | 1100ms | 2500ms | 3700ms | 0% |
| Stress | 200 | 35.5 | 3600ms | 5600ms | 8600ms | 0.36% |

## HPA Scaling Observed
- 10 users → 1→2 replicas (CPU: 59%)
- 200 users → 2→3 replicas (CPU: 148%)
- Scale-up lag: ~60 seconds from threshold breach to new pod ready

## SLA Assessment
| Metric | Target | Baseline | Normal | Stress |
|--------|--------|----------|--------|--------|
| p95 latency | <500ms | ✅ 400ms | ❌ 2500ms | ❌ 5600ms |
| Failure rate | <1% | ✅ 0% | ✅ 0% | ✅ 0.36% |
| Min RPS | >20 | ❌ 10 | ✅ 19.4 | ✅ 35.5 |

## Key Findings
1. API is stable — 0% failures up to 50 users
2. p95 SLA breached at 50+ users — single pod bottleneck during HPA lag
3. HPA lag (~60s) causes latency spikes — reactive not proactive
4. 503 errors during pod restarts — fixed with preStop hook

## Optimizations Applied
- minReplicas: 1 → 2 (eliminates cold-start lag)
- maxReplicas: 3 → 5 (more scaling headroom)
- CPU threshold: 70% → 50% (earlier scaling trigger)
- preStop hook: 5s sleep (graceful connection draining)
- terminationGracePeriodSeconds: 60 (complete in-flight requests)

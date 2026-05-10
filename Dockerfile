# ─────────────────────────────────────────
# Stage 1 — Builder
# ─────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# CHANGE 1: Added apt-get upgrade -y
# Patches all OS-level CVEs that have upstream fixes available
# Without this, Trivy fails on libssl/libexpat/zlib in base image
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY requirements-api.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements-api.txt

# ─────────────────────────────────────────
# Stage 2 — Runtime
# ─────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

# CHANGE 1 (continued): apt-get upgrade in runtime stage too
# Trivy scans the FINAL image — builder upgrades don't carry over
# CHANGE 2: curl removed entirely
#   - libcurl is a direct CVE source (Trivy flags it)
#   - curl is a post-exploitation tool (attacker can wget payloads)
#   - Python stdlib urllib replaces it with zero new dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local

# CHANGE 3: /sbin/nologin replaces /bin/bash
# /bin/bash allows interactive shell if someone kubectl exec's in
# /sbin/nologin explicitly rejects login — industry standard for service accounts
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 \
            --gid appgroup \
            --shell /sbin/nologin \
            --no-create-home \
            appuser

COPY --chown=appuser:appgroup app/ ./app/

USER appuser

# CHANGE 2 (continued): Pure Python healthcheck — no curl binary
# urllib.request is Python stdlib — zero attack surface added
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=40s \
            --retries=3 \
            CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000

# CHANGE 4: --workers 1 instead of 2
# You have HPA scaling pods — uvicorn workers inside a pod cause:
#   - Prometheus counters split across worker processes (metric gaps)
#   - Resource limits sized per pod, not per worker (OOMKill risk)
# Let HPA do horizontal scaling at pod level
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "1", \
     "--log-level", "info", \
     "--access-log"]

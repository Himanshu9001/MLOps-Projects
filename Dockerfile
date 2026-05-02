# ─────────────────────────────────────────
# Stage 1 — Builder
# ─────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy minimal API requirements only
COPY requirements-api.txt .

# Install into /install directory
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements-api.txt

# ─────────────────────────────────────────
# Stage 2 — Runtime
# ─────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

# Fix — set PYTHONPATH after /install is copied
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install only runtime system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Set PYTHONPATH after copy
ENV PYTHONPATH=/app

# Create non-root user
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 \
            --gid appgroup \
            --shell /bin/bash \
            --no-create-home \
            appuser

# Copy app code with correct ownership
COPY --chown=appuser:appgroup app/ ./app/

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=40s \
            --retries=3 \
            CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "2", \
     "--log-level", "info", \
     "--access-log"]
import mlflow
import mlflow.sklearn
import pandas as pd
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import logging
import os
from contextlib import asynccontextmanager
from prometheus_fastapi_instrumentator import Instrumentator

# ─────────────────────────────────────────
# OpenTelemetry — Distributed Tracing
# Traces every prediction request end-to-end
# Sends to Tempo via OTLP gRPC (port 4317)
# ─────────────────────────────────────────
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource

def setup_tracing():
    resource = Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "churn-prediction-api"),
        "service.version": "1.0.0",
        "deployment.environment": os.getenv("ENVIRONMENT", "nonprod"),
    })
    provider = TracerProvider(resource=resource)
    otlp_endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "http://tempo.monitoring:4317"
    )
    exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    return trace.get_tracer(__name__)

tracer = setup_tracing()

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Global model variable
model = None

# ─────────────────────────────────────────
# Pydantic Schema — defines input structure
# ─────────────────────────────────────────
class CustomerFeatures(BaseModel):
    gender: int = Field(..., description="0=Female, 1=Male")
    SeniorCitizen: int = Field(..., description="0=No, 1=Yes")
    Partner: int = Field(..., description="0=No, 1=Yes")
    Dependents: int = Field(..., description="0=No, 1=Yes")
    tenure: int = Field(..., description="Months with company")
    PhoneService: int = Field(..., description="0=No, 1=Yes")
    MultipleLines: int = Field(..., description="0=No, 1=No phone service, 2=Yes")
    InternetService: int = Field(..., description="0=DSL, 1=Fiber optic, 2=No")
    OnlineSecurity: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    OnlineBackup: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    DeviceProtection: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    TechSupport: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    StreamingTV: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    StreamingMovies: int = Field(..., description="0=No, 1=No internet service, 2=Yes")
    Contract: int = Field(..., description="0=Month-to-month, 1=One year, 2=Two year")
    PaperlessBilling: int = Field(..., description="0=No, 1=Yes")
    PaymentMethod: int = Field(..., description="0=Bank transfer, 1=Credit card, 2=Electronic check, 3=Mailed check")
    MonthlyCharges: float = Field(..., description="Monthly bill amount")
    TotalCharges: float = Field(..., description="Total billed so far")

class PredictionResponse(BaseModel):
    churn: int
    probability: float
    risk_level: str
    message: str

# ─────────────────────────────────────────
# Load model on startup
# ─────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    await load_model()
    yield

app = FastAPI(
    title="Churn Prediction API",
    description="Predicts customer churn using a Random Forest model",
    version="1.0.0",
    lifespan=lifespan
)

Instrumentator().instrument(app).expose(app)

# Auto-instrument all HTTP requests
FastAPIInstrumentor.instrument_app(app)

async def load_model():
    global model
    try:
        logger.info("Loading model from MLflow Registry...")
        model = mlflow.sklearn.load_model("models:/churn-prediction-model@production")
        logger.info("Model loaded successfully!")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise RuntimeError(f"Model loading failed: {e}")

# ─────────────────────────────────────────
# Health check endpoint
# ─────────────────────────────────────────
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": model is not None
    }

# ─────────────────────────────────────────
# Prediction endpoint — with custom spans
# ─────────────────────────────────────────
@app.post("/predict", response_model=PredictionResponse)
async def predict(customer: CustomerFeatures):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    with tracer.start_as_current_span("predict") as span:
        span.set_attribute("customer.tenure", customer.tenure)
        span.set_attribute("customer.contract", customer.Contract)
        span.set_attribute("customer.monthly_charges", customer.MonthlyCharges)

        try:
            with tracer.start_as_current_span("preprocess"):
                input_data = pd.DataFrame([customer.model_dump()])
                logger.info(f"Received prediction request for tenure={customer.tenure}")

            with tracer.start_as_current_span("model_inference"):
                churn_pred = int(model.predict(input_data)[0])
                churn_prob = float(model.predict_proba(input_data)[0][1])

            with tracer.start_as_current_span("risk_classification"):
                if churn_prob >= 0.7:
                    risk_level = "HIGH"
                    message = "Customer is very likely to churn. Immediate action needed."
                elif churn_prob >= 0.4:
                    risk_level = "MEDIUM"
                    message = "Customer has moderate churn risk. Consider retention offer."
                else:
                    risk_level = "LOW"
                    message = "Customer is likely to stay."

            span.set_attribute("prediction.churn", churn_pred)
            span.set_attribute("prediction.probability", churn_prob)
            span.set_attribute("prediction.risk_level", risk_level)

            logger.info(f"Prediction: churn={churn_pred}, probability={churn_prob:.4f}, risk={risk_level}")

            return PredictionResponse(
                churn=churn_pred,
                probability=round(churn_prob, 4),
                risk_level=risk_level,
                message=message
            )

        except Exception as e:
            span.record_exception(e)
            logger.error(f"Prediction failed: {e}")
            raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

# ─────────────────────────────────────────
# Root endpoint
# ─────────────────────────────────────────
@app.get("/")
async def root():
    return {
        "message": "Churn Prediction API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "predict": "/predict",
            "docs": "/docs"
        }
    }

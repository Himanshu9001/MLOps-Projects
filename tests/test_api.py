import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
import numpy as np
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# ─────────────────────────────────────────
# Mock model to avoid loading MLflow
# ─────────────────────────────────────────
@pytest.fixture
def mock_model():
    """Create a mock ML model for testing."""
    model = MagicMock()
    model.predict.return_value = np.array([1])
    model.predict_proba.return_value = np.array([[0.3, 0.7]])
    return model

@pytest.fixture
def client(mock_model):
    """Create test client with mocked MLflow model loading."""
    with patch('mlflow.sklearn.load_model', return_value=mock_model):
        from app.main import app
        with TestClient(app) as c:
            yield c

# Sample customer data
SAMPLE_CUSTOMER = {
    "gender": 0,
    "SeniorCitizen": 0,
    "Partner": 0,
    "Dependents": 0,
    "tenure": 2,
    "PhoneService": 1,
    "MultipleLines": 0,
    "InternetService": 1,
    "OnlineSecurity": 0,
    "OnlineBackup": 0,
    "DeviceProtection": 0,
    "TechSupport": 0,
    "StreamingTV": 0,
    "StreamingMovies": 0,
    "Contract": 0,
    "PaperlessBilling": 1,
    "PaymentMethod": 2,
    "MonthlyCharges": 70.7,
    "TotalCharges": 151.65
}

# ─────────────────────────────────────────
# Tests
# ─────────────────────────────────────────
def test_health_check(client):
    """Health endpoint should return 200."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_root_endpoint(client):
    """Root endpoint should return API info."""
    response = client.get("/")
    assert response.status_code == 200
    assert "version" in response.json()

def test_predict_returns_200(client):
    """Predict endpoint should return 200 with valid input."""
    response = client.post("/predict", json=SAMPLE_CUSTOMER)
    assert response.status_code == 200

def test_predict_response_structure(client):
    """Predict response should have required fields."""
    response = client.post("/predict", json=SAMPLE_CUSTOMER)
    data = response.json()
    assert "churn" in data
    assert "probability" in data
    assert "risk_level" in data
    assert "message" in data

def test_predict_churn_is_binary(client):
    """Churn prediction should be 0 or 1."""
    response = client.post("/predict", json=SAMPLE_CUSTOMER)
    assert response.json()["churn"] in [0, 1]

def test_predict_probability_range(client):
    """Probability should be between 0 and 1."""
    response = client.post("/predict", json=SAMPLE_CUSTOMER)
    prob = response.json()["probability"]
    assert 0.0 <= prob <= 1.0

def test_predict_risk_level_values(client):
    """Risk level should be HIGH, MEDIUM or LOW."""
    response = client.post("/predict", json=SAMPLE_CUSTOMER)
    assert response.json()["risk_level"] in ["HIGH", "MEDIUM", "LOW"]

def test_predict_missing_field_returns_422(client):
    """Missing required field should return 422."""
    incomplete = SAMPLE_CUSTOMER.copy()
    del incomplete["tenure"]
    response = client.post("/predict", json=incomplete)
    assert response.status_code == 422

def test_predict_invalid_type_returns_422(client):
    """Invalid data type should return 422."""
    invalid = SAMPLE_CUSTOMER.copy()
    invalid["tenure"] = "not_a_number"
    response = client.post("/predict", json=invalid)
    assert response.status_code == 422
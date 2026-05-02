import pytest
import pandas as pd
import numpy as np
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.preprocess import load_data, preprocess, split_data, save_data

# ─────────────────────────────────────────
# Fixtures — reusable test data
# ─────────────────────────────────────────
@pytest.fixture
def sample_df():
    """Create a sample DataFrame for testing."""
    n = 20
    return pd.DataFrame({
        'customerID': [f'{i:04d}-ABCD' for i in range(n)],
        'gender': (['Male', 'Female'] * n)[:n],
        'SeniorCitizen': ([0, 1] * n)[:n],
        'Partner': (['Yes', 'No'] * n)[:n],
        'Dependents': (['No', 'Yes'] * n)[:n],
        'tenure': list(range(1, n + 1)),
        'PhoneService': (['Yes', 'No'] * n)[:n],
        'MultipleLines': (['No', 'No phone service', 'Yes'] * n)[:n],
        'InternetService': (['DSL', 'Fiber optic', 'No'] * n)[:n],
        'OnlineSecurity': (['Yes', 'No', 'No internet service'] * n)[:n],
        'OnlineBackup': (['No', 'Yes', 'No internet service'] * n)[:n],
        'DeviceProtection': (['Yes', 'No', 'No internet service'] * n)[:n],
        'TechSupport': (['No', 'Yes', 'No internet service'] * n)[:n],
        'StreamingTV': (['Yes', 'No', 'No internet service'] * n)[:n],
        'StreamingMovies': (['No', 'Yes', 'No internet service'] * n)[:n],
        'Contract': (['Month-to-month', 'One year', 'Two year'] * n)[:n],
        'PaperlessBilling': (['Yes', 'No'] * n)[:n],
        'PaymentMethod': (['Electronic check', 'Mailed check',
                           'Bank transfer (automatic)',
                           'Credit card (automatic)'] * n)[:n],
        'MonthlyCharges': [29.85 + i for i in range(n)],
        'TotalCharges': [str(29.85 + i * 10) for i in range(n)],
        'Churn': (['No', 'Yes'] * n)[:n]
    })

# ─────────────────────────────────────────
# Tests
# ─────────────────────────────────────────
def test_preprocess_drops_customer_id(sample_df):
    """customerID should be dropped after preprocessing."""
    result = preprocess(sample_df.copy())
    assert 'customerID' not in result.columns

def test_preprocess_converts_churn_to_binary(sample_df):
    """Churn column should be 0 or 1 after preprocessing."""
    result = preprocess(sample_df.copy())
    assert set(result['Churn'].unique()).issubset({0, 1})

def test_preprocess_no_missing_values(sample_df):
    """No missing values should remain after preprocessing."""
    result = preprocess(sample_df.copy())
    assert result.isnull().sum().sum() == 0

def test_preprocess_all_numeric(sample_df):
    """All columns should be numeric after preprocessing."""
    result = preprocess(sample_df.copy())
    assert all(result.dtypes != 'object')

def test_preprocess_total_charges_converts_strings(sample_df):
    """TotalCharges strings should be converted to float."""
    result = preprocess(sample_df.copy())
    assert result['TotalCharges'].dtype in [np.float64, np.float32]

def test_split_data_correct_proportions(sample_df):
    """Train/test split should respect test_size parameter."""
    df = preprocess(sample_df.copy())
    X_train, X_test, y_train, y_test = split_data(df, test_size=0.2)
    total = len(X_train) + len(X_test)
    assert total == len(df)

def test_split_data_no_overlap(sample_df):
    """Train and test sets should not overlap."""
    df = preprocess(sample_df.copy())
    X_train, X_test, y_train, y_test = split_data(df, test_size=0.2)
    train_idx = set(X_train.index)
    test_idx = set(X_test.index)
    assert len(train_idx.intersection(test_idx)) == 0

def test_split_data_features_match(sample_df):
    """Train and test should have same number of features."""
    df = preprocess(sample_df.copy())
    X_train, X_test, y_train, y_test = split_data(df, test_size=0.2)
    assert X_train.shape[1] == X_test.shape[1]

def test_save_data_creates_files(sample_df, tmp_path):
    """save_data should create train.csv and test.csv."""
    df = preprocess(sample_df.copy())
    X_train, X_test, y_train, y_test = split_data(df, test_size=0.2)
    save_data(X_train, X_test, y_train, y_test, str(tmp_path))
    assert (tmp_path / "train.csv").exists()
    assert (tmp_path / "test.csv").exists()
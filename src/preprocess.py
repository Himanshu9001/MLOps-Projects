import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import os
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def load_data(filepath):
    logger.info(f"Loading data from {filepath}")
    df = pd.read_csv(filepath)
    logger.info(f"Data shape: {df.shape}")
    return df

def preprocess(df):
    logger.info("Starting preprocessing...")

    # Drop customerID — not useful for prediction
    df = df.drop(columns=['customerID'])

    # Fix TotalCharges — it's a string with spaces, convert to float
    df['TotalCharges'] = pd.to_numeric(df['TotalCharges'], errors='coerce')

    # Fill missing TotalCharges with median
    median_val = df['TotalCharges'].median()
    df['TotalCharges'] = df['TotalCharges'].fillna(median_val)
    logger.info(f"Filled {df['TotalCharges'].isna().sum()} missing TotalCharges with median {median_val}")

    # Convert target column — Yes=1, No=0
    df['Churn'] = df['Churn'].map({'Yes': 1, 'No': 0})

    # Encode all categorical columns
    categorical_cols = df.select_dtypes(include=['object']).columns.tolist()
    logger.info(f"Encoding categorical columns: {categorical_cols}")

    le = LabelEncoder()
    for col in categorical_cols:
        df[col] = le.fit_transform(df[col])

    logger.info(f"Preprocessed data shape: {df.shape}")
    return df

def split_data(df, test_size=0.2, random_state=42):
    X = df.drop(columns=['Churn'])
    y = df['Churn']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    logger.info(f"Train size: {X_train.shape}, Test size: {X_test.shape}")
    return X_train, X_test, y_train, y_test

def save_data(X_train, X_test, y_train, y_test, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    train_df = pd.concat([X_train, y_train], axis=1)
    test_df = pd.concat([X_test, y_test], axis=1)

    train_path = os.path.join(output_dir, 'train.csv')
    test_path = os.path.join(output_dir, 'test.csv')

    train_df.to_csv(train_path, index=False)
    test_df.to_csv(test_path, index=False)

    logger.info(f"Train data saved to {train_path}")
    logger.info(f"Test data saved to {test_path}")

    return train_path, test_path

if __name__ == "__main__":
    # Paths
    RAW_DATA_PATH = "data/raw/churn.csv"
    PROCESSED_DIR = "data/processed"

    # Run pipeline
    df = load_data(RAW_DATA_PATH)
    df = preprocess(df)
    X_train, X_test, y_train, y_test = split_data(df)
    save_data(X_train, X_test, y_train, y_test, PROCESSED_DIR)

    logger.info("Preprocessing complete!")

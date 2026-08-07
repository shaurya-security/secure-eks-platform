import os


class Config:
    """Application configuration."""

    # Flask
    SECRET_KEY = os.getenv("SECRET_KEY", "change-me")
    DEBUG = os.getenv("FLASK_DEBUG", "False").lower() == "true"

    # Application
    APP_NAME = os.getenv("APP_NAME", "Secure EKS Platform")
    APP_ENV = os.getenv("APP_ENV", "production")
    APP_VERSION = os.getenv("APP_VERSION", "v1.0.0")

    # Database
    DB_HOST = os.getenv("DB_HOST")
    DB_PORT = int(os.getenv("DB_PORT", "5432"))
    DB_NAME = os.getenv("DB_NAME")
    DB_USER = os.getenv("DB_USERNAME")
    DB_PASSWORD = os.getenv("DB_PASSWORD")

    SQLALCHEMY_DATABASE_URI = (
        f"postgresql+psycopg://{DB_USER}:{DB_PASSWORD}"
        f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    )

    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Kubernetes / AWS metadata
    POD_NAME = os.getenv("HOSTNAME", "unknown")
    NODE_NAME = os.getenv("NODE_NAME", "unknown")
    CLUSTER_NAME = os.getenv("CLUSTER_NAME", "secure-eks-cluster")
    AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")

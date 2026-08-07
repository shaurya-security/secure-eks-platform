import time

from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

from config import Config


# Create SQLAlchemy engine
engine = create_engine(
    Config.SQLALCHEMY_DATABASE_URI,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    future=True,
)


def check_connection():
    """
    Returns database connectivity status and latency.
    """

    start = time.perf_counter()

    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))

        latency = round((time.perf_counter() - start) * 1000, 2)

        return {
            "connected": True,
            "latency_ms": latency,
        }

    except SQLAlchemyError as err:
        return {
            "connected": False,
            "latency_ms": None,
            "error": str(err),
        }


def get_postgres_version():
    """
    Returns PostgreSQL version string.
    """

    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT version();"))
            return result.scalar()

    except SQLAlchemyError:
        return "Unavailable"


def get_database_name():
    """
    Returns current database name.
    """

    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT current_database();"))
            return result.scalar()

    except SQLAlchemyError:
        return "Unavailable"

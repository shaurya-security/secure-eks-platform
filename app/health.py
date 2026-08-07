import socket

from config import Config
from database import (
    check_connection,
    get_database_name,
    get_postgres_version,
)


def health():
    """
    Liveness probe.
    """

    return {
        "status": "healthy",
        "application": Config.APP_NAME,
        "version": Config.APP_VERSION,
    }, 200


def readiness():
    """
    Readiness probe.
    """

    db = check_connection()

    if not db["connected"]:
        return {
            "status": "not-ready",
            "database": "disconnected",
            "error": db.get("error"),
        }, 503

    return {
        "status": "ready",
        "database": "connected",
        "latency_ms": db["latency_ms"],
    }, 200


def metrics():
    """
    Dashboard metrics.
    """

    db = check_connection()

    return {
        "application": Config.APP_NAME,
        "environment": Config.APP_ENV,
        "version": Config.APP_VERSION,
        "cluster": Config.CLUSTER_NAME,
        "region": Config.AWS_REGION,
        "pod": Config.POD_NAME,
        "node": Config.NODE_NAME,
        "hostname": socket.gethostname(),
        "database": {
            "connected": db["connected"],
            "latency_ms": db["latency_ms"],
            "name": get_database_name(),
            "version": get_postgres_version(),
        },
    }, 200

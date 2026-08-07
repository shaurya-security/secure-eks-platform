from flask import render_template

from config import Config
from database import (
    check_connection,
    get_database_name,
    get_postgres_version,
)
from utils import (
    get_system_info,
    get_uptime,
)


def register_routes(app):

    @app.route("/")
    def index():

        db = check_connection()

        return render_template(
            "index.html",

            # Application
            app_name=Config.APP_NAME,
            app_version=Config.APP_VERSION,
            app_env=Config.APP_ENV,

            # Kubernetes
            cluster_name=Config.CLUSTER_NAME,
            pod_name=Config.POD_NAME,
            node_name=Config.NODE_NAME,

            # Database
            db_connected=db["connected"],
            db_latency=db["latency_ms"],
            db_name=get_database_name(),
            db_version=get_postgres_version(),

            # System
            uptime=get_uptime(),
            system=get_system_info(),
        )

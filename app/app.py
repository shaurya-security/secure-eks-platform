from flask import Flask, jsonify

from config import Config
from health import health, readiness, metrics
from routes import register_routes

app = Flask(__name__)
app.config.from_object(Config)

register_routes(app)


@app.route("/health")
def health_endpoint():
    payload, status = health()
    return jsonify(payload), status


@app.route("/ready")
def ready_endpoint():
    payload, status = readiness()
    return jsonify(payload), status


@app.route("/metrics")
def metrics_endpoint():
    payload, status = metrics()
    return jsonify(payload), status


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=Config.DEBUG
    )

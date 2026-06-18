# Lab 2 buổi chiều: Flask app với /metrics
import os
import random
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
PrometheusMetrics(app)  # Tự thêm /metrics

ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
VERSION = os.getenv("VERSION", "v1")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE", "/var/run/secrets/db/password")

def read_db_secret():
    try:
        with open(DB_PASSWORD_FILE, "r", encoding="utf-8") as secret_file:
            return secret_file.read().strip()
    except FileNotFoundError:
        return None

@app.get("/")
def index():
    if random.random() < ERROR_RATE:
        return jsonify(error="injected", version=VERSION), 500
    return jsonify(ok=True, version=VERSION)

@app.get("/db-secret")
def db_secret():
    secret_value = read_db_secret()
    if secret_value is None:
        return jsonify(secretMounted=False, version=VERSION), 503
    return jsonify(secretMounted=True, secretLength=len(secret_value), version=VERSION)

@app.get("/healthz")
def healthz():
    return "ok", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

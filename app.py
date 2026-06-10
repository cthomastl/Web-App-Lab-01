import os
import time
import logging
from datetime import datetime
from flask import Flask, jsonify, render_template
import psutil

app = Flask(__name__)

LOG_DIR = "/var/log/flaskapp"
LOG_FILE = f"{LOG_DIR}/app.log"

os.makedirs(LOG_DIR, exist_ok=True)

file_handler = logging.FileHandler(LOG_FILE)
file_handler.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s %(message)s")
file_handler.setFormatter(formatter)

logger = logging.getLogger("flaskapp")
logger.setLevel(logging.INFO)
logger.addHandler(file_handler)

START_TIME = time.time()


def log_request(route, status_code):
    ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    logger.info(f"timestamp={ts} route={route} status_code={status_code}")


@app.route("/")
def index():
    log_request("/", 200)
    return render_template("index.html")


@app.route("/health")
def health():
    disk = psutil.disk_usage("/")
    mem = psutil.virtual_memory()

    uptime_seconds = int(time.time() - START_TIME)
    hours = uptime_seconds // 3600
    minutes = (uptime_seconds % 3600) // 60
    seconds = uptime_seconds % 60

    data = {
        "status": "ok",
        "disk": {
            "total_gb": round(disk.total / (1024 ** 3), 2),
            "used_gb": round(disk.used / (1024 ** 3), 2),
            "free_gb": round(disk.free / (1024 ** 3), 2),
            "percent_used": disk.percent,
        },
        "memory": {
            "total_gb": round(mem.total / (1024 ** 3), 2),
            "used_gb": round(mem.used / (1024 ** 3), 2),
            "available_gb": round(mem.available / (1024 ** 3), 2),
            "percent_used": mem.percent,
        },
        "uptime": f"{hours}h {minutes}m {seconds}s",
    }

    log_request("/health", 200)
    return jsonify(data)


@app.route("/logs")
def logs():
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        last_50 = lines[-50:] if len(lines) > 50 else lines
        log_request("/logs", 200)
        return jsonify({"lines": last_50})
    except FileNotFoundError:
        log_request("/logs", 404)
        return jsonify({"error": "Log file not found"}), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)

#!/bin/bash
# user_data.sh
# Runs once on first EC2 boot. Installs Docker, writes all application files,
# starts the containers, and configures a health-check cron job.
# Full output is logged to /var/log/user_data.log for post-boot debugging.

set -e
exec > >(tee /var/log/user_data.log) 2>&1

echo "=== user_data started at $(date) ==="

# -------------------------------------------------------------------------
# 1. System updates and package installation
# -------------------------------------------------------------------------

# Refresh all installed packages to pick up security patches
yum update -y

# amazon-linux-extras provides Docker as a curated extras package on Amazon Linux 2
amazon-linux-extras install docker -y

# Start the Docker daemon and configure it to start automatically on reboot
systemctl start docker
systemctl enable docker

# Allow the default ec2-user to run Docker commands without sudo
usermod -aG docker ec2-user

# Download the docker-compose v2 binary for x86_64
curl -SL "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose

# Mark the binary as executable
chmod +x /usr/local/bin/docker-compose

echo "Docker and docker-compose installed."

# -------------------------------------------------------------------------
# 2. Create directory structure
# -------------------------------------------------------------------------

# Application source code and Docker files live here
mkdir -p /opt/app/templates
mkdir -p /opt/app/nginx

# Scripts directory on the host (referenced from README and cron)
mkdir -p /opt/scripts

# Log directories: the Flask app writes here; the volume mount exposes it to the host
mkdir -p /var/log/flaskapp/archive
mkdir -p /var/log/scripts

echo "Directories created."

# -------------------------------------------------------------------------
# 3. Write application source files
#    Each heredoc uses a unique single-quoted marker to prevent bash from
#    expanding any variables or backticks inside the file content.
# -------------------------------------------------------------------------

# --- app.py ---
cat > /opt/app/app.py << 'PYEOF'
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
PYEOF

# --- requirements.txt ---
cat > /opt/app/requirements.txt << 'REQEOF'
Flask==2.3.3
psutil==5.9.5
Werkzeug==2.3.7
REQEOF

# --- templates/index.html ---
cat > /opt/app/templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flask App Monitor</title>
</head>
<body>
    <h1>Flask App Monitor</h1>
    <p>Server monitoring dashboard</p>

    <div>
        <button onclick="checkHealth()">Check Health</button>
        <button onclick="viewLogs()">View Logs</button>
    </div>

    <br>
    <textarea id="output" rows="20" cols="80" readonly style="font-family: monospace;"></textarea>

    <script>
        function checkHealth() {
            document.getElementById('output').value = 'Loading...';
            fetch('/health')
                .then(function(response) { return response.json(); })
                .then(function(data) {
                    document.getElementById('output').value = JSON.stringify(data, null, 2);
                })
                .catch(function(err) {
                    document.getElementById('output').value = 'Error: ' + err;
                });
        }

        function viewLogs() {
            document.getElementById('output').value = 'Loading...';
            fetch('/logs')
                .then(function(response) { return response.json(); })
                .then(function(data) {
                    if (data.lines) {
                        document.getElementById('output').value = data.lines.join('');
                    } else {
                        document.getElementById('output').value = JSON.stringify(data, null, 2);
                    }
                })
                .catch(function(err) {
                    document.getElementById('output').value = 'Error: ' + err;
                });
        }
    </script>
</body>
</html>
HTMLEOF

# --- Dockerfile ---
cat > /opt/app/Dockerfile << 'DOCKEREOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN mkdir -p /var/log/flaskapp/archive

COPY app.py .
COPY templates/ templates/

EXPOSE 5000

CMD ["python", "app.py"]
DOCKEREOF

# --- nginx/nginx.conf ---
# NOTE: The upstream block configures which host:port nginx forwards traffic to.
# If nginx returns 502 Bad Gateway, start your investigation here.
cat > /opt/app/nginx/nginx.conf << 'NGINXEOF'
events {
    worker_connections 1024;
}

http {
    upstream flask_app {
        server flask:5001;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://flask_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_connect_timeout 10s;
            proxy_read_timeout 30s;
        }
    }
}
NGINXEOF

# --- docker-compose.yml ---
cat > /opt/app/docker-compose.yml << 'COMPOSEEOF'
version: '3.8'

services:
  flask:
    build: .
    container_name: flask_app
    ports:
      - "5000:5000"
    volumes:
      - /var/log/flaskapp:/var/log/flaskapp
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - flask
    restart: unless-stopped
COMPOSEEOF

echo "Application files written."

# -------------------------------------------------------------------------
# 4. Write scripts to /opt/scripts/
# -------------------------------------------------------------------------

cat > /opt/scripts/health_check.sh << 'HEALTHEOF'
#!/bin/bash
# health_check.sh
# Checks disk usage, memory usage, and whether the Flask container is running.
# Prints a status report to stdout and appends it to /var/log/scripts/health.log.

# Get the current timestamp in a human-readable format
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Get disk usage for the root filesystem.
# df -h produces human-readable output; awk targets row 2 (the data row) and prints column 5 (Use%)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')

# Get the free disk space on the root filesystem (column 4 of df output)
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

# Read available memory in kilobytes from the kernel's memory info file
MEM_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# Read total installed memory in kilobytes from the same file
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert kilobytes to megabytes using integer division (bash does not support floats natively)
MEM_AVAILABLE_MB=$((MEM_AVAILABLE_KB / 1024))
MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))

# Calculate used memory by subtracting available from total
MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAILABLE_MB))

# Check whether the Flask container is currently running.
# docker ps lists only running containers; --format restricts output to container names only.
# grep -q returns exit code 0 if the container name is found, 1 otherwise.
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "flask_app"; then
    FLASK_STATUS="RUNNING"
else
    FLASK_STATUS="NOT RUNNING"
fi

# Also check the nginx proxy container status
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nginx_proxy"; then
    NGINX_STATUS="RUNNING"
else
    NGINX_STATUS="NOT RUNNING"
fi

# Build the full status report as a variable so it can be sent to both stdout and the log file
STATUS_REPORT="[${TIMESTAMP}] Health Check Report
  Disk Usage (root):   ${DISK_USAGE} used  (${DISK_FREE} free)
  Memory:              ${MEM_USED_MB}MB used / ${MEM_TOTAL_MB}MB total (${MEM_AVAILABLE_MB}MB available)
  Flask Container:     ${FLASK_STATUS}
  Nginx Container:     ${NGINX_STATUS}"

# Print the report to standard output for manual runs and cron email output
echo "$STATUS_REPORT"

# Create the scripts log directory if it does not yet exist
mkdir -p /var/log/scripts

# Append the same report to the persistent health log file
echo "$STATUS_REPORT" >> /var/log/scripts/health.log

# Write a separator line so individual runs are visually distinct in the log
echo "---" >> /var/log/scripts/health.log
HEALTHEOF

cat > /opt/scripts/log_rotate.sh << 'ROTATEEOF'
#!/bin/bash
# log_rotate.sh
# Archives the current Flask app.log to a timestamped file in the archive directory,
# then resets app.log to an empty file so the application can continue logging cleanly.
# This prevents the log file from growing without bound on a long-running server.

# Define the path to the active Flask log file
LOG_FILE="/var/log/flaskapp/app.log"

# Define the directory that will hold archived (rotated) log files
ARCHIVE_DIR="/var/log/flaskapp/archive"

# Build a timestamp string using only characters safe in a filename (no spaces or colons)
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")

# Combine the archive directory path and the timestamp to form the archive filename
ARCHIVE_FILE="${ARCHIVE_DIR}/app_${TIMESTAMP}.log"

# Create the archive directory if it does not already exist
mkdir -p "$ARCHIVE_DIR"

# Check whether the log file we intend to rotate actually exists
if [ -f "$LOG_FILE" ]; then

    # Copy the current log file to the archive location with the timestamped name.
    # Using cp (not mv) keeps the original inode in place, so the Flask process
    # can keep writing to the same file descriptor without errors.
    cp "$LOG_FILE" "$ARCHIVE_FILE"

    # Confirm to the operator where the archive was written
    echo "Archived: ${LOG_FILE} -> ${ARCHIVE_FILE}"

    # Truncate the original log file to zero bytes to start it fresh.
    # truncate -s 0 clears content while preserving permissions, ownership, and inode.
    truncate -s 0 "$LOG_FILE"

    # Confirm that the file has been cleared
    echo "Cleared: ${LOG_FILE} is now empty and ready for new log entries"

else
    # The log file does not exist — print a warning but do not exit with an error
    echo "WARNING: ${LOG_FILE} not found. Nothing to rotate."
fi
ROTATEEOF

cat > /opt/scripts/deploy.sh << 'DEPLOYEOF'
#!/bin/bash
# deploy.sh
# Rebuilds the Flask container from the latest local code and restarts it.
# Records the deployment timestamp and outcome in /var/log/scripts/deploy.log.

# The directory containing docker-compose.yml and the application source code
APP_DIR="/opt/app"

# The file where deployment events are recorded for audit and troubleshooting
DEPLOY_LOG="/var/log/scripts/deploy.log"

# Capture the timestamp at the moment the deployment begins
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Ensure the directory that holds the deploy log exists before writing to it
mkdir -p /var/log/scripts

# Write the start-of-deployment marker to both the terminal and the log file.
# tee -a writes to the log file in append mode while also printing to stdout.
echo "[${TIMESTAMP}] Deployment started" | tee -a "$DEPLOY_LOG"

# Move into the application directory so docker-compose can find its config file
cd "$APP_DIR" || { echo "ERROR: Cannot cd to ${APP_DIR}" | tee -a "$DEPLOY_LOG"; exit 1; }

# Pull any updated upstream base images from the registry
docker-compose pull --quiet 2>&1 | tee -a "$DEPLOY_LOG"

# Rebuild only the Flask service image from the local Dockerfile.
# --no-cache forces Docker to rebuild every layer, ensuring code changes are included.
docker-compose build --no-cache flask 2>&1 | tee -a "$DEPLOY_LOG"

# Recreate and start only the Flask container with the newly built image.
# --no-deps prevents docker-compose from restarting the nginx container unnecessarily.
# -d runs the container detached (in the background).
docker-compose up -d --no-deps flask 2>&1 | tee -a "$DEPLOY_LOG"

# Wait briefly for the container runtime to settle before checking status
sleep 3

# Verify that the Flask container is now showing as running
if docker ps --format '{{.Names}}' | grep -q "flask_app"; then

    # Container is in the running list — deployment succeeded
    echo "[${TIMESTAMP}] Deployment SUCCESS: flask_app is running" | tee -a "$DEPLOY_LOG"

else
    # Container is not running — it may have crashed immediately after start
    echo "[${TIMESTAMP}] Deployment FAILED: flask_app is not running" | tee -a "$DEPLOY_LOG"

    # Print recent container logs to help diagnose the failure
    echo "--- Container logs ---" | tee -a "$DEPLOY_LOG"
    docker logs --tail 20 flask_app 2>&1 | tee -a "$DEPLOY_LOG"

    # Return a non-zero exit code so calling scripts or CI systems detect failure
    exit 1
fi

# Separator line to visually separate entries in the deploy log
echo "---" >> "$DEPLOY_LOG"
DEPLOYEOF

# Make all scripts executable so they can be run directly from the terminal
chmod +x /opt/scripts/health_check.sh
chmod +x /opt/scripts/log_rotate.sh
chmod +x /opt/scripts/deploy.sh

echo "Scripts written and made executable."

# -------------------------------------------------------------------------
# 5. Build and start the application
# -------------------------------------------------------------------------

cd /opt/app

# --build forces Docker to build the Flask image from the Dockerfile before starting
docker-compose up -d --build

echo "Containers started."

# -------------------------------------------------------------------------
# 6. Set up cron job to run health_check.sh every 5 minutes
#    /etc/cron.d/ entries require: minute hour dom month dow user command
# -------------------------------------------------------------------------

echo "*/5 * * * * root /opt/scripts/health_check.sh > /dev/null 2>&1" > /etc/cron.d/flask_health_check
chmod 644 /etc/cron.d/flask_health_check

echo "Cron job configured."
echo "=== user_data completed at $(date) ==="

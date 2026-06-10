#!/bin/bash
# deploy.sh
# Rebuilds the Flask container from the latest local code and restarts it.
# Records the deployment timestamp and outcome in /var/log/scripts/deploy.log.
# Run this script whenever you update application files and want those changes live.

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

# Move into the application directory so docker-compose can find its configuration file
cd "$APP_DIR" || { echo "ERROR: Cannot cd to ${APP_DIR}" | tee -a "$DEPLOY_LOG"; exit 1; }

# Pull any updated upstream base images (e.g. python:3.11-slim) from the registry.
# --quiet suppresses the verbose layer-by-layer pull output.
# 2>&1 merges stderr into stdout so both streams are captured by tee.
docker-compose pull --quiet 2>&1 | tee -a "$DEPLOY_LOG"

# Rebuild only the Flask service image from the local Dockerfile.
# --no-cache forces Docker to rebuild every layer from scratch, ensuring
# that changes to app.py or requirements.txt are picked up even if the
# base image layers are cached.
docker-compose build --no-cache flask 2>&1 | tee -a "$DEPLOY_LOG"

# Recreate and start only the Flask container with the newly built image.
# -d runs the container detached (in the background).
# --no-deps prevents docker-compose from restarting the nginx container unnecessarily.
docker-compose up -d --no-deps flask 2>&1 | tee -a "$DEPLOY_LOG"

# Allow a short window for the container runtime to settle before checking status
sleep 3

# Verify that the Flask container is now showing as running.
# docker ps only lists containers in the running state; grep -q returns 0 on a match.
if docker ps --format '{{.Names}}' | grep -q "flask_app"; then

    # Container is running — deployment was successful
    echo "[${TIMESTAMP}] Deployment SUCCESS: flask_app is running" | tee -a "$DEPLOY_LOG"

else
    # Container is not in the running list — it may have crashed immediately after start
    echo "[${TIMESTAMP}] Deployment FAILED: flask_app is not running" | tee -a "$DEPLOY_LOG"

    # Print the last 20 lines of the container's logs to help diagnose the failure
    echo "--- Container logs ---" | tee -a "$DEPLOY_LOG"
    docker logs --tail 20 flask_app 2>&1 | tee -a "$DEPLOY_LOG"

    # Exit with a non-zero status code so any calling script or CI system knows it failed
    exit 1
fi

# Write a visual separator to the log file to cleanly separate deployment entries
echo "---" >> "$DEPLOY_LOG"

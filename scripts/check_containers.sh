#!/bin/bash
# check_containers.sh
# Checks whether each required container is in the running state.
# If any container is stopped or missing, attempts to bring it back up with docker-compose.
# Writes a status report to stdout and appends it to /var/log/scripts/containers.log.
#
# HOW TO RUN:
#   sudo /opt/scripts/check_containers.sh

# The application directory where docker-compose.yml lives
APP_DIR="/opt/app"

# The log file where status reports accumulate over time
LOG_FILE="/var/log/scripts/containers.log"

# The three containers that must be running for the app to work
REQUIRED=("postgres_db" "flask_app" "nginx_proxy")

# Capture the current timestamp for this check
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Ensure the log directory exists before we try to write to it
mkdir -p /var/log/scripts

# Print and log the header line for this check run
echo "[${TIMESTAMP}] Container status check" | tee -a "$LOG_FILE"

# Track whether all containers passed so we can print a summary at the end
ALL_OK=true

# Iterate over every container name in the REQUIRED array
for container in "${REQUIRED[@]}"; do

    # docker ps lists only RUNNING containers.
    # --format '{{.Names}}' limits output to container names, one per line.
    # grep -q "^${container}$" matches the exact name (^ and $ are anchors).
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        echo "  [OK]   ${container}" | tee -a "$LOG_FILE"
    else
        # Container is not in the running list — it may be stopped or crashed
        echo "  [FAIL] ${container} is not running" | tee -a "$LOG_FILE"
        ALL_OK=false
    fi
done

# If any container was not running, use docker-compose to restart the whole stack.
# docker-compose up -d starts stopped services and leaves already-running ones alone.
if [ "$ALL_OK" = false ]; then
    echo "  Attempting to restart stopped containers..." | tee -a "$LOG_FILE"
    cd "$APP_DIR" && docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
else
    echo "  All containers healthy." | tee -a "$LOG_FILE"
fi

# Write a visual separator so individual check runs are easy to find in the log
echo "---" >> "$LOG_FILE"

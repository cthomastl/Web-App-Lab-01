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
    # Container found in the running list
    FLASK_STATUS="RUNNING"
else
    # Container not found — either stopped or never started
    FLASK_STATUS="NOT RUNNING"
fi

# Also check the nginx proxy container status using the same approach
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

# Create the scripts log directory if it does not yet exist (-p suppresses the error if it does)
mkdir -p /var/log/scripts

# Append the same report to the persistent health log file
echo "$STATUS_REPORT" >> /var/log/scripts/health.log

# Write a separator line so individual runs are visually distinct when viewing the log file
echo "---" >> /var/log/scripts/health.log

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

# Create the archive directory if it does not already exist.
# The -p flag prevents an error if the directory is already there.
mkdir -p "$ARCHIVE_DIR"

# Check whether the log file we intend to rotate actually exists
if [ -f "$LOG_FILE" ]; then

    # Copy the current log file to the archive location with the timestamped name.
    # Using cp (not mv) ensures the original inode stays in place, which avoids
    # breaking any process that has the file open for writing.
    cp "$LOG_FILE" "$ARCHIVE_FILE"

    # Confirm to the operator where the archive was written
    echo "Archived: ${LOG_FILE} -> ${ARCHIVE_FILE}"

    # Truncate the original log file to zero bytes to start it fresh.
    # truncate -s 0 clears the file content while preserving its permissions,
    # ownership, and inode — so Flask can continue writing to the same file handle.
    truncate -s 0 "$LOG_FILE"

    # Confirm that the file has been cleared
    echo "Cleared: ${LOG_FILE} is now empty and ready for new log entries"

else
    # The log file does not exist at all — print a warning but do not exit with an error.
    # This can happen if the app has never started or has not written a log yet.
    echo "WARNING: ${LOG_FILE} not found. Nothing to rotate."
fi

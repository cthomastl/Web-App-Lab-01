#!/bin/bash
# db_backup.sh
# Dumps the basketball PostgreSQL database to a timestamped SQL file on the EC2 host.
# Backups are stored in /var/backups/basketball/.
# Files older than 7 days are automatically deleted at the end of each run.
#
# HOW TO RUN:
#   sudo /opt/scripts/db_backup.sh

# Directory on the EC2 host where backup files will be written
BACKUP_DIR="/var/backups/basketball"

# Name of the running Postgres container (matches container_name in docker-compose.yml)
DB_CONTAINER="postgres_db"

# Postgres credentials — must match the values in docker-compose.yml
DB_USER="flask"
DB_NAME="basketball"

# Build a filename that includes the date and time so backups never overwrite each other
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/basketball_${TIMESTAMP}.sql"

# Create the backup directory if it does not exist; -p suppresses the error if it does
mkdir -p "$BACKUP_DIR"

echo "Starting backup of '${DB_NAME}' database..."

# Run pg_dump inside the Postgres container and redirect the output to a file on the host.
# docker exec runs a command inside a running container without opening an interactive shell.
# pg_dump writes a plain-text SQL dump to stdout, which we capture with >.
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"

# Check the exit code of the previous command ($? holds the exit code: 0 = success)
if [ $? -eq 0 ]; then
    echo "Backup saved: ${BACKUP_FILE}"
    # Print the file size so you can confirm the dump is not empty
    ls -lh "$BACKUP_FILE"
else
    echo "ERROR: pg_dump failed. Check that the container '${DB_CONTAINER}' is running."
    # Remove the empty file that was created by the failed redirect
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Remove backup files older than 7 days to keep disk usage in check.
# find with -mtime +7 matches files last modified more than 7 days ago.
# -delete removes them in place without spawning a separate rm process.
DELETED=$(find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete -print | wc -l)
echo "Cleaned up ${DELETED} backup(s) older than 7 days."

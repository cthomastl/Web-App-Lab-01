#!/bin/bash
# seed_players.sh
# Wipes the players table and re-inserts the default starting roster.
# Use this to reset the database to a known state during testing or after accidentally
# deleting all players through the UI.
#
# HOW TO RUN:
#   sudo /opt/scripts/seed_players.sh

# Name of the running Postgres container
DB_CONTAINER="postgres_db"

# Postgres credentials — must match docker-compose.yml
DB_USER="flask"
DB_NAME="basketball"

# Confirm the Postgres container is running before attempting the SQL commands
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "ERROR: Container '${DB_CONTAINER}' is not running."
    echo "Start it with: cd /opt/app && docker-compose up -d db"
    exit 1
fi

echo "Seeding '${DB_NAME}' with the default roster..."

# Run a multi-statement SQL block inside the Postgres container using psql.
# docker exec -i allows us to pipe the SQL text in via stdin.
# The -c flag passes a single SQL string to psql directly.
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'SQL'
-- Remove all existing players so the seed is idempotent
DELETE FROM players;

-- Reset the auto-increment sequence so IDs start from 1 again
ALTER SEQUENCE players_id_seq RESTART WITH 1;

-- Insert the default starting roster
INSERT INTO players (name, position, number) VALUES
    ('Marcus Johnson', 'PG',  1),
    ('Darius Cole',    'SG',  3),
    ('Terrence Hill',  'SF',  7),
    ('Andre Williams', 'PF', 15),
    ('Devon Carter',   'C',  32);

-- Print the resulting table so you can confirm the seed worked
SELECT id, number, name, position FROM players ORDER BY number;
SQL

# Check whether the psql command exited successfully
if [ $? -eq 0 ]; then
    echo "Roster seeded successfully."
else
    echo "ERROR: psql command failed. Check the container logs."
    exit 1
fi

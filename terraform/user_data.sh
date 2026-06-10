#!/bin/bash
# user_data.sh
# Runs once on first EC2 boot. Installs Docker, writes all application files,
# starts the three-container stack, and sets up a health-check cron job.
# All output is logged to /var/log/user_data.log for post-boot debugging.

set -e
exec > >(tee /var/log/user_data.log) 2>&1

echo "=== user_data started at $(date) ==="

# -------------------------------------------------------------------------
# 1. System updates and package installation
# -------------------------------------------------------------------------

yum update -y

# docker is available as a curated package via amazon-linux-extras on AL2
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker

# Allow ec2-user to run docker commands without sudo
usermod -aG docker ec2-user

# Install the docker-compose v2 binary for x86_64
curl -SL "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Docker and docker-compose installed."

# -------------------------------------------------------------------------
# 2. Create directory structure
# -------------------------------------------------------------------------

mkdir -p /opt/app/templates
mkdir -p /opt/app/nginx
mkdir -p /opt/app/initdb
mkdir -p /opt/scripts
mkdir -p /var/log/flaskapp
mkdir -p /var/log/scripts
mkdir -p /var/backups/basketball

echo "Directories created."

# -------------------------------------------------------------------------
# 3. Write application files
#    Each heredoc uses a unique single-quoted marker so bash does not
#    expand variables or backticks inside the file content.
# -------------------------------------------------------------------------

# --- app.py ---
cat > /opt/app/app.py << 'PYEOF'
import os
import time
import logging
from flask import Flask, jsonify, render_template, request
import psycopg2
import psycopg2.extras

app = Flask(__name__)

LOG_DIR = "/var/log/flaskapp"
LOG_FILE = f"{LOG_DIR}/app.log"
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)


def get_db():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "basketball"),
        user=os.environ.get("DB_USER", "flask"),
        password=os.environ.get("DB_PASSWORD", "flaskpass"),
    )


def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS players (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            position VARCHAR(20),
            number INTEGER
        )
        """
    )
    conn.commit()
    cur.close()
    conn.close()


@app.route("/")
def index():
    logger.info("GET / 200")
    return render_template("index.html")


@app.route("/api/players", methods=["GET"])
def get_players():
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT id, name, position, number FROM players ORDER BY number, name")
        players = [dict(row) for row in cur.fetchall()]
        cur.close()
        conn.close()
        logger.info(f"GET /api/players 200 ({len(players)} players)")
        return jsonify(players)
    except Exception as e:
        logger.error(f"GET /api/players 500 - {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/players", methods=["POST"])
def add_player():
    data = request.get_json(force=True)
    name = (data.get("name") or "").strip()
    position = (data.get("position") or "").strip()
    number = data.get("number")

    if not name:
        return jsonify({"error": "name is required"}), 400

    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO players (name, position, number) VALUES (%s, %s, %s) RETURNING id",
            (name, position, number),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        logger.info(f"POST /api/players 201 - id={new_id} name={name}")
        return jsonify({"id": new_id, "name": name, "position": position, "number": number}), 201
    except Exception as e:
        logger.error(f"POST /api/players 500 - {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/players/<int:player_id>", methods=["DELETE"])
def remove_player(player_id):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("DELETE FROM players WHERE id = %s RETURNING id", (player_id,))
        deleted = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        if deleted is None:
            logger.warning(f"DELETE /api/players/{player_id} 404 - not found")
            return jsonify({"error": "Player not found"}), 404
        logger.info(f"DELETE /api/players/{player_id} 200")
        return jsonify({"deleted": player_id})
    except Exception as e:
        logger.error(f"DELETE /api/players/{player_id} 500 - {e}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    for attempt in range(15):
        try:
            init_db()
            logger.info("Database initialized")
            break
        except Exception as e:
            logger.warning(f"DB not ready ({attempt + 1}/15): {e}")
            time.sleep(3)
    else:
        logger.error("Could not reach database after 15 attempts. API endpoints will return 500.")

    app.run(host="0.0.0.0", port=5000, debug=False)
PYEOF

# --- requirements.txt ---
cat > /opt/app/requirements.txt << 'REQEOF'
Flask==2.3.3
psycopg2-binary==2.9.9
Werkzeug==2.3.7
REQEOF

# --- templates/index.html ---
cat > /opt/app/templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Northside Ballers</title>
</head>
<body>
    <h1>Northside Ballers</h1>
    <h2>Team Roster</h2>

    <p id="roster-error" style="color: red; display: none;"></p>

    <table id="roster-table" border="1" cellpadding="6">
        <thead>
            <tr>
                <th>Number</th>
                <th>Name</th>
                <th>Position</th>
                <th></th>
            </tr>
        </thead>
        <tbody id="roster-body">
            <tr><td colspan="4">Loading roster...</td></tr>
        </tbody>
    </table>

    <br>
    <h3>Add Player</h3>

    <form id="add-form">
        <label>Name:
            <input type="text" id="player-name" required>
        </label>
        <br><br>
        <label>Position:
            <select id="player-position">
                <option value="PG">PG - Point Guard</option>
                <option value="SG">SG - Shooting Guard</option>
                <option value="SF">SF - Small Forward</option>
                <option value="PF">PF - Power Forward</option>
                <option value="C">C - Center</option>
            </select>
        </label>
        <br><br>
        <label>Jersey Number:
            <input type="number" id="player-number" min="0" max="99" required>
        </label>
        <br><br>
        <button type="submit">Add Player</button>
    </form>

    <p id="form-message"></p>

    <script>
        function loadRoster() {
            fetch('/api/players')
                .then(function(res) { return res.json(); })
                .then(function(data) {
                    var error = document.getElementById('roster-error');
                    var tbody = document.getElementById('roster-body');

                    if (data.error) {
                        error.textContent = 'Could not load roster: ' + data.error;
                        error.style.display = 'block';
                        tbody.innerHTML = '<tr><td colspan="4">Roster unavailable.</td></tr>';
                        return;
                    }

                    error.style.display = 'none';

                    if (data.length === 0) {
                        tbody.innerHTML = '<tr><td colspan="4">No players on roster.</td></tr>';
                        return;
                    }

                    tbody.innerHTML = '';
                    data.forEach(function(player) {
                        var row = document.createElement('tr');
                        row.innerHTML =
                            '<td>' + player.number + '</td>' +
                            '<td>' + player.name + '</td>' +
                            '<td>' + player.position + '</td>' +
                            '<td><button onclick="removePlayer(' + player.id + ')">Remove</button></td>';
                        tbody.appendChild(row);
                    });
                })
                .catch(function(err) {
                    var error = document.getElementById('roster-error');
                    error.textContent = 'Could not reach server: ' + err;
                    error.style.display = 'block';
                });
        }

        function removePlayer(id) {
            if (!confirm('Remove this player from the roster?')) { return; }
            fetch('/api/players/' + id, { method: 'DELETE' })
                .then(function(res) { return res.json(); })
                .then(function(data) {
                    if (data.error) {
                        document.getElementById('form-message').textContent = 'Error: ' + data.error;
                    } else {
                        loadRoster();
                    }
                })
                .catch(function(err) {
                    document.getElementById('form-message').textContent = 'Request failed: ' + err;
                });
        }

        document.getElementById('add-form').addEventListener('submit', function(e) {
            e.preventDefault();
            var name = document.getElementById('player-name').value.trim();
            var position = document.getElementById('player-position').value;
            var number = parseInt(document.getElementById('player-number').value, 10);
            var msg = document.getElementById('form-message');

            fetch('/api/players', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: name, position: position, number: number })
            })
            .then(function(res) { return res.json(); })
            .then(function(data) {
                if (data.error) {
                    msg.textContent = 'Error: ' + data.error;
                } else {
                    document.getElementById('player-name').value = '';
                    document.getElementById('player-number').value = '';
                    msg.textContent = name + ' added.';
                    loadRoster();
                }
            })
            .catch(function(err) {
                msg.textContent = 'Request failed: ' + err;
            });
        });

        loadRoster();
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

RUN mkdir -p /var/log/flaskapp

COPY app.py .
COPY templates/ templates/

EXPOSE 5000

CMD ["python", "app.py"]
DOCKEREOF

# --- initdb/01_init.sql (runs automatically on first Postgres startup) ---
cat > /opt/app/initdb/01_init.sql << 'SQLEOF'
CREATE TABLE IF NOT EXISTS players (
    id       SERIAL PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    position VARCHAR(20),
    number   INTEGER
);

INSERT INTO players (name, position, number) VALUES
    ('Marcus Johnson', 'PG',  1),
    ('Darius Cole',    'SG',  3),
    ('Terrence Hill',  'SF',  7),
    ('Andre Williams', 'PF', 15),
    ('Devon Carter',   'C',  32);
SQLEOF

# --- nginx/nginx.conf ---
cat > /opt/app/nginx/nginx.conf << 'NGINXEOF'
events {
    worker_connections 1024;
}

http {
    upstream flask_app {
        server flask:5000;
    }

    server {
        listen 80;

        location / {
            proxy_pass         http://flask_app;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_connect_timeout 10s;
            proxy_read_timeout    30s;
        }
    }
}
NGINXEOF

# --- docker-compose.yml (DB_HOST is intentionally wrong) ---
cat > /opt/app/docker-compose.yml << 'COMPOSEEOF'
version: '3.8'

services:

  db:
    image: postgres:15-alpine
    container_name: postgres_db
    environment:
      POSTGRES_DB:       basketball
      POSTGRES_USER:     flask
      POSTGRES_PASSWORD: flaskpass
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./initdb:/docker-entrypoint-initdb.d
    restart: unless-stopped

  flask:
    build: .
    container_name: flask_app
    environment:
      DB_HOST:     localhost
      DB_PORT:     "5432"
      DB_NAME:     basketball
      DB_USER:     flask
      DB_PASSWORD: flaskpass
    ports:
      - "5000:5000"
    volumes:
      - /var/log/flaskapp:/var/log/flaskapp
    depends_on:
      - db
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

volumes:
  pgdata:
COMPOSEEOF

echo "Application files written."

# -------------------------------------------------------------------------
# 4. Write operator scripts
# -------------------------------------------------------------------------

cat > /opt/scripts/db_backup.sh << 'BKEOF'
#!/bin/bash
# db_backup.sh
# Dumps the basketball PostgreSQL database to a timestamped SQL file on the EC2 host.
# Backups are stored in /var/backups/basketball/.
# Files older than 7 days are automatically deleted at the end of each run.
#
# HOW TO RUN:
#   sudo /opt/scripts/db_backup.sh

BACKUP_DIR="/var/backups/basketball"
DB_CONTAINER="postgres_db"
DB_USER="flask"
DB_NAME="basketball"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/basketball_${TIMESTAMP}.sql"

mkdir -p "$BACKUP_DIR"

echo "Starting backup of '${DB_NAME}' database..."

# docker exec runs pg_dump inside the container; stdout is redirected to a file on the host
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup saved: ${BACKUP_FILE}"
    ls -lh "$BACKUP_FILE"
else
    echo "ERROR: pg_dump failed. Check that container '${DB_CONTAINER}' is running."
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Remove backup files older than 7 days to prevent unbounded disk growth
DELETED=$(find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete -print | wc -l)
echo "Cleaned up ${DELETED} backup(s) older than 7 days."
BKEOF

cat > /opt/scripts/check_containers.sh << 'CHKEOF'
#!/bin/bash
# check_containers.sh
# Checks whether each required container is in the running state.
# If any container is stopped, attempts to bring it back up with docker-compose.
# Writes a status report to stdout and appends it to /var/log/scripts/containers.log.
#
# HOW TO RUN:
#   sudo /opt/scripts/check_containers.sh

APP_DIR="/opt/app"
LOG_FILE="/var/log/scripts/containers.log"
REQUIRED=("postgres_db" "flask_app" "nginx_proxy")
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p /var/log/scripts

echo "[${TIMESTAMP}] Container status check" | tee -a "$LOG_FILE"

ALL_OK=true

for container in "${REQUIRED[@]}"; do
    # docker ps only lists running containers; --format limits output to names
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        echo "  [OK]   ${container}" | tee -a "$LOG_FILE"
    else
        echo "  [FAIL] ${container} is not running" | tee -a "$LOG_FILE"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = false ]; then
    echo "  Attempting restart via docker-compose..." | tee -a "$LOG_FILE"
    # docker-compose up -d starts any stopped services and leaves running ones alone
    cd "$APP_DIR" && docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
else
    echo "  All containers healthy." | tee -a "$LOG_FILE"
fi

echo "---" >> "$LOG_FILE"
CHKEOF

cat > /opt/scripts/seed_players.sh << 'SEEDEOF'
#!/bin/bash
# seed_players.sh
# Wipes the players table and re-inserts the default starting roster.
# Use this to reset the database to a known state during testing or after
# accidentally deleting all players through the UI.
#
# HOW TO RUN:
#   sudo /opt/scripts/seed_players.sh

DB_CONTAINER="postgres_db"
DB_USER="flask"
DB_NAME="basketball"

if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "ERROR: Container '${DB_CONTAINER}' is not running."
    echo "Start it with: cd /opt/app && docker-compose up -d db"
    exit 1
fi

echo "Seeding '${DB_NAME}' with the default roster..."

# Pipe a SQL block into psql running inside the Postgres container.
# docker exec -i keeps stdin open so the heredoc content is passed through.
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" << 'SQL'
DELETE FROM players;
ALTER SEQUENCE players_id_seq RESTART WITH 1;
INSERT INTO players (name, position, number) VALUES
    ('Marcus Johnson', 'PG',  1),
    ('Darius Cole',    'SG',  3),
    ('Terrence Hill',  'SF',  7),
    ('Andre Williams', 'PF', 15),
    ('Devon Carter',   'C',  32);
SELECT id, number, name, position FROM players ORDER BY number;
SQL

if [ $? -eq 0 ]; then
    echo "Roster seeded successfully."
else
    echo "ERROR: psql command failed."
    exit 1
fi
SEEDEOF

chmod +x /opt/scripts/db_backup.sh
chmod +x /opt/scripts/check_containers.sh
chmod +x /opt/scripts/seed_players.sh

echo "Scripts written and made executable."

# -------------------------------------------------------------------------
# 5. Build and start the containers
# -------------------------------------------------------------------------

cd /opt/app
docker-compose up -d --build

echo "Containers started."

# -------------------------------------------------------------------------
# 6. Cron job: run check_containers.sh every 5 minutes
# -------------------------------------------------------------------------

echo "*/5 * * * * root /opt/scripts/check_containers.sh > /dev/null 2>&1" > /etc/cron.d/container_watch
chmod 644 /etc/cron.d/container_watch

echo "Cron job configured."
echo "=== user_data completed at $(date) ==="

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

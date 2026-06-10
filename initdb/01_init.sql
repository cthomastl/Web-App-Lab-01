-- Runs automatically on first Postgres container startup.
-- Creates the players table and inserts the starting roster.

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

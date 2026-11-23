-- Sprint 8: the Everyone leaderboard switch, bell notes of any kind (titles taken), and the old app's game history
-- imported from its Group history (only games whose every name is on the real-player list). Only adds.

-- "Show me on the Everyone leaderboard" (Profile), on by default
ALTER TABLE users ADD COLUMN on_board INTEGER NOT NULL DEFAULT 1;

-- bell notes that aren't social (notifications.kind is fixed by a CHECK): a title taken from me, and later kinds
CREATE TABLE bell_notes (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,                        -- title_lost
  data       TEXT NOT NULL CHECK (json_valid(data)),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  read_at    INTEGER
) STRICT;
CREATE INDEX bell_notes_user ON bell_notes (user_id, created_at);

-- the real players of the old app: {"version":1,"names":{"<old name>": "<@handle or account id, or null>"}}
-- (filled by hand; empty = an import keeps nothing)
INSERT INTO settings (key, value, updated_at) VALUES ('old_players', '{"version":1,"names":{}}', 0);
-- who holds each Everyone-leaderboard title now (to tell the one who lost it)
INSERT INTO settings (key, value, updated_at) VALUES ('titles', '{}', 0);

-- a finished game from the old app, kept as the old app wrote it
CREATE TABLE legacy_games (
  id          TEXT PRIMARY KEY,                    -- a hash of the old game (the same game imported twice is one row)
  importer_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  group_code  TEXT NOT NULL,
  raw         TEXT NOT NULL CHECK (json_valid(raw)),
  format      INTEGER NOT NULL,                    -- 1 = the old app's LogEntry (v2.4 - v2.20)
  played_at   INTEGER NOT NULL,
  valid       INTEGER NOT NULL CHECK (valid IN (0, 1)),
  winner      TEXT NOT NULL CHECK (winner IN ('mafia', 'citizens')),
  days        INTEGER NOT NULL,
  created_at  INTEGER NOT NULL
) STRICT;
CREATE INDEX legacy_games_importer ON legacy_games (importer_id);

CREATE TABLE legacy_seats (
  game_id  TEXT NOT NULL REFERENCES legacy_games (id) ON DELETE CASCADE,
  seat     INTEGER NOT NULL,
  name     TEXT NOT NULL,
  name_key TEXT NOT NULL,                          -- the name compared ignoring case and spacing
  role     TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen')),
  alive    INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
CREATE INDEX legacy_seats_name ON legacy_seats (name_key);

-- "Which one were you?": an old name claimed by an account (one account per name)
CREATE TABLE legacy_claims (
  name_key   TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX legacy_claims_user ON legacy_claims (user_id);

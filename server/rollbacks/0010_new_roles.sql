-- Rollback of migrations/0010_new_roles.sql: back to the 0.4 CHECKs. Games that can't fit them (a Jester win, or a
-- Sniper or Jester seat) are deleted from history first; every other game is kept as it is.
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0010_new_roles.sql
-- then: DELETE FROM d1_migrations WHERE name = '0010_new_roles.sql';
PRAGMA defer_foreign_keys = true;

DELETE FROM games WHERE winner = 'jester' OR id IN (SELECT game_id FROM game_players WHERE role IN ('sniper', 'jester'));

CREATE TABLE m10_players AS SELECT game_id, seat, user_id, name, role, alive FROM game_players;
CREATE TABLE m10_wifi AS SELECT id, game_id FROM wifi_requests WHERE game_id IS NOT NULL;

CREATE TABLE games_old (
  id         TEXT PRIMARY KEY,
  host_id    TEXT REFERENCES users (id) ON DELETE SET NULL,
  winner     TEXT NOT NULL CHECK (winner IN ('mafia', 'citizens')),
  days       INTEGER NOT NULL CHECK (days >= 1),
  valid      INTEGER NOT NULL DEFAULT 1 CHECK (valid IN (0, 1)),
  rules      TEXT NOT NULL CHECK (json_valid(rules)),
  log        TEXT NOT NULL CHECK (json_valid(log)),
  stats      TEXT NOT NULL CHECK (json_valid(stats)),
  played_at  INTEGER NOT NULL,
  record     TEXT CHECK (record IS NULL OR json_valid(record)),
  source     TEXT NOT NULL DEFAULT 'online'
) STRICT;
INSERT INTO games_old (id, host_id, winner, days, valid, rules, log, stats, played_at, record, source)
  SELECT id, host_id, winner, days, valid, rules, log, stats, played_at, record, source FROM games;

DROP TABLE game_players;
DROP TABLE games;
ALTER TABLE games_old RENAME TO games;

CREATE TABLE game_players (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
INSERT INTO game_players (game_id, seat, user_id, name, role, alive)
  SELECT game_id, seat, user_id, name, role, alive FROM m10_players;
CREATE INDEX game_players_user ON game_players (user_id);

UPDATE wifi_requests SET game_id = (SELECT w.game_id FROM m10_wifi w WHERE w.id = wifi_requests.id)
  WHERE id IN (SELECT id FROM m10_wifi);

DROP TABLE m10_players;
DROP TABLE m10_wifi;

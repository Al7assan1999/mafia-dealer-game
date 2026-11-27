-- Rollback of migrations/0015_wave2.sql: back to the 1.3.0 CHECKs. Games with a new winner or a Serial Killer or Cupid
-- seat can't fit them and are deleted from history first; every other game is kept as it is.
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0015_wave2.sql
-- then: DELETE FROM d1_migrations WHERE name = '0015_wave2.sql';
PRAGMA defer_foreign_keys = true;

DELETE FROM games WHERE winner IN ('killer', 'lovers', 'draw') OR id IN (SELECT game_id FROM game_players WHERE role IN ('killer', 'cupid'));
-- dropping `games` would cascade into game_players and clear wifi_requests.game_id: copy both first
CREATE TABLE r15_players AS SELECT game_id, seat, user_id, name, role, alive FROM game_players WHERE game_id IN (SELECT id FROM games);  -- the kept games only (with or without the cascade)
CREATE TABLE r15_wifi AS SELECT id, game_id FROM wifi_requests WHERE game_id IS NOT NULL;

CREATE TABLE games_new (
  id         TEXT PRIMARY KEY,
  host_id    TEXT REFERENCES users (id) ON DELETE SET NULL,
  winner     TEXT NOT NULL CHECK (winner IN ('mafia', 'citizens', 'jester')),
  days       INTEGER NOT NULL CHECK (days >= 1),
  valid      INTEGER NOT NULL DEFAULT 1 CHECK (valid IN (0, 1)),
  rules      TEXT NOT NULL CHECK (json_valid(rules)),
  log        TEXT NOT NULL CHECK (json_valid(log)),     -- the engine's events
  stats      TEXT NOT NULL CHECK (json_valid(stats)),
  played_at  INTEGER NOT NULL,
  record     TEXT CHECK (record IS NULL OR json_valid(record)),
  source     TEXT NOT NULL DEFAULT 'online'
) STRICT;
INSERT INTO games_new (id, host_id, winner, days, valid, rules, log, stats, played_at, record, source)
  SELECT id, host_id, winner, days, valid, rules, log, stats, played_at, record, source FROM games;

DROP TABLE game_players;  -- the child first: then dropping games has nothing to cascade into
DROP TABLE games;         -- clears wifi_requests.game_id (restored below)
ALTER TABLE games_new RENAME TO games;

CREATE TABLE game_players (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard', 'hunter', 'mayor', 'watcher')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
INSERT INTO game_players (game_id, seat, user_id, name, role, alive)
  SELECT game_id, seat, user_id, name, role, alive FROM r15_players;
CREATE INDEX game_players_user ON game_players (user_id);

UPDATE wifi_requests SET game_id = (SELECT w.game_id FROM r15_wifi w WHERE w.id = wifi_requests.id)
  WHERE id IN (SELECT id FROM r15_wifi);

DROP TABLE r15_players;
DROP TABLE r15_wifi;

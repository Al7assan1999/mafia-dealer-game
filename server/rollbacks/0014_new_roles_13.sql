-- Rollback of migrations/0014_new_roles_13.sql: back to the 1.1.0 CHECK. Games with a Hunter, Mayor or Watcher seat
-- can't fit it and are deleted from history first; every other game is kept as it is.
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0014_new_roles_13.sql
-- then: DELETE FROM d1_migrations WHERE name = '0014_new_roles_13.sql';
PRAGMA defer_foreign_keys = true;

DELETE FROM games WHERE id IN (SELECT game_id FROM game_players WHERE role IN ('hunter', 'mayor', 'watcher'));

CREATE TABLE game_players_old (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
INSERT INTO game_players_old (game_id, seat, user_id, name, role, alive)
  SELECT game_id, seat, user_id, name, role, alive FROM game_players;
DROP TABLE game_players;
ALTER TABLE game_players_old RENAME TO game_players;
CREATE INDEX game_players_user ON game_players (user_id);

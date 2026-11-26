-- Sprint 20 (1.3.0): the Hunter, the Mayor and the Watcher (the Framer is a Mafia seat, stored as 'mafia'). SQLite can't
-- change a CHECK, so `game_players` is rebuilt with role also taking 'hunter', 'mayor' and 'watcher'. Nothing
-- references game_players, and `games` is untouched (no new winner). Every row is kept as it is; the 1.2.1 Worker
-- works on the new table unchanged (it never writes the new values).
-- Rollback: rollbacks/0014_new_roles_13.sql.
PRAGMA defer_foreign_keys = true;

CREATE TABLE game_players_new (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard', 'hunter', 'mayor', 'watcher')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
INSERT INTO game_players_new (game_id, seat, user_id, name, role, alive)
  SELECT game_id, seat, user_id, name, role, alive FROM game_players;
DROP TABLE game_players;
ALTER TABLE game_players_new RENAME TO game_players;
CREATE INDEX game_players_user ON game_players (user_id);

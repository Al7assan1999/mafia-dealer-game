-- Sprint 18 (1.1.0): the Bodyguard. SQLite can't change a CHECK, so `game_players` is rebuilt with role also taking
-- 'bodyguard'. Nothing references game_players, and `games` is untouched (no new winner). Every row is kept as it is;
-- the 1.0.0 Worker works on the new table unchanged (it never writes the new value).
-- Rollback: rollbacks/0011_bodyguard.sql.
PRAGMA defer_foreign_keys = true;

CREATE TABLE game_players_new (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
INSERT INTO game_players_new (game_id, seat, user_id, name, role, alive)
  SELECT game_id, seat, user_id, name, role, alive FROM game_players;
DROP TABLE game_players;
ALTER TABLE game_players_new RENAME TO game_players;
CREATE INDEX game_players_user ON game_players (user_id);

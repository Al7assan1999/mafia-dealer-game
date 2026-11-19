-- Live play: online rooms, presence, the bell (invites, join requests, friend notes) and online game history.
-- Rollback: ../rollbacks/0002_live.sql

-- an online room; its live state lives in the room's Durable Object, this row is what others need to see
CREATE TABLE rooms (
  code       TEXT NOT NULL CHECK (length(code) = 6 AND code NOT GLOB '*[^0-9]*'),
  host_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  status     TEXT NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'game')),
  created_at INTEGER NOT NULL,
  closed_at  INTEGER,
  PRIMARY KEY (code, created_at)
) STRICT;
-- a code is unique among open rooms only (codes are reused later)
CREATE UNIQUE INDEX rooms_open_code ON rooms (code) WHERE closed_at IS NULL;

-- presence: online = the app is open (its hub has a socket); room_code / room_status = in an online room
ALTER TABLE users ADD COLUMN online INTEGER NOT NULL DEFAULT 0 CHECK (online IN (0, 1));
ALTER TABLE users ADD COLUMN room_code TEXT;
ALTER TABLE users ADD COLUMN room_status TEXT NOT NULL DEFAULT '' CHECK (room_status IN ('', 'lobby', 'game'));

-- the bell: kind invite | join_request | let_in (room invites, 30 min) and friend_request | friend_accept (7 days)
CREATE TABLE notifications (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  from_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('invite', 'join_request', 'let_in', 'friend_request', 'friend_accept')),
  room_code  TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  read_at    INTEGER,
  CHECK ((kind IN ('invite', 'let_in')) = (room_code IS NOT NULL))
) STRICT;
CREATE INDEX notifications_user ON notifications (user_id, created_at);
CREATE INDEX notifications_from ON notifications (from_id, created_at);

-- finished online games (the server judged them)
CREATE TABLE games (
  id         TEXT PRIMARY KEY,
  host_id    TEXT REFERENCES users (id) ON DELETE SET NULL,
  winner     TEXT NOT NULL CHECK (winner IN ('mafia', 'citizens')),
  days       INTEGER NOT NULL CHECK (days >= 1),
  valid      INTEGER NOT NULL DEFAULT 1 CHECK (valid IN (0, 1)),
  rules      TEXT NOT NULL CHECK (json_valid(rules)),
  log        TEXT NOT NULL CHECK (json_valid(log)),     -- the engine's events
  stats      TEXT NOT NULL CHECK (json_valid(stats)),
  played_at  INTEGER NOT NULL
) STRICT;
CREATE TABLE game_players (
  game_id TEXT NOT NULL REFERENCES games (id) ON DELETE CASCADE,
  seat    INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 19),
  user_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  name    TEXT NOT NULL,
  role    TEXT NOT NULL CHECK (role IN ('mafia', 'doctor', 'detective', 'citizen')),
  alive   INTEGER NOT NULL CHECK (alive IN (0, 1)),
  PRIMARY KEY (game_id, seat)
) STRICT;
CREATE INDEX game_players_user ON game_players (user_id);

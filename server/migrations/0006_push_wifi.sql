-- Sprint 7: push notifications (S7-1) and Wi-Fi games added to online history by automatic rules (S7-2).
-- Only adds: the approval rules live in a settings row with a version, and every request keeps its raw record and the
-- rules version it was judged by, so the rules can change later without losing anything.

-- one push token per signed-in device (its session): gone with the session (sign-out, device removed, account deleted)
CREATE TABLE push_tokens (
  session_id TEXT PRIMARY KEY REFERENCES sessions (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  lang       TEXT NOT NULL DEFAULT 'en' CHECK (lang IN ('en', 'ar')),
  updated_at INTEGER NOT NULL
) STRICT;
CREATE INDEX push_tokens_user ON push_tokens (user_id);

-- settings the server reads at run time (JSON), changed by hand with a SQL script
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL CHECK (json_valid(value)),
  updated_at INTEGER NOT NULL
) STRICT;
INSERT INTO settings (key, value, updated_at) VALUES ('wifi_rules',
  '{"version":1,"minPlayers":4,"maxPlayers":20,"minSecondsPerRound":60,"maxAgeDays":7,"perHostPerDay":10,"confirmHours":48}', 0);

-- a host's request to add a finished Wi-Fi game to online history, kept as sent
CREATE TABLE wifi_requests (
  id            TEXT PRIMARY KEY,
  host_id       TEXT REFERENCES users (id) ON DELETE SET NULL,
  record        TEXT NOT NULL,                  -- the game record exactly as the host's phone sent it
  record_hash   TEXT NOT NULL,                  -- sha256 of the record: the same game can't be sent twice
  game_key      TEXT NOT NULL DEFAULT '',       -- the game's id on the phones ("<room>-<ended at>"), so they can match it
  app_version   TEXT NOT NULL DEFAULT '',
  played_at     INTEGER NOT NULL,
  rules_version INTEGER NOT NULL,               -- settings.wifi_rules.version it was judged by
  status        TEXT NOT NULL,                  -- pending | approved | declined | expired | rejected
  reason        TEXT,                           -- why rejected (a check) or declined
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,               -- the end of the confirmation window
  decided_at    INTEGER,
  game_id       TEXT REFERENCES games (id) ON DELETE SET NULL,  -- approved: the game in history
  host_seen     INTEGER NOT NULL DEFAULT 0      -- the result in the host's bell: 0 new, 1 read, 2 dismissed
) STRICT;
CREATE INDEX wifi_requests_host ON wifi_requests (host_id, created_at);
CREATE INDEX wifi_requests_hash ON wifi_requests (record_hash);
CREATE INDEX wifi_requests_pending ON wifi_requests (expires_at) WHERE status = 'pending';

-- each seat of a request and that player's answer (the host's own seat counts as confirmed)
CREATE TABLE wifi_seats (
  request_id  TEXT NOT NULL REFERENCES wifi_requests (id) ON DELETE CASCADE,
  seat        INTEGER NOT NULL,
  user_id     TEXT REFERENCES users (id) ON DELETE SET NULL,
  name        TEXT NOT NULL,
  answer      TEXT,                             -- null = not yet, 'yes', 'no'
  answered_at INTEGER,
  seen        INTEGER NOT NULL DEFAULT 0,       -- read in the bell
  PRIMARY KEY (request_id, seat)
) STRICT;
CREATE INDEX wifi_seats_user ON wifi_seats (user_id);

-- approved Wi-Fi games sit in `games` next to online ones, told apart here (History keeps them in separate tabs)
ALTER TABLE games ADD COLUMN source TEXT NOT NULL DEFAULT 'online';

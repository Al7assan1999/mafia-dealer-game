-- Accounts, sign-in, sessions, avatars and friends. Rollback: ../rollbacks/0001_init.sql
-- Times are milliseconds since 1970 (Date.now()). D1 enforces foreign keys.

CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  -- public @handle, chosen after the first sign-in (NULL until then)
  handle        TEXT UNIQUE COLLATE NOCASE
                CHECK (handle IS NULL OR (length(handle) BETWEEN 3 AND 20 AND handle NOT GLOB '*[^A-Za-z0-9_.]*')),
  display       TEXT NOT NULL CHECK (length(display) BETWEEN 1 AND 18),
  avatar_preset INTEGER NOT NULL DEFAULT 0 CHECK (avatar_preset BETWEEN 0 AND 9),
  avatar_ver    INTEGER NOT NULL DEFAULT 0 CHECK (avatar_ver >= 0),  -- 0: the preset is shown; n: photo version n
  fav_role      TEXT NOT NULL DEFAULT '' CHECK (fav_role IN ('', 'mafia', 'doctor', 'detective', 'citizen')),
  show_online   INTEGER NOT NULL DEFAULT 1 CHECK (show_online IN (0, 1)),
  created_at    INTEGER NOT NULL
) STRICT;

-- how an account signs in: an email address (code) or a Google account; several per user
CREATE TABLE identities (
  kind       TEXT NOT NULL CHECK (kind IN ('email', 'google')),
  subject    TEXT NOT NULL,              -- the email address, or Google's account id ("sub")
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  email      TEXT NOT NULL,              -- verified, lowercase
  created_at INTEGER NOT NULL,
  PRIMARY KEY (kind, subject)
) STRICT;
CREATE INDEX identities_user ON identities (user_id);
CREATE INDEX identities_email ON identities (email);

-- the one live sign-in code per email address (only its hash)
CREATE TABLE email_codes (
  email      TEXT PRIMARY KEY,
  code_hash  TEXT NOT NULL,
  tries      INTEGER NOT NULL DEFAULT 0 CHECK (tries >= 0),
  sent_at    INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
) STRICT;

-- fixed-window counters (key = 'mail:<email>' | 'ip:<address>')
CREATE TABLE rate_limits (
  key          TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL CHECK (count >= 0)
) STRICT;

CREATE TABLE sessions (
  id           TEXT PRIMARY KEY,         -- shown to the user (sign out a device); not the token
  token_hash   TEXT NOT NULL UNIQUE,     -- SHA-256 of the bearer token
  user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  device       TEXT NOT NULL CHECK (length(device) BETWEEN 1 AND 40),
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  expires_at   INTEGER NOT NULL
) STRICT;
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE avatars (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  mime    TEXT NOT NULL CHECK (mime IN ('image/jpeg', 'image/png', 'image/webp')),
  data    BLOB NOT NULL CHECK (length(data) <= 150000),
  ver     INTEGER NOT NULL CHECK (ver > 0)
) STRICT;

-- one row per pair (a < b), whoever asked first
CREATE TABLE friendships (
  a            TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  b            TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL,
  status       TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
  created_at   INTEGER NOT NULL,
  accepted_at  INTEGER,
  PRIMARY KEY (a, b),
  CHECK (a < b),
  CHECK (requested_by IN (a, b)),
  CHECK ((status = 'accepted') = (accepted_at IS NOT NULL))
) STRICT;
CREATE INDEX friendships_b ON friendships (b);

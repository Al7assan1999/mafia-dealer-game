-- Sprint 5 (S5-2): Google Play's user-generated-content rule. Blocks between accounts, reports with a snapshot of what
-- was reported (kept even after the room or the reported account is gone, for moderation), and bans.
CREATE TABLE blocks (
  blocker_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
) STRICT;
CREATE INDEX blocks_blocked ON blocks (blocked_id);

CREATE TABLE reports (
  id          TEXT PRIMARY KEY,
  reporter_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  reported_id TEXT REFERENCES users (id) ON DELETE SET NULL,
  reason      TEXT NOT NULL CHECK (reason IN ('spam', 'harassment', 'hate', 'other')),
  note        TEXT NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  snapshot    TEXT NOT NULL CHECK (json_valid(snapshot)),  -- who (display, handle) and the message, if any
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'banned')),
  created_at  INTEGER NOT NULL,
  handled_at  INTEGER
) STRICT;
CREATE INDEX reports_open ON reports (created_at) WHERE status = 'open';

ALTER TABLE users ADD COLUMN banned_at INTEGER;

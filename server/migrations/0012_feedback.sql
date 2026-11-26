-- Sprint 19 (1.2.0): the suggestions box. A player's suggestion or problem, with at most one screenshot (a small
-- JPEG, ≤ 300 KB), read and emptied by the admin. Only adds a table. Rollback: ../rollbacks/0012_feedback.sql
CREATE TABLE feedback (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('idea', 'problem')),
  text       TEXT NOT NULL CHECK (length(text) BETWEEN 10 AND 1000),
  info       TEXT NOT NULL CHECK (json_valid(info)),         -- app version, build, language, Android version
  game_id    TEXT,                                           -- P2: the online game it is about (one of the sender's)
  image      BLOB CHECK (image IS NULL OR length(image) <= 300000),
  status     TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'read', 'done')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT;
CREATE INDEX feedback_user ON feedback (user_id, created_at);
CREATE INDEX feedback_time ON feedback (created_at);

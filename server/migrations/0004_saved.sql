-- Sprint 3 (S3-5): an account's saved player names (the setup's chips) and its last setup, as JSON. Deleted with the
-- account. One row per account; either column may be empty.
CREATE TABLE saved (
  user_id    TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  names      TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(names) AND json_type(names) = 'array'),
  setup      TEXT CHECK (setup IS NULL OR json_valid(setup)),
  updated_at INTEGER NOT NULL
) STRICT;

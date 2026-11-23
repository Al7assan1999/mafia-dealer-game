-- Sprint 9 (S9-5 AC2): the bell keeps handled items 24 h, read-only with their result, instead of deleting them.
ALTER TABLE notifications ADD COLUMN handled_at INTEGER;
ALTER TABLE notifications ADD COLUMN result TEXT;  -- joined | let_in | accepted | declined | dismissed

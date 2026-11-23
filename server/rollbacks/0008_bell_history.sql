-- Rollback of migrations/0008_bell_history.sql (handled bell items lose their result; they are deleted, as before).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0008_bell_history.sql
-- then: DELETE FROM d1_migrations WHERE name = '0008_bell_history.sql';
DELETE FROM notifications WHERE handled_at IS NOT NULL;
ALTER TABLE notifications DROP COLUMN result;
ALTER TABLE notifications DROP COLUMN handled_at;

-- Rollback of migrations/0012_feedback.sql: the suggestions box goes, with its rows and screenshots.
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0012_feedback.sql
-- then: DELETE FROM d1_migrations WHERE name = '0012_feedback.sql';
DROP TABLE IF EXISTS feedback;

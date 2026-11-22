-- Rollback of migrations/0005_safety.sql (blocks, reports and bans are lost).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0005_safety.sql
-- then: DELETE FROM d1_migrations WHERE name = '0005_safety.sql';
DROP INDEX IF EXISTS reports_open;
DROP TABLE IF EXISTS reports;
DROP INDEX IF EXISTS blocks_blocked;
DROP TABLE IF EXISTS blocks;
ALTER TABLE users DROP COLUMN banned_at;

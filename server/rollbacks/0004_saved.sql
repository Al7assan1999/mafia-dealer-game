-- Rollback of migrations/0004_saved.sql (saved names and setups are lost).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0004_saved.sql
-- then: DELETE FROM d1_migrations WHERE name = '0004_saved.sql';
DROP TABLE IF EXISTS saved;

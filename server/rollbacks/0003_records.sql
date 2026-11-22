-- Rollback of migrations/0003_records.sql (the saved game records are lost; the games themselves stay).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0003_records.sql
-- then: DELETE FROM d1_migrations WHERE name = '0003_records.sql';
ALTER TABLE games DROP COLUMN record;

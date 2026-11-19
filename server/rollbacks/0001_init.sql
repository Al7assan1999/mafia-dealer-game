-- Rollback of migrations/0001_init.sql (drops everything it created; data is lost).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0001_init.sql
-- then delete its row: DELETE FROM d1_migrations WHERE name = '0001_init.sql';
DROP TABLE IF EXISTS friendships;
DROP TABLE IF EXISTS avatars;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS rate_limits;
DROP TABLE IF EXISTS email_codes;
DROP TABLE IF EXISTS identities;
DROP TABLE IF EXISTS users;

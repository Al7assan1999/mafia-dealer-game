-- Rollback of migrations/0002_live.sql (drops what it created; online history is lost).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0002_live.sql
-- then: DELETE FROM d1_migrations WHERE name = '0002_live.sql';
DROP TABLE IF EXISTS game_players;
DROP TABLE IF EXISTS games;
DROP TABLE IF EXISTS notifications;
DROP INDEX IF EXISTS rooms_open_code;
DROP TABLE IF EXISTS rooms;
ALTER TABLE users DROP COLUMN room_status;
ALTER TABLE users DROP COLUMN room_code;
ALTER TABLE users DROP COLUMN online;

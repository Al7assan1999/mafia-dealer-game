-- Rollback of migrations/0009_room_size.sql (the drawer loses the player count; nothing else changes).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0009_room_size.sql
-- then: DELETE FROM d1_migrations WHERE name = '0009_room_size.sql';
ALTER TABLE users DROP COLUMN room_size;

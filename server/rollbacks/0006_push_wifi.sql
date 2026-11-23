-- Rollback of migrations/0006_push_wifi.sql (push tokens, the Wi-Fi rules and every Wi-Fi request are lost; approved
-- Wi-Fi games are deleted from history, since without `source` they would look like online games).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0006_push_wifi.sql
-- then: DELETE FROM d1_migrations WHERE name = '0006_push_wifi.sql';
DELETE FROM games WHERE source = 'wifi';
ALTER TABLE games DROP COLUMN source;
DROP INDEX IF EXISTS wifi_seats_user;
DROP TABLE IF EXISTS wifi_seats;
DROP INDEX IF EXISTS wifi_requests_pending;
DROP INDEX IF EXISTS wifi_requests_hash;
DROP INDEX IF EXISTS wifi_requests_host;
DROP TABLE IF EXISTS wifi_requests;
DROP TABLE IF EXISTS settings;
DROP INDEX IF EXISTS push_tokens_user;
DROP TABLE IF EXISTS push_tokens;

-- Rollback of migrations/0007_stats_legacy.sql (imported old games, name claims, title notes and the leaderboard switch
-- are lost).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0007_stats_legacy.sql
-- then: DELETE FROM d1_migrations WHERE name = '0007_stats_legacy.sql';
DROP INDEX IF EXISTS legacy_claims_user;
DROP TABLE IF EXISTS legacy_claims;
DROP INDEX IF EXISTS legacy_seats_name;
DROP TABLE IF EXISTS legacy_seats;
DROP INDEX IF EXISTS legacy_games_importer;
DROP TABLE IF EXISTS legacy_games;
DELETE FROM settings WHERE key IN ('old_players', 'titles');
DROP INDEX IF EXISTS bell_notes_user;
DROP TABLE IF EXISTS bell_notes;
ALTER TABLE users DROP COLUMN on_board;

-- Rollback of migrations/0013_title_tie.sql: Best Doctor back to Sami (the removed bell note is not brought back).
-- Run by hand: npx wrangler d1 execute DB --remote --file rollbacks/0013_title_tie.sql
-- then: DELETE FROM d1_migrations WHERE name = '0013_title_tie.sql';
UPDATE settings SET value = json_set(value, '$.doc', 'f2250a3e-fe90-4606-a3af-206700603e23')
 WHERE key = 'titles' AND json_extract(value, '$.doc') = 'a1edc5b5-8f62-44b8-85ec-ee03bb376a43';

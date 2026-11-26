-- 1.2.1 hotfix: Best Doctor went from Alhassan to Sami on a 13-13 tie (the first in the game list won a tie). From 1.2.1
-- a tie leaves a title with its holder; this puts Best Doctor back with him and removes the "Sami took it" note.
-- Data only, and only if it is still as the tie left it (a no-op anywhere else). Rollback: ../rollbacks/0013_title_tie.sql
UPDATE settings SET value = json_set(value, '$.doc', 'a1edc5b5-8f62-44b8-85ec-ee03bb376a43')
 WHERE key = 'titles' AND json_extract(value, '$.doc') = 'f2250a3e-fe90-4606-a3af-206700603e23';
DELETE FROM bell_notes WHERE kind = 'title_lost' AND user_id = 'a1edc5b5-8f62-44b8-85ec-ee03bb376a43'
 AND json_extract(data, '$.title') = 'doc' AND json_extract(data, '$.by') = 'f2250a3e-fe90-4606-a3af-206700603e23';

-- Sprint 1 (S1-6): a finished online game keeps its record (the dealt game plus every action in order), so the engine
-- can replay and check it. Games saved before this have none (NULL). Nothing already stored changes.
ALTER TABLE games ADD COLUMN record TEXT CHECK (record IS NULL OR json_valid(record));

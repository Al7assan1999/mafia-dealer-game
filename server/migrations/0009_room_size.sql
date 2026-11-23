-- Sprint 12 (P3): how many players are in a friend's room, shown next to "In a room" / "In a game" in the drawer.
-- Only adds; 0 when not in a room.
ALTER TABLE users ADD COLUMN room_size INTEGER NOT NULL DEFAULT 0;

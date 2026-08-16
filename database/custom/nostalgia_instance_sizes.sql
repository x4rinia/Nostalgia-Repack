-- Nostalgia: keep the original large endgame dungeons as 10-player instances.
-- The server targets content patch 1.12 (database patch 8); LBRS/UBRS already use 10 players there.
UPDATE `map_template`
SET `player_limit` = 10
WHERE `entry` IN (230, 289, 329)
  AND `patch` = 8;

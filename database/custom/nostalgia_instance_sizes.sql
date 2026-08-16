-- Nostalgia: keep the original large dungeons as 10-player instances.
-- The server targets content patch 1.12 (database patch 8); LBRS/UBRS already use 10 players there.
UPDATE `map_template`
SET `player_limit` = 10
WHERE `entry` IN (230, 289, 329)
  AND `patch` = 8;

-- Maraudon is already a 10-player dungeon from patch 1 onward.  Keep that
-- value explicit for every patch level used by this repack.
UPDATE `map_template`
SET `player_limit` = 10
WHERE `entry` = 349
  AND `patch` BETWEEN 1 AND 8;

-- Nostalgia: Gurubashi Arena Booty Run
-- Start at every full server hour and remain active for two minutes.
UPDATE `game_event`
SET `start_time` = '2021-01-01 00:00:00',
    `end_time` = '2038-01-01 00:59:59',
    `occurence` = 3600,
    `length` = 120
WHERE `entry` = 16;

-- Nostalgia: Transmogger in den Banken von Sturmwind und Orgrimmar.
-- Die beiden Vorlagen verwenden unterschiedliche Modelle, aber dasselbe C++-Gossip-Skript.

DELETE FROM `creature` WHERE `guid` IN (900500, 900501);
DELETE FROM `creature_template` WHERE `entry` IN (900500, 900501);

INSERT INTO `creature_template`
    (`entry`, `patch`, `name`, `subname`, `level_min`, `level_max`, `faction`, `npc_flags`, `gossip_menu_id`,
     `display_id1`, `display_scale1`, `display_probability1`, `display_total_probability`, `unit_class`, `civilian`, `script_name`)
VALUES
    (900500, 0, 'Transmogger', 'Nostalgia Garderobe', 60, 60, 35, 1, 0, 1450, 1, 100, 100, 1, 1, 'custom_transmogger'),
    (900501, 0, 'Transmogger', 'Nostalgia Garderobe', 60, 60, 35, 1, 0, 1310, 1, 100, 100, 1, 1, 'custom_transmogger');

-- Sturmwind-Bank, neben den vorhandenen Bankangestellten.
INSERT INTO `creature`
    (`guid`, `id`, `map`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecsmin`, `spawntimesecsmax`, `wander_distance`, `movement_type`, `spawn_flags`, `patch_min`, `patch_max`)
VALUES
    (900500, 900500, 0, -8928.50, 613.00, 99.61, 3.70, 300, 300, 0, 0, 0, 0, 10);

-- Orgrimmar-Bank, neben den vorhandenen Bankangestellten.
INSERT INTO `creature`
    (`guid`, `id`, `map`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecsmin`, `spawntimesecsmax`, `wander_distance`, `movement_type`, `spawn_flags`, `patch_min`, `patch_max`)
VALUES
    (900501, 900501, 1, 1625.00, -4384.00, 11.81, 3.50, 300, 300, 0, 0, 0, 0, 10);

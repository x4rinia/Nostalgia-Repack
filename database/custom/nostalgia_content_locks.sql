-- Nostalgia content locks: Die Eingange bleiben sichtbar, aber die Instanzen sind nicht betretbar.
-- Betroffen: Zul'Gurub (309), Ruinen von Ahn'Qiraj (509), Tempel von Ahn'Qiraj (531).
-- MC, BWL, Naxxramas und alle anderen Instanzen werden nicht veraendert.

DELETE FROM `conditions` WHERE `condition_entry` = 900600;
INSERT INTO `conditions` (`condition_entry`, `type`, `value1`, `value2`, `value3`, `value4`, `flags`)
VALUES (900600, 0, 0, 0, 0, 0, 1);

DELETE FROM `areatrigger_teleport` WHERE `id` IN (3928, 4008, 4010) AND `patch` = 10;

INSERT INTO `areatrigger_teleport`
    (`id`, `patch`, `name`, `message`, `required_level`, `required_condition`, `target_map`, `target_position_x`, `target_position_y`, `target_position_z`, `target_orientation`)
VALUES
    (3928, 10, 'Zul''Gurub - Entrance', 'Dieser Raid ist gesperrt und kein Bestandteil von Nostalgia.', 50, 900600, 309, -11916.6, -1243.52, 92.5338, 4.71239),
    (4008, 10, 'Ruins Of Ahn''Qiraj - Entrance', 'Dieser Raid ist gesperrt und kein Bestandteil von Nostalgia.', 50, 900600, 509, -8436.53, 1519.17, 31.907, 2.61799),
    (4010, 10, 'Temple of Ahn''Qiraj - Entrance', 'Dieser Raid ist gesperrt und kein Bestandteil von Nostalgia.', 50, 900600, 531, -8221.35, 2014.34, 129.071, 0.872665);

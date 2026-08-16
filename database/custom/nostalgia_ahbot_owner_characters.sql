-- Nostalgia AH-Bot seller name
-- Creates one technical, offline character without a login account.  It only
-- exists so the Vanilla client can resolve the seller GUID to the name Ahbot.

SET @ahbot_guid := (SELECT `guid` FROM `characters` WHERE `name` = 'Ahbot' LIMIT 1);

CREATE TEMPORARY TABLE `nostalgia_ahbot_template` AS
SELECT * FROM `characters` ORDER BY `guid` LIMIT 1;

UPDATE `nostalgia_ahbot_template`
SET `guid` = 900000,
    `account` = 0,
    `name` = 'Ahbot',
    `race` = 1,
    `class` = 1,
    `gender` = 0,
    `level` = 1,
    `online` = 0,
    `health` = 100,
    `power1` = 0,
    `power2` = 0,
    `power3` = 0,
    `power4` = 0,
    `power5` = 0;

INSERT INTO `characters`
SELECT * FROM `nostalgia_ahbot_template`
WHERE @ahbot_guid IS NULL
  AND NOT EXISTS (SELECT 1 FROM `characters` WHERE `guid` = 900000);

SET @ahbot_guid := (SELECT `guid` FROM `characters` WHERE `name` = 'Ahbot' LIMIT 1);

-- Existing bot auctions have seller_guid 0.  Player auctions are untouched.
UPDATE `auction`
SET `seller_guid` = @ahbot_guid
WHERE `seller_guid` = 0
  AND @ahbot_guid IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS `nostalgia_ahbot_template`;

-- Nostalgia: dauerhafte Transmog-Optiken pro Charakter und ausgeruestetem Item.
-- Das Originalitem und die Vorlage werden nicht veraendert oder verbraucht.

CREATE TABLE IF NOT EXISTS `character_transmog`
(
    `item_guid`          INT UNSIGNED NOT NULL,
    `owner_guid`         INT UNSIGNED NOT NULL,
    `display_item_entry` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`item_guid`),
    KEY `idx_owner_guid` (`owner_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

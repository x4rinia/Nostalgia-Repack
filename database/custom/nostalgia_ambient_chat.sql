-- Nostalgia: messages are sent as named chat lines in the corresponding /1 zone channel.
CREATE TABLE IF NOT EXISTS `nostalgia_ambient_chat` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `zone_id` INT UNSIGNED NOT NULL,
    `channel_name` VARCHAR(128) NOT NULL,
    `sender_guid` INT UNSIGNED NOT NULL,
    `sender_name` VARCHAR(12) NOT NULL,
    `race` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `gender` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `class` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `level` TINYINT UNSIGNED NOT NULL DEFAULT 60,
    `guild_name` VARCHAR(48) NOT NULL DEFAULT 'Nostalgia',
    `message` VARCHAR(255) NOT NULL,
    `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE KEY `sender_message` (`sender_guid`, `message`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `nostalgia_ambient_chat` ADD COLUMN IF NOT EXISTS `level` TINYINT UNSIGNED NOT NULL DEFAULT 60 AFTER `class`;
ALTER TABLE `nostalgia_ambient_chat` ADD COLUMN IF NOT EXISTS `guild_name` VARCHAR(48) NOT NULL DEFAULT 'Nostalgia' AFTER `level`;

DELETE FROM `nostalgia_ambient_chat`;

INSERT INTO `nostalgia_ambient_chat` (`zone_id`, `channel_name`, `sender_guid`, `sender_name`, `race`, `gender`, `class`, `message`) VALUES
(40, 'World', 900001, 'Corvin', 1, 0, 1, 'lfm dm noch 2 dd dann go'),
(40, 'World', 900002, 'Hedwig', 1, 1, 5, 'suche tank + heal fuer dm'),
(40, 'World', 900003, 'Brom', 3, 0, 1, 'need noch healer fuer deadmines'),
(40, 'World', 900004, 'Lysa', 1, 1, 8, 'wer macht defias quest mit mir xD'),
(40, 'World', 900005, 'Tarek', 1, 0, 4, 'LFM DM NEED HEAL GO GO'),
(40, 'World', 900006, 'Mirelle', 4, 1, 5, 'heal fuer dm da einfach inv'),
(12, 'World', 900011, 'Aldren', 1, 0, 1, 'kobolde mine noch wer dabei?'),
(12, 'World', 900012, 'Mira', 1, 1, 8, 'brauch nur noch 3 bandanas pls'),
(12, 'World', 900013, 'Thoran', 3, 0, 1, 'hat wer leinen ueber ^^'),
(12, 'World', 900014, 'Elira', 1, 1, 5, 'rolf escort noch offen?'),
(12, 'World', 900015, 'Garen', 1, 0, 4, 'goldhain ist voll heute lol'),
(12, 'World', 900016, 'Nelia', 4, 1, 8, 'mache taschen gegen stoff'),
(10, 'World', 900021, 'Marlow', 1, 0, 1, 'morladiem wieder da vorsicht'),
(10, 'World', 900022, 'Selene', 1, 1, 5, 'suche grp fuer friedhof'),
(10, 'World', 900023, 'Garrick', 3, 0, 4, 'wer kennt den weg zur gruft?'),
(10, 'World', 900024, 'Nora', 1, 1, 8, 'diese spinnen nerven so hart xD'),
(10, 'World', 900025, 'Roderick', 1, 0, 1, 'LFM DUSKWOOD QUESTS'),
(10, 'World', 900026, 'Iria', 4, 1, 5, 'kann jemand kurz nach darkshire helfen?'),
(17, 'World', 900031, 'Krag', 2, 0, 1, 'lfm wc need heal'),
(17, 'World', 900032, 'Zalra', 2, 1, 8, 'ratchet escort noch offen jemand?'),
(17, 'World', 900033, 'Moktar', 2, 0, 4, 'harpyien federn dauern ewig omg'),
(17, 'World', 900034, 'Rikka', 2, 1, 5, 'suche noch 2 fuer kfd'),
(17, 'World', 900035, 'Dren', 8, 0, 1, 'piraten bei ratchet farmen?'),
(17, 'World', 900036, 'Vexa', 2, 1, 8, 'CROSSROADS BEST PLACE xD'),
(33, 'General', 900041, 'Keksdieb', 1, 0, 4, 'lfm sfk noch heal dann los'),
(33, 'General', 900042, 'Tankwart', 3, 0, 1, 'need tank fuer bfd bitte kein afk'),
(33, 'General', 900043, 'Bimmelbert', 7, 0, 8, 'wer kann mir nen portal nach sw machen?'),
(33, 'General', 900044, 'Milchbart', 1, 0, 2, 'suche noch 2 fuer gnomer'),
(33, 'General', 900045, 'Fluffi', 4, 1, 11, 'hat jemand moosachat zu viel?'),
(33, 'General', 900046, 'Critney', 1, 1, 8, 'mage food in if gratis ^^'),
(33, 'General', 900047, 'Drachenei', 3, 0, 3, 'lfm elite quest im oedland'),
(33, 'General', 900048, 'Wurstbrot', 1, 0, 1, 'brauche noch 1 fuer kloster bib'),
(33, 'General', 900049, 'Mogli', 4, 0, 3, 'kann wer kurz bei nesingwary helfen?'),
(33, 'General', 900050, 'Schlumpfi', 7, 0, 9, 'verkaufe kleine seelensplitter sehr billig xD'),
(33, 'General', 900051, 'Opaheiler', 3, 0, 5, 'lfm sm cath need 1 dd'),
(33, 'General', 900052, 'Stabstich', 1, 1, 4, 'wer macht rfc bin grad erst 16'),
(33, 'General', 900053, 'Gnombert', 7, 0, 1, 'suche ingenieur der mir was baut'),
(33, 'General', 900054, 'Zimtstern', 1, 1, 5, 'heal fuer zf da einfach inv'),
(33, 'General', 900055, 'Trollbert', 8, 0, 3, 'lfm zf graveyard farm'),
(33, 'General', 900056, 'Puddingtod', 5, 1, 9, 'brauche gruppe die nicht alles pullt pls'),
(33, 'General', 900057, 'Schurkin', 1, 1, 4, 'kaufe blindpulver mats'),
(33, 'General', 900058, 'Angler', 3, 0, 3, 'wo gibts nochmal den dicksten fisch?'),
(33, 'General', 900059, 'Eisenhelm', 3, 0, 1, 'lfm ulda quest run need heal'),
(33, 'General', 900060, 'Knappe', 1, 0, 2, 'kann palas auch mal heilen oder nur afk sein?'),
(33, 'General', 900061, 'Frostbeule', 1, 1, 8, 'port nach darn bitte tippe gut'),
(33, 'General', 900062, 'Blubber', 6, 0, 7, 'lfm mara princess run'),
(33, 'General', 900063, 'Knusper', 1, 1, 5, 'suche verzauberer fuer brust'),
(33, 'General', 900064, 'Mausbert', 7, 0, 4, 'wer hat noch platz fuer dm?'),
(33, 'General', 900065, 'Dotschaden', 5, 0, 9, 'need noch 2 fuer sunken temple'),
(33, 'General', 900066, 'Totemheld', 2, 0, 7, 'lfm st voll quest run'),
(33, 'General', 900067, 'Bananajoe', 6, 0, 1, 'hab mich wieder verlaufen in mara lol'),
(33, 'General', 900068, 'Hufschlag', 6, 1, 11, 'suche lederer 225'),
(33, 'General', 900069, 'Rattenfang', 5, 0, 4, 'LFM BRD PRISON NEED HEAL'),
(33, 'General', 900070, 'Krampfadern', 1, 0, 2, 'wer kennt den weg zu angerforge?'),
(33, 'General', 900071, 'Lottesocke', 4, 1, 5, 'noch wer fuer lbrs key?'),
(33, 'General', 900072, 'Manabrot', 1, 0, 8, 'verkaufe wasser und brot in sw'),
(33, 'General', 900073, 'Schafkopf', 3, 0, 1, 'lfm brd arena nur schnelle gruppe'),
(33, 'General', 900074, 'Wichtel', 7, 1, 9, 'brauche noch 1 fuer dm east'),
(33, 'General', 900075, 'Waldfee', 4, 1, 11, 'suche grp fuer hinterland elite'),
(33, 'General', 900076, 'Grimbeard', 3, 0, 1, 'need healer fuer lbrs dann go'),
(33, 'General', 900077, 'Kaffeejunk', 1, 0, 4, 'bin nur kurz afk kaffee holen'),
(33, 'General', 900078, 'Blitzdings', 7, 1, 8, 'wer braucht noch port?'),
(33, 'General', 900079, 'Fischkopp', 8, 0, 7, 'lfm zf noch tank'),
(33, 'General', 900080, 'Feuerknopf', 5, 1, 9, 'suchen 2 dd fuer brd'),
(33, 'General', 900081, 'Ruestung', 1, 0, 1, 'brauche 5 gold fuer mount pls no joke'),
(33, 'General', 900082, 'Goldzahn', 3, 0, 4, 'kaufe thoriumbarren'),
(33, 'General', 900083, 'Lootgoblin', 7, 0, 3, 'wer rollt need auf graue sachen? xD'),
(33, 'General', 900084, 'Palaheilt', 1, 1, 2, 'lfm scholo need tank'),
(33, 'General', 900085, 'Rogueschaf', 1, 0, 4, 'suche 1 fuer strat live'),
(33, 'General', 900086, 'Stofflumpi', 4, 1, 5, 'mache mondstoff cd gegen tip'),
(33, 'General', 900087, 'Todesrose', 5, 1, 9, 'lfm strat ud brauche heiler'),
(33, 'General', 900088, 'Knuddelfee', 4, 1, 11, 'wer hilft bei demon quest?'),
(33, 'General', 900089, 'Uebereber', 2, 0, 1, 'need noch 1 fuer ubrs 10er'),
(33, 'General', 900090, 'Spitzhacke', 3, 0, 3, 'verkaufe arkanit cd'),
(33, 'General', 900091, 'Rundschlag', 1, 0, 1, 'lfm ony pre quest'),
(33, 'General', 900092, 'Feuerzopf', 1, 1, 8, 'port service if sw dm'),
(33, 'General', 900093, 'Hexenheinz', 5, 0, 9, 'wer hat noch felcloth?'),
(33, 'General', 900094, 'Druidenopa', 6, 0, 11, 'naxx attunement noch wer?'),
(33, 'General', 900095, 'Schurkenjoe', 2, 0, 4, 'lfm mc trash farm'),
(33, 'General', 900096, 'Beutelratte', 1, 1, 5, 'mache 10 slot taschen bring stoff'),
(33, 'General', 900097, 'Flauschi', 4, 1, 3, 'bitte nicht noch ein hunter pet pull'),
(33, 'General', 900098, 'Brezelbert', 3, 0, 2, 'LFM BWL NEED PRIEST'),
(33, 'General', 900099, 'Ragnarosfan', 2, 0, 7, 'mc heute abend wer ist dabei?'),
(33, 'General', 900100, 'Wirbelwind', 1, 1, 8, 'ich bin schon wieder in die lava gefallen xD'),
(33, 'General', 900101, 'Klingenmax', 1, 0, 1, 'lfm strat live 10er need heal dann direkt los'),
(33, 'General', 900102, 'Mooshexe', 4, 1, 11, 'scholo 10er gesucht brauch noch 2 dd'),
(33, 'General', 900103, 'Lichtpala', 1, 1, 2, 'heal fuer strat ud da bitte inv'),
(33, 'General', 900104, 'Stahlschuh', 3, 0, 1, 'lfm ubrs 10er brauche noch 1 healer'),
(33, 'General', 900105, 'Kesselkeks', 7, 1, 8, 'lbrs 10er full run need tank pls'),
(33, 'General', 900106, 'Schattenoma', 5, 1, 5, 'suche nette grp fuer scholo 10er kein rush :D'),
(33, 'General', 900107, 'Axtimwald', 2, 0, 1, 'UBRS 10ER NEED DD KEIN LEAVEN NACH REND'),
(33, 'General', 900108, 'Frosttoast', 1, 0, 8, 'lfm strat baron 10er noch 1 dd'),
(33, 'General', 900109, 'Totemklaus', 2, 0, 7, 'lbrs key run 10er wer kommt mit?'),
(33, 'General', 900110, 'Rosenstich', 4, 1, 4, 'scholo 10er need tank bin schon am see'),
(33, 'General', 900111, 'Blechdose', 3, 0, 1, 'strat live 10er lfm 2 dd'),
(33, 'General', 900112, 'Wolkenbrot', 6, 1, 11, 'ubrs 10er rend run brauche noch heal'),
(33, 'General', 900113, 'Seelenpeter', 5, 0, 9, 'lfm scholo 10er bringe summon mit ^^'),
(33, 'General', 900114, 'Grimmling', 8, 0, 4, 'wer hat bock auf lbrs 10er? bin tank'),
(33, 'General', 900115, 'Heiltrank', 1, 1, 5, 'strat ud 10er suche noch 2 dann go go'),
(33, 'General', 900116, 'Kritkrieger', 3, 0, 1, 'ubrs 10er leeroy style xD noch 3'),
(33, 'General', 900117, 'Arkanmama', 1, 1, 8, 'scholo 10er nur quest run pls nicht alles skippen'),
(33, 'General', 900118, 'Rindenmann', 4, 0, 11, 'lbrs 10er need heal und 2 dd'),
(33, 'General', 900119, 'Knochenhexe', 5, 1, 9, 'lfm strat baron 10er need tank'),
(33, 'General', 900120, 'Kampfkeks', 7, 0, 4, 'ubrs 10er letzte plaetze wer will rend?'),
(14, 'General', 900121, 'Schnetzler', 2, 0, 1, 'lfm rfc noch heal dann los'),
(85, 'General', 900122, 'Gruftmama', 5, 1, 5, 'wer macht tirisfal quests mit?'),
(215, 'General', 900123, 'Totemtrude', 6, 1, 7, 'wailing caverns suche noch 3'),
(17, 'General', 900124, 'Raptorzahn', 8, 0, 3, 'need gruppe fuer wc bin hunter'),
(1637, 'General', 900125, 'Mokkabohne', 2, 1, 8, 'orgrimmar portal pls? ach ja vanilla xD'),
(130, 'General', 900126, 'Seuchenzahn', 5, 0, 4, 'sfk lfm tank und heal'),
(215, 'General', 900127, 'Hufstampfer', 6, 0, 1, 'bin tank fuer rfk einfach inv'),
(331, 'General', 900128, 'Trolltoast', 8, 1, 5, 'bfd quest run wer kommt mit?'),
(14, 'General', 900129, 'Kriegsgurke', 2, 0, 9, 'lfm rfk need 2 dd'),
(85, 'General', 900130, 'Knochenbart', 5, 0, 1, 'strat 10er suche noch 1 heal'),
(400, 'General', 900131, 'Wasserkuh', 6, 1, 11, 'feralas noch wer auf hippogreif quests?'),
(331, 'General', 900132, 'Voodoomaus', 8, 1, 8, 'zulfarrak lfm bitte keine leaver'),
(14, 'General', 900133, 'Axtkeks', 2, 0, 4, 'brd 10er nur emperor und quests'),
(85, 'General', 900134, 'Grufthexe', 5, 1, 9, 'scholo 10er summon steht'),
(215, 'General', 900135, 'Donnerhuf', 6, 0, 7, 'lbrs 10er suche gruppe'),
(17, 'General', 900136, 'Speerfisch', 8, 0, 3, 'ubrs 10er noch 2 dann rend'),
(14, 'General', 900137, 'Zornbolzen', 2, 0, 1, 'mc pre quests wer braucht noch?'),
(85, 'General', 900138, 'Modermaus', 5, 1, 5, 'heal fuer strat oder scholo da'),
(400, 'General', 900139, 'Mondsichel', 6, 1, 3, 'maraudon 10er princess run?'),
(331, 'General', 900140, 'Hexhex', 8, 1, 7, 'bwl attunement helfe gern'),
(1637, 'General', 900141, 'Blutbrot', 2, 0, 9, 'naxx attunement noch jemand?');

-- Messages are shown through the Vanilla client's automatically joined /1 General channel.
UPDATE `nostalgia_ambient_chat` SET `channel_name` = 'General';
UPDATE `nostalgia_ambient_chat` SET `level` = 18 + (`sender_guid` % 43);
UPDATE `nostalgia_ambient_chat`
SET `guild_name` = CASE
    WHEN `sender_guid` BETWEEN 900001 AND 900006 THEN 'Die Keksbande'
    WHEN `sender_guid` BETWEEN 900011 AND 900016 THEN 'Goldhain Wache'
    WHEN `sender_guid` BETWEEN 900021 AND 900026 THEN 'Nachtwache'
    WHEN `sender_guid` BETWEEN 900031 AND 900036 THEN 'Kobold Kompanie'
    WHEN `sender_guid` BETWEEN 900041 AND 900045 THEN 'Feierabendraid'
    WHEN `sender_guid` BETWEEN 900046 AND 900050 THEN 'Kritische Masse'
    WHEN `sender_guid` BETWEEN 900051 AND 900055 THEN 'Die Letzte Instanz'
    WHEN `sender_guid` BETWEEN 900056 AND 900060 THEN 'Stammgruppe Mittwoch'
    WHEN `sender_guid` BETWEEN 900061 AND 900065 THEN 'Gnomischer Fortschritt'
    WHEN `sender_guid` BETWEEN 900066 AND 900070 THEN 'Wipe Zum Fruehstueck'
    WHEN `sender_guid` BETWEEN 900071 AND 900075 THEN 'Die Taschenhelden'
    WHEN `sender_guid` BETWEEN 900076 AND 900080 THEN 'Murloc Fanclub'
    WHEN `sender_guid` BETWEEN 900081 AND 900085 THEN 'Zehn Mann Chaos'
    WHEN `sender_guid` BETWEEN 900086 AND 900090 THEN 'Schwarze Schafe'
    WHEN `sender_guid` BETWEEN 900091 AND 900095 THEN 'Kaffee und Kekse'
    WHEN `sender_guid` BETWEEN 900096 AND 900100 THEN 'Raid Ohne Plan'
    WHEN `sender_guid` BETWEEN 900101 AND 900105 THEN 'Die Letzten Helden'
    WHEN `sender_guid` BETWEEN 900106 AND 900110 THEN 'Wipe Zum Sonntag'
    WHEN `sender_guid` BETWEEN 900111 AND 900115 THEN 'Kessel und Klinge'
    WHEN `sender_guid` BETWEEN 900116 AND 900120 THEN 'Rend oder Raus'
    WHEN `sender_guid` BETWEEN 900121 AND 900141 THEN 'Horde Feierabend'
    ELSE 'Nostalgia'
END;

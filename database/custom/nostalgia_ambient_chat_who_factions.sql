-- Nostalgia: expands the Horde fake-player pool to 50 entries for the faction-aware /who list.
-- Safe to import repeatedly: only this sender GUID range is refreshed.
DELETE FROM `nostalgia_ambient_chat` WHERE `sender_guid` BETWEEN 900121 AND 900141;

INSERT INTO `nostalgia_ambient_chat`
    (`zone_id`, `channel_name`, `sender_guid`, `sender_name`, `race`, `gender`, `class`, `level`, `guild_name`, `message`, `enabled`)
VALUES
    (14,   'General', 900121, 'Schnetzler',  2, 0, 1, 60, 'Horde Feierabend', 'lfm rfc noch heal dann los', 1),
    (85,   'General', 900122, 'Gruftmama',   5, 1, 5, 60, 'Horde Feierabend', 'wer macht tirisfal quests mit?', 1),
    (215,  'General', 900123, 'Totemtrude',  6, 1, 7, 60, 'Horde Feierabend', 'wailing caverns 10er suche noch 3', 1),
    (17,   'General', 900124, 'Raptorzahn',  8, 0, 3, 60, 'Horde Feierabend', 'need gruppe fuer wc bin hunter', 1),
    (1637, 'General', 900125, 'Mokkabohne',  2, 1, 8, 60, 'Horde Feierabend', 'orgrimmar portal pls? ach ja vanilla xD', 1),
    (130,  'General', 900126, 'Seuchenzahn', 5, 0, 4, 60, 'Horde Feierabend', 'sfk 10er lfm tank und heal', 1),
    (215,  'General', 900127, 'Hufstampfer', 6, 0, 1, 60, 'Horde Feierabend', 'bin tank fuer rfk einfach inv', 1),
    (331,  'General', 900128, 'Trolltoast',  8, 1, 5, 60, 'Horde Feierabend', 'bfd quest run wer kommt mit?', 1),
    (14,   'General', 900129, 'Kriegsgurke', 2, 0, 9, 60, 'Horde Feierabend', 'lfm rfk 10er need 2 dd', 1),
    (85,   'General', 900130, 'Knochenbart', 5, 0, 1, 60, 'Horde Feierabend', 'strat 10er suche noch 1 heal', 1),
    (400,  'General', 900131, 'Wasserkuh',   6, 1, 11, 60, 'Horde Feierabend', 'feralas noch wer auf hippogreif quests?', 1),
    (331,  'General', 900132, 'Voodoomaus',  8, 1, 8, 60, 'Horde Feierabend', 'zulfarrak 10er lfm bitte keine leaver', 1),
    (14,   'General', 900133, 'Axtkeks',     2, 0, 4, 60, 'Horde Feierabend', 'brd 10er nur emperor und quests', 1),
    (85,   'General', 900134, 'Grufthexe',   5, 1, 9, 60, 'Horde Feierabend', 'scholo 10er summon steht', 1),
    (215,  'General', 900135, 'Donnerhuf',   6, 0, 7, 60, 'Horde Feierabend', 'lbrs 10er suche gruppe', 1),
    (17,   'General', 900136, 'Speerfisch',  8, 0, 3, 60, 'Horde Feierabend', 'ubrs 10er noch 2 dann rend', 1),
    (14,   'General', 900137, 'Zornbolzen',  2, 0, 1, 60, 'Horde Feierabend', 'mc pre quests wer braucht noch?', 1),
    (85,   'General', 900138, 'Modermaus',   5, 1, 5, 60, 'Horde Feierabend', 'heal fuer strat oder scholo da', 1),
    (400,  'General', 900139, 'Mondsichel',  6, 1, 3, 60, 'Horde Feierabend', 'maraudon 10er princess run?', 1),
    (331,  'General', 900140, 'Hexhex',      8, 1, 7, 60, 'Horde Feierabend', 'bwl attunement helfe gern', 1),
    (1637, 'General', 900141, 'Blutbrot',    2, 0, 9, 60, 'Horde Feierabend', 'naxx attunement noch jemand?', 1);

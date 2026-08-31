-- Vergib dem 'admin' Account das maximale GM-Level (3 für Administrator)
-- Dies stellt sicher, dass der Account alle Rechte auf dem Server hat.

-- Falls die Spalte 'gmlevel' direkt in der account Tabelle existiert:
UPDATE account SET gmlevel = 3 WHERE username = 'ADMIN';

-- Falls die Tabelle 'account_access' existiert (Standard in vielen MaNGOS-Derivaten):
REPLACE INTO account_access (id, gmlevel, RealmID)
SELECT id, 3, -1 FROM account WHERE username = 'ADMIN';

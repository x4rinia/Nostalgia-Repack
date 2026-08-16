-- Nostalgia client compatibility:
-- Replace German umlauts in the German locale (_loc3) with ASCII spellings.
-- This also repairs the legacy double-encoded variants such as "SÃ¤uberung".
-- A full backup of the affected locale tables is created before this script is applied.

DROP PROCEDURE IF EXISTS `NostalgiaAsciiGermanLocales`;

DELIMITER //
CREATE PROCEDURE `NostalgiaAsciiGermanLocales`()
BEGIN
    DECLARE finished TINYINT DEFAULT 0;
    DECLARE locale_table VARCHAR(64);
    DECLARE locale_column VARCHAR(64);
    DECLARE locale_cursor CURSOR FOR
        SELECT `TABLE_NAME`, `COLUMN_NAME`
        FROM `information_schema`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE()
          AND `TABLE_NAME` LIKE 'locales\\_%'
          AND `COLUMN_NAME` LIKE '%\\_loc3'
          AND `DATA_TYPE` IN ('char', 'varchar', 'tinytext', 'text', 'mediumtext', 'longtext');
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = 1;

    OPEN locale_cursor;
    replace_loop: LOOP
        FETCH locale_cursor INTO locale_table, locale_column;
        IF finished = 1 THEN
            LEAVE replace_loop;
        END IF;

        SET @ascii_value = CONCAT(
            'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(',
            'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(`', locale_column, '`, ',
            'CONVERT(0xC383C284 USING utf8mb3), ''Ae''), ',
            'CONVERT(0xC383C296 USING utf8mb3), ''Oe''), ',
            'CONVERT(0xC383C29C USING utf8mb3), ''Ue''), ',
            'CONVERT(0xC383C2A4 USING utf8mb3), ''ae''), ',
            'CONVERT(0xC383C2B6 USING utf8mb3), ''oe''), ',
            'CONVERT(0xC383C2BC USING utf8mb3), ''ue''), ',
            'CONVERT(0xC383C29F USING utf8mb3), ''ss''), ',
            'CONVERT(0xC383C5B8 USING utf8mb3), ''ss''), ',
            'CONVERT(0xC384 USING utf8mb3), ''Ae''), ',
            'CONVERT(0xC396 USING utf8mb3), ''Oe''), ',
            'CONVERT(0xC39C USING utf8mb3), ''Ue''), ',
            'CONVERT(0xC3A4 USING utf8mb3), ''ae''), ',
            'CONVERT(0xC3B6 USING utf8mb3), ''oe''), ',
            'CONVERT(0xC3BC USING utf8mb3), ''ue''), ',
            'CONVERT(0xC39F USING utf8mb3), ''ss'')'
        );

        SET @nostalgia_sql = CONCAT(
            'UPDATE `', locale_table, '` SET `', locale_column, '` = ', @ascii_value
        );
        PREPARE nostalgia_statement FROM @nostalgia_sql;
        EXECUTE nostalgia_statement;
        DEALLOCATE PREPARE nostalgia_statement;
    END LOOP;
    CLOSE locale_cursor;
END//
DELIMITER ;

CALL `NostalgiaAsciiGermanLocales`();
DROP PROCEDURE `NostalgiaAsciiGermanLocales`;

-- ============================================================
-- Vider toutes les tables du schema Oracle courant
-- Compatible Oracle 11g+
--
-- ATTENTION : operation destructive et irreversible (TRUNCATE).
-- Faites une sauvegarde et verifiez le schema/connecte avant execution.
-- Ce script agit sur TOUTES les tables visibles dans USER_TABLES
-- du schema actuellement connecte.
-- ============================================================

SET SERVEROUTPUT ON;

DECLARE
BEGIN
    -- 1. Desactiver les contraintes de cle etrangere pour autoriser
    --    le TRUNCATE des tables parentes et enfants.
    FOR c IN (
        SELECT table_name, constraint_name
        FROM user_constraints
        WHERE constraint_type = 'R'
    ) LOOP
        EXECUTE IMMEDIATE
            'ALTER TABLE "' || REPLACE(c.table_name, '"', '""') ||
            '" DISABLE CONSTRAINT "' ||
            REPLACE(c.constraint_name, '"', '""') || '"';
    END LOOP;

    -- 2. Tronquer toutes les tables du schema courant.
    FOR t IN (
        SELECT table_name
        FROM user_tables
        ORDER BY table_name
    ) LOOP
        EXECUTE IMMEDIATE
            'TRUNCATE TABLE "' || REPLACE(t.table_name, '"', '""') || '"';

        DBMS_OUTPUT.PUT_LINE('Table tronquee : ' || t.table_name);
    END LOOP;

    -- 3. Reactiver les contraintes de cle etrangere.
    FOR c IN (
        SELECT table_name, constraint_name
        FROM user_constraints
        WHERE constraint_type = 'R'
    ) LOOP
        EXECUTE IMMEDIATE
            'ALTER TABLE "' || REPLACE(c.table_name, '"', '""') ||
            '" ENABLE CONSTRAINT "' ||
            REPLACE(c.constraint_name, '"', '""') || '"';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Termine : toutes les tables du schema courant ont ete videes.');
END;
/

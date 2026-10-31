-- =====================================================================
-- MobiPass - Magasin LOCATION_MD1 - SUPPRESSION de la structure
-- Supprime tout ce que 01_Location_MD_structure.sql a cree :
--   * 3 dimensions Oracle : TEMPS_DIM1, EXEMPLAIRE_DIM1, EMPLOYE_DIM1
--   * 4 vues materialisees : LOCATION_MD1 (fait), TEMPS_MD1,
--     EXEMPLAIRE_MD1, EMPLOYE_MD1 (dimensions)
--   * (avec les MV) leurs tables, cles primaires, cles etrangeres et CHECK
--   * LOCATION_MD2 (ancienne version de test, si elle existe)
--
-- Re-executable : ne plante pas si un objet n'existe pas / plus.
-- Ordre : dimensions -> fait -> dimensions du magasin (a cause des FK).
-- =====================================================================
SET SERVEROUTPUT ON

DECLARE
  PROCEDURE drop_dimension(p_nom VARCHAR2) IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM USER_DIMENSIONS WHERE DIMENSION_NAME = UPPER(p_nom);
    IF n > 0 THEN
      EXECUTE IMMEDIATE 'DROP DIMENSION ' || p_nom;
      DBMS_OUTPUT.PUT_LINE('Dimension supprimee : ' || p_nom);
    ELSE
      DBMS_OUTPUT.PUT_LINE('Dimension absente   : ' || p_nom);
    END IF;
  END;

  PROCEDURE drop_mview(p_nom VARCHAR2) IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM USER_MVIEWS WHERE MVIEW_NAME = UPPER(p_nom);
    IF n > 0 THEN
      EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || p_nom;
      DBMS_OUTPUT.PUT_LINE('MV supprimee        : ' || p_nom);
    ELSE
      DBMS_OUTPUT.PUT_LINE('MV absente          : ' || p_nom);
    END IF;
  END;
BEGIN
  -- 1) Dimensions Oracle (elles referencent les MV de dimensions)
  drop_dimension('TEMPS_DIM1');
  drop_dimension('EXEMPLAIRE_DIM1');
  drop_dimension('EMPLOYE_DIM1');

  -- 2) Fait en premier : sa suppression retire aussi ses cles etrangeres
  drop_mview('LOCATION_MD1');
  drop_mview('LOCATION_MD2');   -- ancienne version de test

  -- 3) Dimensions du magasin (plus aucune FK ne les reference)
  drop_mview('TEMPS_MD1');
  drop_mview('EXEMPLAIRE_MD1');
  drop_mview('EMPLOYE_MD1');
END;
/

-- Verification : doit ne rien renvoyer
SELECT MVIEW_NAME AS objet_restant FROM USER_MVIEWS
 WHERE MVIEW_NAME IN ('TEMPS_MD1','EXEMPLAIRE_MD1','EMPLOYE_MD1','LOCATION_MD1','LOCATION_MD2')
UNION ALL
SELECT DIMENSION_NAME FROM USER_DIMENSIONS
 WHERE DIMENSION_NAME IN ('TEMPS_DIM1','EXEMPLAIRE_DIM1','EMPLOYE_DIM1');

-- Optionnel : table d'exceptions creee par utldim.sql pour VALIDATE_DIMENSION
-- DROP TABLE DIMENSION_EXCEPTIONS PURGE;

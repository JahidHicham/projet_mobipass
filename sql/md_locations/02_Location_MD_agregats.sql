-- =====================================================================
-- MobiPass - Magasin LOCATION_MD - 02 AGREGATS (treillis partiel)
-- A lancer APRES 01_Location_MD_structure.sql (lit LOCATION_MD, TEMPS_MD, EMPLOYE_MD).
-- Methode du cours : vues materialisees d'agregats, interrogees directement.
-- =====================================================================


-- =====================================================================
-- 5) AGREGATS - treillis partiel (analyses a, b, c du sujet)
--
--        (CodeE, CodeEX, DateJ)  = LOCATION_MD (donnees detaillees)
--          |                \
--   AGG_MOIS_SOC             AGG_SEM_EMP
--   (Mois, Societe)          (Semaine, Employe)
--          |
--   AGG_MOIS_REG
--   (Mois, Region)
--
--  a) montant paye / mois / societe   -> AGG_MOIS_SOC
--  b) montant paye + duree / semaine / employe -> AGG_SEM_EMP
--  c) duree / mois / region           -> AGG_MOIS_REG (calcule depuis AGG_MOIS_SOC,
--                                        comme Agg2 est calcule depuis Agg1 dans le cours)
-- =====================================================================
CREATE MATERIALIZED VIEW AGG_MOIS_SOC
BUILD IMMEDIATE REFRESH COMPLETE ON DEMAND
AS SELECT t.Num_Mois,
          e.CodeSOC, e.NomSOC,
          e.CodeReg, e.NomReg, e.CodePays,      -- societe determine region et pays
          SUM(f.MontantReelP_MD) AS MontantPaye_Mois,
          SUM(f.Duree_MD)        AS Duree_Mois
   FROM   LOCATION_MD f, TEMPS_MD t, EMPLOYE_MD e
   WHERE  f.DateJ = t.DateJ
   AND    f.CodeE = e.CodeE
   GROUP BY t.Num_Mois, e.CodeSOC, e.NomSOC, e.CodeReg, e.NomReg, e.CodePays;

CREATE MATERIALIZED VIEW AGG_MOIS_REG
BUILD IMMEDIATE REFRESH COMPLETE ON DEMAND
AS SELECT Num_Mois, CodeReg, NomReg,
          SUM(Duree_Mois) AS Duree_Mois_Reg
   FROM   AGG_MOIS_SOC
   GROUP BY Num_Mois, CodeReg, NomReg;

CREATE MATERIALIZED VIEW AGG_SEM_EMP
BUILD IMMEDIATE REFRESH COMPLETE ON DEMAND
AS SELECT t.Num_Semaine,
          e.CodeE, e.NomE, e.PrenomE,
          SUM(f.MontantReelP_MD) AS MontantPaye_Sem,
          SUM(f.Duree_MD)        AS Duree_Sem
   FROM   LOCATION_MD f, TEMPS_MD t, EMPLOYE_MD e
   WHERE  f.DateJ = t.DateJ
   AND    f.CodeE = e.CodeE
   GROUP BY t.Num_Semaine, e.CodeE, e.NomE, e.PrenomE;

-- Requetes d'analyse (lecture directe des agregats, comme dans le cours)
-- a) SELECT Num_Mois, NomSOC, MontantPaye_Mois FROM AGG_MOIS_SOC;
-- b) SELECT Num_Semaine, NomE, PrenomE, MontantPaye_Sem, Duree_Sem FROM AGG_SEM_EMP;
-- c) SELECT Num_Mois, NomReg, Duree_Mois_Reg FROM AGG_MOIS_REG;

-- =====================================================================
-- RAFRAICHISSEMENT DES AGREGATS (apres celui de la structure ; ordre : AGG_MOIS_SOC avant AGG_MOIS_REG)
-- =====================================================================
BEGIN
  DBMS_MVIEW.REFRESH('AGG_MOIS_SOC', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_MOIS_REG', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_SEM_EMP',  method => 'C', atomic_refresh => TRUE);
END;
/

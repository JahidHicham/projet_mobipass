-- =====================================================================
-- MobiPass - Magasin LOCATION_MD1 - 02 AGREGATS (treillis partiel)
-- A lancer APRES 01_Location_MD_structure.sql
-- (lit LOCATION_MD1, TEMPS_MD1 et EMPLOYE_MD1).
--
-- Methode du cours : vues materialisees d'agregats interrogees directement ;
-- un agregat peut etre calcule depuis un autre (Agg2 depuis Agg1 dans le cours).
--
--      (CodeEmploye, CodeExemplaire, DateJ)  =  LOCATION_MD1  (donnees detaillees)
--                              |
--                     AGG_SEM_EMPLOYE_MD1  (Num_Semaine, Num_Mois, CodeEmploye)   Agg1
--                      /                  \
--     AGG_MOIS_SOCIETE_MD1          AGG_MOIS_REGION_MD1
--     (Num_Mois, CodeSociete)       (Num_Mois, CodeRegion, CodeLand)                        Agg2, Agg3
--
--  a) montant paye par mois et par societe   -> AGG_MOIS_SOCIETE_MD1
--  b) montant paye et duree par semaine et par employe -> AGG_SEM_EMPLOYE_MD1
--  c) duree par mois et par region (France) / Land (Allemagne) -> AGG_MOIS_REGION_MD1
--  Montants en TTC (cf. dictionnaire de mesures).
-- =====================================================================

-- Agg1 : (Semaine, Mois, Employe) - porte societe, type, region et pays pour alimenter Agg2 et Agg3
CREATE MATERIALIZED VIEW AGG_SEM_EMPLOYE_MD1
BUILD IMMEDIATE 
REFRESH COMPLETE ON DEMAND
AS SELECT 
          -- Analyse A (et alimentation de Agg2)
          t.Num_Mois,
          e.CodeSociete, e.NomSociete, e.CodeTy, e.LibelleTypeSoc,

          -- Analyse B
          t.Num_Semaine,
          e.CodeEmploye, e.NomEmploye, e.PrenomEmploye,

          -- Analyse C
          e.CodeRegion, e.NomRegion, e.CodeLand, e.NomLand, e.CodePays, e.NomPays,

          SUM(l.Montant_Location_ReelPaye_MD) AS MontantPaye_Semaine,
          SUM(l.Duree_Location_MD)            AS Duree_Semaine
   FROM   LOCATION_MD1 l, TEMPS_MD1 t, EMPLOYE_MD1 e
   WHERE  l.DateJ        = t.DateJ
   AND    l.CodeEmploye  = e.CodeEmploye
   GROUP BY t.Num_Mois,
          e.CodeSociete, e.NomSociete, e.CodeTy, e.LibelleTypeSoc,
          t.Num_Semaine, e.CodeEmploye, e.NomEmploye, e.PrenomEmploye, 
          e.CodeRegion, e.NomRegion, e.CodeLand, e.NomLand, e.CodePays, e.NomPays;

-- Agg2 : (Mois, Societe) calcule depuis Agg1
CREATE MATERIALIZED VIEW AGG_MOIS_SOCIETE_MD1
BUILD IMMEDIATE 
REFRESH COMPLETE ON DEMAND
AS SELECT Num_Mois,
          CodeSociete, NomSociete, CodeTy, LibelleTypeSoc,
          SUM(MontantPaye_Semaine) AS MontantPaye_Mois
   FROM   AGG_SEM_EMPLOYE_MD1
   GROUP BY Num_Mois,
          CodeSociete, NomSociete, CodeTy, LibelleTypeSoc;

-- Agg3 : (Mois, Region) calcule depuis Agg1
CREATE MATERIALIZED VIEW AGG_MOIS_REGION_MD1
BUILD IMMEDIATE 
REFRESH COMPLETE ON DEMAND
AS SELECT Num_Mois, CodeRegion, NomRegion, CodeLand, NomLand, CodePays, NomPays,
          SUM(Duree_Semaine) AS Duree_Mois_Region
   FROM   AGG_SEM_EMPLOYE_MD1
   GROUP BY Num_Mois, CodeRegion, NomRegion, CodeLand, NomLand, CodePays, NomPays;



-- Requetes d'analyse :

-- a) SELECT Num_Mois, CodeSociete, NomSociete, CodeTy, LibelleTypeSoc, MontantPaye_Mois FROM   AGG_MOIS_SOCIETE_MD1

-- b) SELECT Num_Semaine, CodeEmploye, NomEmploye, PrenomEmploye, MontantPaye_Semaine, Duree_Semaine FROM AGG_SEM_EMPLOYE_MD1

-- c) SELECT Num_Mois, CodeRegion, NomRegion, CodeLand, NomLand, CodePays, NomPays, Duree_Mois_Region FROM   AGG_MOIS_REGION_MD1;


-- =====================================================================
-- RAFRAICHISSEMENT DES AGREGATS
-- (apres celui de la structure ; AGG_SEM_EMPLOYE_MD1 (Agg1) AVANT les agregats qui en dependent)
-- =====================================================================
BEGIN
  DBMS_MVIEW.REFRESH('AGG_SEM_EMPLOYE_MD1',  method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_MOIS_SOCIETE_MD1', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_MOIS_REGION_MD1',  method => 'C', atomic_refresh => TRUE);
END;
/

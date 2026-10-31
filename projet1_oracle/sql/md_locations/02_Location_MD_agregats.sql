-- =====================================================================
-- MobiPass - Magasin LOCATION_MD1 - 02 AGREGATS (treillis partiel)
-- A lancer APRES 01_Location_MD_structure.sql
-- (lit LOCATION_MD1, TEMPS_MD1 et EMPLOYE_MD1).
--
-- Methode du cours : vues materialisees d'agregats interrogees directement ;
-- un agregat peut etre calcule depuis un autre (Agg2 depuis Agg1 dans le cours).
--
-- La semaine et le mois sont dans deux hierarchies distinctes (H_SEM et H_MOIS) :
-- une semaine ISO peut chevaucher deux mois, donc l'agregat mensuel ne peut pas
-- etre calcule depuis l'agregat hebdomadaire. Agg1 et Agg2 sont donc tous deux
-- calcules depuis LOCATION_MD1 ; seul Agg3 est calcule depuis un autre agregat (Agg2).
--
--      (CodeEmploye, CodeExemplaire, DateJ)  =  LOCATION_MD1  (donnees detaillees)
--                      /                              \
--     AGG_SEM_EMPLOYE_MD1                    AGG_MOIS_SOCIETE_MD1
--     (Num_Semaine, CodeEmploye)             (Num_Mois, CodeSociete)
--     Agg1                                   Agg2
--                                                     |
--                                            AGG_MOIS_REGION_MD1
--                                            (Num_Mois, CodeRegLand)
--                                            Agg3
--
--  a) montant paye par mois et par societe   -> AGG_MOIS_SOCIETE_MD1
--  b) montant paye et duree par semaine et par employe -> AGG_SEM_EMPLOYE_MD1
--  c) duree par mois et par region (France) / Land (Allemagne) -> AGG_MOIS_REGION_MD1
--  Montants en TTC (cf. dictionnaire de mesures).
-- =====================================================================

-- Agg1 : (Semaine, Employe) calcule depuis LOCATION_MD1 - sert l'analyse b
CREATE MATERIALIZED VIEW AGG_SEM_EMPLOYE_MD1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT

          -- Analyse B
          t.Num_Semaine,
          e.CodeEmploye, e.NomEmploye, e.PrenomEmploye,


          SUM(l.Montant_Location_ReelPaye_MD) AS MontantPaye_Semaine,
          SUM(l.Duree_Location_MD)            AS Duree_Semaine
   FROM   LOCATION_MD1 l, TEMPS_MD1 t, EMPLOYE_MD1 e
   WHERE  l.DateJ        = t.DateJ
   AND    l.CodeEmploye  = e.CodeEmploye
   GROUP BY
          t.Num_Semaine, e.CodeEmploye, e.NomEmploye, e.PrenomEmploye;

-- Agg2 : (Mois, Societe) calcule depuis LOCATION_MD1 - sert l'analyse a
--        et porte type de societe, pays et region/Land (determines par la societe)
--        pour alimenter Agg3
CREATE MATERIALIZED VIEW AGG_MOIS_SOCIETE_MD1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT
          -- Analyse A (et alimentation de Agg3)
          t.Num_Mois,
          e.CodeSociete, e.NomSociete, e.CodeTy, e.LibelleTypeSoc,

          -- Analyse C
          e.CodePays, e.NomPays, COALESCE(e.CodeRegion, e.CodeLand) AS CodeRegLand, COALESCE(e.NomRegion, e.NomLand) NomRegLand,

          SUM(l.Montant_Location_ReelPaye_MD) AS MontantPaye_Mensuel,
          SUM(l.Duree_Location_MD)            AS Duree_Mensuel

   FROM   LOCATION_MD1 l, TEMPS_MD1 t, EMPLOYE_MD1 e
   WHERE  l.DateJ        = t.DateJ
   AND    l.CodeEmploye  = e.CodeEmploye
   GROUP BY Num_Mois, CodeSociete, NomSociete, CodeTy, LibelleTypeSoc, e.CodePays, e.NomPays, e.CodeRegion, e.CodeLand, e.NomRegion, e.NomLand;

-- Agg3 : (Mois, Region/Land) calcule depuis Agg2 - sert l'analyse c
CREATE MATERIALIZED VIEW AGG_MOIS_REGION_MD1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT Num_Mois, CodePays, NomPays, CodeRegLand, NomRegLand,
          SUM(Duree_Mensuel) AS Duree_Mensuel_Region
   FROM   AGG_MOIS_SOCIETE_MD1
   GROUP BY Num_Mois, CodePays, NomPays, CodeRegLand, NomRegLand;



-- Requetes d'analyse :

-- a) SELECT Num_Mois, CodeSociete, NomSociete, CodeTy, LibelleTypeSoc, MontantPaye_Mensuel FROM AGG_MOIS_SOCIETE_MD1;

-- b) SELECT Num_Semaine, CodeEmploye, NomEmploye, PrenomEmploye, MontantPaye_Semaine, Duree_Semaine FROM AGG_SEM_EMPLOYE_MD1;

-- c) SELECT Num_Mois, CodeRegLand, NomRegLand, CodePays, NomPays, Duree_Mensuel_Region FROM AGG_MOIS_REGION_MD1;
--    (CodeRegLand / NomRegLand = region pour la France, Land pour l'Allemagne)


-- =====================================================================
-- RAFRAICHISSEMENT DES AGREGATS
-- (apres celui de la structure ; AGG_MOIS_SOCIETE_MD1 (Agg2) AVANT AGG_MOIS_REGION_MD1 (Agg3) qui en depend)
-- =====================================================================
BEGIN
  DBMS_MVIEW.REFRESH('AGG_SEM_EMPLOYE_MD1',  method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_MOIS_SOCIETE_MD1', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('AGG_MOIS_REGION_MD1',  method => 'C', atomic_refresh => TRUE);
END;
/

-- =====================================================================
-- MobiPass - Magasin ACHAT_MD2 (ventes) - 02 AGREGATS (treillis partiel)
-- A lancer apres 05_MD2_Ventes_structure.sql.
-- Noeuds notes (Produit, Employe, Metier, Temps) ; chaque agregat garde CodePays
-- pour la securite par pays des deux responsables des ventes.
--
--                         (All, All, All, All)
--                        /                    \
--     (All, CodePays, All, Num_Mois)  B2.1      \
--               |                                \
--     (CodeGamme, CodeRegion/CodeLand,            (All, CodeTy x CodeCJ2, All, Trimestre)  B2.3
--      All, Num_Mois)  B2.2                      /
--                        \                      /
--          (CodeProduit, CodeEmploye, CodeAppellation, DateJ) = ACHAT_MD2
--
-- Les analyses libres B2.4 portent sur les donnees detaillees.
-- =====================================================================

ALTER SESSION SET QUERY_REWRITE_ENABLED   = TRUE;
ALTER SESSION SET QUERY_REWRITE_INTEGRITY = TRUSTED;   -- les DIMENSION ne sont pas verifiees par Oracle


-- B2.2 : classement des gammes par montant reellement paye, par region (FR) ou Land (DE) et par mois
CREATE MATERIALIZED VIEW MV_ACH_GAM_REG_MOIS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
ENABLE QUERY REWRITE
AS SELECT p.CodeGamme, p.NomGamme, p.SecteurProduit,
          e.CodeRegion, e.NomRegion, e.CodeLand, e.NomLand, e.CodePays, e.NomPays,
          t.Num_Mois, t.LibMois, t.Annee,
          SUM(f.Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(f.Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(f.Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,
          SUM(f.Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM   ACHAT_MD2 f, PRODUIT_MD2 p, EMPLOYE_MD2 e, TEMPS_MD2 t
   WHERE  f.CodeProduit = p.CodeProduit
   AND    f.CodeEmploye = e.CodeEmploye
   AND    f.DateJ       = t.DateJ
   GROUP BY p.CodeGamme, p.NomGamme, p.SecteurProduit,
            e.CodeRegion, e.NomRegion, e.CodeLand, e.NomLand, e.CodePays, e.NomPays,
            t.Num_Mois, t.LibMois, t.Annee;

-- B2.1 : tableau de bord mensuel par pays (quantites, montant paye, benefice, comparaison a l'annee precedente)
--        construit a partir de MV_ACH_GAM_REG_MOIS (noeud plus detaille du meme chemin du treillis)
CREATE MATERIALIZED VIEW MV_ACH_PAYS_MOIS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT CodePays, NomPays, Num_Mois, LibMois, Annee,
          SUM(Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,
          SUM(Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM   MV_ACH_GAM_REG_MOIS
   GROUP BY CodePays, NomPays, Num_Mois, LibMois, Annee;

-- B2.3 : ventes par type de societe et categorie juridique (niveau 2), par trimestre
CREATE MATERIALIZED VIEW MV_ACH_TYPE_CJ_TRIM
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
ENABLE QUERY REWRITE
AS SELECT e.CodeTy, e.LibelleTypeSoc, e.CodeCJ2, e.LibelleCJ2, e.CodePays, e.NomPays,
          t.Trimestre, t.Annee,
          SUM(f.Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(f.Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(f.Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,
          SUM(f.Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM   ACHAT_MD2 f, EMPLOYE_MD2 e, TEMPS_MD2 t
   WHERE  f.CodeEmploye = e.CodeEmploye
   AND    f.DateJ       = t.DateJ
   GROUP BY e.CodeTy, e.LibelleTypeSoc, e.CodeCJ2, e.LibelleCJ2, e.CodePays, e.NomPays,
            t.Trimestre, t.Annee;


-- =====================================================================
-- RAFRAICHISSEMENT (apres celui de la structure ; MV_ACH_PAYS_MOIS apres MV_ACH_GAM_REG_MOIS)
-- =====================================================================
BEGIN
  DBMS_MVIEW.REFRESH('MV_ACH_GAM_REG_MOIS', method => 'C');
  DBMS_MVIEW.REFRESH('MV_ACH_PAYS_MOIS',    method => 'C');
  DBMS_MVIEW.REFRESH('MV_ACH_TYPE_CJ_TRIM', method => 'C');
END;
/


-- =====================================================================
-- EXEMPLES DE REQUETES (reecrites sur les agregats ; verifier avec EXPLAIN PLAN :
-- "MAT_VIEW REWRITE ACCESS" doit apparaitre)
-- =====================================================================
-- B2.2 : top des gammes par region ou Land sur l'annee 2026
-- SELECT NomPays, NVL(NomRegion, NomLand) AS RegionOuLand, NomGamme,
--        SUM(Montant_Achat_ReelPaye_TTC_MD) AS MontantPaye
-- FROM   MV_ACH_GAM_REG_MOIS
-- WHERE  Annee = 2026
-- GROUP BY NomPays, NVL(NomRegion, NomLand), NomGamme
-- ORDER BY NomPays, RegionOuLand, MontantPaye DESC;

-- B2.1 : comparaison mensuelle a l'annee precedente (France)
-- SELECT a.Num_Mois, a.Montant_Achat_ReelPaye_TTC_MD AS MontantAnnee,
--        b.Montant_Achat_ReelPaye_TTC_MD AS MontantAnneePrec
-- FROM   MV_ACH_PAYS_MOIS a
--        LEFT JOIN MV_ACH_PAYS_MOIS b
--               ON b.CodePays = a.CodePays
--              AND b.Num_Mois = TO_CHAR(ADD_MONTHS(TO_DATE(a.Num_Mois, 'YYYY-MM'), -12), 'YYYY-MM')
-- WHERE  a.CodePays = 'FR'
-- ORDER BY a.Num_Mois;

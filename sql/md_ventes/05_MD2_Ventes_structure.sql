-- =====================================================================
-- MobiPass - Magasin ACHAT_MD2 (ventes, R-OLAP denormalise) - 01 STRUCTURE
-- Dimensions TEMPS_MD2, PRODUIT_MD2, METIER_MD2, EMPLOYE_MD2 + fait ACHAT_MD2
--
-- Meme demarche et memes conventions que LOCATION_MD1 (01_Location_MD_structure.sql) :
--   dimension : CREATE MATERIALIZED VIEW -> ALTER TABLE ... PRIMARY KEY
--               -> CREATE DIMENSION (niveaux, hierarchies, attributs faibles)
--   fait      : CREATE MATERIALIZED VIEW -> PRIMARY KEY -> FOREIGN KEY -> NOT NULL
--
-- Source : tables de l'ED (01_creation_ED.sql : noms SANS suffixe _DW).
-- Les agregats sont dans 06_MD2_Ventes_agregats.sql.
--
-- Ecarts volontaires entre schema en etoile et Oracle :
--   * niveau "Date" -> colonne DateJ (DATE est un mot reserve Oracle)
--   * TypeKreis / TypeLand : comme EMPLOYE_MD1 (TypeKreis = NiveauZG du Kreis,
--     TypeLand calcule : 'Stadtstaat' pour Berlin, Hamburg, Bremen, 'Flächenland' sinon)
--
-- Regles de calcul des mesures :
--   * prix publics ramenes en HT (tarifs FR en TTC divises par 1 + TauxTVA) ;
--     montant reellement paye fourni en HT et en TTC (meme convention TTC que Location_MD) ;
--     benefice en HT (la TVA est reversee a l'Etat)
--   * tarif : pays de la societe de l'employe, valable a la date d'achat
--   * reduction : (categorie de l'employe, gamme du produit, annee d'achat) ;
--     aucun achat ne se fait au prix public (PctReduc_Achat > 0) : un achat sans tarif
--     ou sans reduction n'est pas charge et est signale par les controles
--   * metier : celui exerce a la date d'achat (historique des metiers, sujet p. 5) ;
--     'NR' (non renseigne) s'il n'y en a pas (salaries allemands : le ROME est francais, RG9)
-- =====================================================================


-- =====================================================================
-- 0) SUPPRESSION (relance du script)
-- =====================================================================
BEGIN
  FOR d IN (SELECT dimension_name FROM user_dimensions
            WHERE dimension_name IN ('TEMPS_DIM2','PRODUIT_DIM2','METIER_DIM2','EMPLOYE_DIM2')) LOOP
    EXECUTE IMMEDIATE 'DROP DIMENSION ' || d.dimension_name;
  END LOOP;
  FOR v IN (SELECT mview_name FROM user_mviews
            WHERE mview_name IN ('MV_ACH_PAYS_MOIS','MV_ACH_GAM_REG_MOIS','MV_ACH_TYPE_CJ_TRIM','ACHAT_MD2',
                                 'TEMPS_MD2','PRODUIT_MD2','METIER_MD2','EMPLOYE_MD2')
            ORDER BY DECODE(mview_name,'MV_ACH_PAYS_MOIS',1,'MV_ACH_GAM_REG_MOIS',2,'MV_ACH_TYPE_CJ_TRIM',3,'ACHAT_MD2',4,5)) LOOP
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || v.mview_name;
  END LOOP;
END;
/


-- =====================================================================
-- 1) DIMENSION TEMPS_MD2
--    H_MOIS : DateJ -> Num_Mois -> Trimestre -> Annee   (annee civile)
--    Le trimestre sert au rapport B2.3.
-- =====================================================================
CREATE MATERIALIZED VIEW TEMPS_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT DISTINCT DateA                                      AS DateJ,
                   TO_CHAR(DateA, 'YYYY-MM')                    AS Num_Mois,
                   TO_CHAR(DateA, 'fmMonth YYYY',
                           'NLS_DATE_LANGUAGE=FRENCH')          AS LibMois,
                   TO_CHAR(DateA, 'YYYY-"T"Q')                  AS Trimestre,
                   EXTRACT(YEAR FROM DateA)                     AS Annee
   FROM ACHAT;                                                  -- dates d'achat

ALTER TABLE TEMPS_MD2 ADD CONSTRAINT pk_temps_md2 PRIMARY KEY (DateJ);

CREATE DIMENSION TEMPS_DIM2
   LEVEL DateJ     IS (TEMPS_MD2.DateJ)
   LEVEL Num_Mois  IS (TEMPS_MD2.Num_Mois)
   LEVEL Trimestre IS (TEMPS_MD2.Trimestre)
   LEVEL Annee     IS (TEMPS_MD2.Annee)
HIERARCHY H_MOIS (DateJ CHILD OF Num_Mois CHILD OF Trimestre CHILD OF Annee)
ATTRIBUTE Num_Mois DETERMINES TEMPS_MD2.LibMois;


-- =====================================================================
-- 2) DIMENSION PRODUIT_MD2
--    H_GENERATION : CodeProduit -> CodeGeneration -> CodeFabricant -> PaysFabricant
--    H_STATUT     : CodeProduit -> CodeGeneration -> StatutGeneration
--    H_MAR        : CodeProduit -> MarqueProduit
--    H_GAMME      : CodeProduit -> CodeGamme -> SecteurProduit
--    H_AUTONOMIE  : CodeProduit -> ClasseAutonomie   (produits avec autonomie seulement)
-- =====================================================================
CREATE MATERIALIZED VIEW PRODUIT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT pr.CodeP           AS CodeProduit,
          pr.NomP            AS NomProduit,
          pr.DescriptifP     AS DescriptifProduit,
          pr.PoidsKg         AS PoidsKgProduit,
          pr.AutonomieKm     AS AutonomieKilometreProduit,
          pr.MarqueP         AS MarqueProduit,
          CASE WHEN pr.AutonomieKm IS NULL THEN NULL
               WHEN pr.AutonomieKm <= 30   THEN 'Jusqu''à 30 km'
               WHEN pr.AutonomieKm <= 70   THEN '31 à 70 km'
               ELSE 'Plus de 70 km' END      AS ClasseAutonomie,
          ge.CodeGEN         AS CodeGeneration,
          ge.NomGEN          AS NomGeneration,
          ge.DateSortieGEN   AS DateSortieGeneration,
          ge.DateArretGEN    AS DateArretGeneration,
          CASE WHEN ge.DateArretGEN IS NOT NULL AND ge.DateArretGEN <= SYSDATE
               THEN 'Arrêtée' ELSE 'Commercialisée' END AS StatutGeneration,
          fa.CodeFAB         AS CodeFabricant,
          fa.NomFAB          AS NomFabricant,
          fa.PaysFAB         AS PaysFabricant,
          ga.CodeG           AS CodeGamme,
          ga.NomG            AS NomGamme,
          ga.SecteurG        AS SecteurProduit
   FROM   PRODUIT    pr,
          GENERATION ge,
          FABRICANT  fa,
          GAMME      ga
   WHERE  pr.CodeGEN = ge.CodeGEN
   AND    ge.CodeFAB = fa.CodeFAB
   AND    pr.CodeG   = ga.CodeG;

ALTER TABLE PRODUIT_MD2 ADD CONSTRAINT pk_produit_md2 PRIMARY KEY (CodeProduit);

CREATE DIMENSION PRODUIT_DIM2
   LEVEL CodeProduit      IS (PRODUIT_MD2.CodeProduit)
   LEVEL CodeGeneration   IS (PRODUIT_MD2.CodeGeneration)
   LEVEL CodeFabricant    IS (PRODUIT_MD2.CodeFabricant)
   LEVEL PaysFabricant    IS (PRODUIT_MD2.PaysFabricant)
   LEVEL StatutGeneration IS (PRODUIT_MD2.StatutGeneration)
   LEVEL MarqueProduit    IS (PRODUIT_MD2.MarqueProduit)
   LEVEL CodeGamme        IS (PRODUIT_MD2.CodeGamme)
   LEVEL SecteurProduit   IS (PRODUIT_MD2.SecteurProduit)
   LEVEL ClasseAutonomie  IS (PRODUIT_MD2.ClasseAutonomie) SKIP WHEN NULL
HIERARCHY H_GENERATION (CodeProduit CHILD OF CodeGeneration CHILD OF CodeFabricant
                        CHILD OF PaysFabricant)
HIERARCHY H_STATUT    (CodeProduit CHILD OF CodeGeneration CHILD OF StatutGeneration)
HIERARCHY H_MAR       (CodeProduit CHILD OF MarqueProduit)
HIERARCHY H_GAMME     (CodeProduit CHILD OF CodeGamme CHILD OF SecteurProduit)
HIERARCHY H_AUTONOMIE (CodeProduit CHILD OF ClasseAutonomie)
ATTRIBUTE CodeProduit DETERMINES PRODUIT_MD2.NomProduit
ATTRIBUTE CodeProduit DETERMINES PRODUIT_MD2.DescriptifProduit
ATTRIBUTE CodeProduit DETERMINES PRODUIT_MD2.PoidsKgProduit
ATTRIBUTE CodeProduit DETERMINES PRODUIT_MD2.AutonomieKilometreProduit
ATTRIBUTE CodeGeneration DETERMINES PRODUIT_MD2.NomGeneration
ATTRIBUTE CodeGeneration DETERMINES PRODUIT_MD2.DateSortieGeneration
ATTRIBUTE CodeGeneration DETERMINES PRODUIT_MD2.DateArretGeneration
ATTRIBUTE CodeFabricant  DETERMINES PRODUIT_MD2.NomFabricant
ATTRIBUTE CodeGamme      DETERMINES PRODUIT_MD2.NomGamme;


-- =====================================================================
-- 3) DIMENSION METIER_MD2
--    H_ROME : CodeAppellation -> CodeROME -> CodeDomainePro -> CodeGrandDomaine
--    + un membre 'NR' (Non renseigne) pour les achats sans metier connu
--    (salaries allemands, employes sans fiche RH)
-- =====================================================================
CREATE MATERIALIZED VIEW METIER_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT ap.CodeAPP        AS CodeAppellation,
          ap.LibelleAPP     AS LibelleAppellation,
          fm.CodeROME       AS CodeROME,
          fm.LibelleMetier  AS LibelleMetier,
          dp.CodeDP         AS CodeDomainePro,
          dp.LibelleDP      AS LibelleDomainePro,
          gd.CodeGD         AS CodeGrandDomaine,
          gd.LibelleGD      AS LibelleGrandDomaine
   FROM   APPELLATION   ap,
          FICHE_METIER  fm,
          DOMAINE_PRO   dp,
          GRAND_DOMAINE gd
   WHERE  ap.CodeROME = fm.CodeROME
   AND    fm.CodeDP   = dp.CodeDP
   AND    dp.CodeGD   = gd.CodeGD
   UNION ALL
   SELECT 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné'
   FROM   dual;

ALTER TABLE METIER_MD2 ADD CONSTRAINT pk_metier_md2 PRIMARY KEY (CodeAppellation);

CREATE DIMENSION METIER_DIM2
   LEVEL CodeAppellation  IS (METIER_MD2.CodeAppellation)
   LEVEL CodeROME         IS (METIER_MD2.CodeROME)
   LEVEL CodeDomainePro   IS (METIER_MD2.CodeDomainePro)
   LEVEL CodeGrandDomaine IS (METIER_MD2.CodeGrandDomaine)
HIERARCHY H_ROME (CodeAppellation CHILD OF CodeROME CHILD OF CodeDomainePro
                  CHILD OF CodeGrandDomaine)
ATTRIBUTE CodeAppellation  DETERMINES METIER_MD2.LibelleAppellation
ATTRIBUTE CodeROME         DETERMINES METIER_MD2.LibelleMetier
ATTRIBUTE CodeDomainePro   DETERMINES METIER_MD2.LibelleDomainePro
ATTRIBUTE CodeGrandDomaine DETERMINES METIER_MD2.LibelleGrandDomaine;


-- =====================================================================
-- 4) DIMENSION EMPLOYE_MD2  (service / societe ACTUELS de l'employe, comme EMPLOYE_MD1)
--    H_France      : CodeEmploye -> CodeService -> CodeSociete -> CodeVille
--                    -> CodeDepartement -> CodeRegion -> CodePays
--    H_Allemagne   : CodeEmploye -> CodeService -> CodeSociete -> CodeGemeinde
--                    -> CodeKreis -> CodeLand -> CodePays
--    H_District    : ... -> CodeGemeinde -> CodeKreis -> CodeDistrict -> CodeLand -> CodePays
--    H_Type_Societe: CodeEmploye -> CodeService -> CodeSociete -> CodeTy
--    H_CJ          : CodeEmploye -> CodeService -> CodeSociete -> CodeCJ3 -> CodeCJ2 -> CodeCJ1
--    H_NAF         : CodeEmploye -> CodeService -> CodeSociete -> SousClasseNAF
--                    -> ClasseNAF -> GroupeNAF -> DivisionNAF          (vide en Allemagne)
--    H_Categorie   : CodeEmploye -> CodeCategorie -> SuperCategorie
--    H_Age         : CodeEmploye -> TrancheAge                          (vide sans fiche RH)
--  Geographie identique a EMPLOYE_MD1 : z0 = zone de la societe, z1 = parent de z0,
--  z2 = parent de z1, z3 = parent de z2 ; le niveau (NiveauZG) decide de la colonne ;
--  une chaine absente donne NULL (hierarchies incompletes, SKIP WHEN NULL).
--  CodeRegion = region francaise ; CodeLand = Land allemand.
--  Pas de ENABLE QUERY REWRITE sur cette vue : SYSDATE y est autorise (age actuel).
-- =====================================================================
CREATE MATERIALIZED VIEW EMPLOYE_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT e.CodeE                                 AS CodeEmploye,
          e.NomE                                  AS NomEmploye,
          e.PrenomE                               AS PrenomEmploye,
          se.CodeSE                               AS CodeService,
          se.NomSE                                AS NomService,
          so.CodeSOC                              AS CodeSociete,
          so.NomSOC                               AS NomSociete,
          ty.CodeTy                               AS CodeTy,
          ty.LibelleTypeSoc                       AS LibelleTypeSoc,
          ca.CodeCAT                              AS CodeCategorie,
          ca.NomCAT                               AS NomCategorie,
          ca.SuperCAT                             AS SuperCategorie,
          CASE WHEN rh.DateNaissSAL IS NULL THEN NULL
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 30 * 12 THEN 'Moins de 30 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 40 * 12 THEN '30 à 39 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 50 * 12 THEN '40 à 49 ans'
               ELSE '50 ans et plus' END          AS TrancheAge,
          c3.CodeCJ                               AS CodeCJ3,
          c3.LibelleCJ                            AS LibelleCJ3,
          c2.CodeCJ                               AS CodeCJ2,
          c2.LibelleCJ                            AS LibelleCJ2,
          c1.CodeCJ                               AS CodeCJ1,
          c1.LibelleCJ                            AS LibelleCJ1,
          d1.CodeDO                               AS SousClasseNAF,
          d1.NomDO                                AS LibelleNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 5 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 5 THEN d3.CodeDO END)  AS ClasseNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 4 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 4 THEN d3.CodeDO END,
                   CASE WHEN LENGTH(d4.CodeDO) = 4 THEN d4.CodeDO END)  AS GroupeNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 2 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 2 THEN d3.CodeDO END,
                   CASE WHEN LENGTH(d4.CodeDO) = 2 THEN d4.CodeDO END)  AS DivisionNAF,
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.CodeZG END AS CodeVille,
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.NomZG  END AS NomVille,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.CodeZG END AS CodeDepartement,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.NomZG  END AS NomDepartement,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.CodeZG END AS CodeGemeinde,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.NomZG  END AS NomGemeinde,
          CASE WHEN z1.NiveauZG IN ('LANDKREIS','KREISFREIE STADT') THEN z1.CodeZG END AS CodeKreis,
          CASE WHEN z1.NiveauZG IN ('LANDKREIS','KREISFREIE STADT') THEN z1.NomZG  END AS NomKreis,
          CASE z1.NiveauZG WHEN 'LANDKREIS' THEN 'Landkreis'
                           WHEN 'KREISFREIE STADT' THEN 'Kreisfreie Stadt' END AS TypeKreis,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.CodeZG END AS CodeDistrict,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.NomZG  END AS NomDistrict,
          CASE WHEN z2.NiveauZG = 'REGION'      THEN z2.CodeZG END AS CodeRegion,
          CASE WHEN z2.NiveauZG = 'REGION'      THEN z2.NomZG  END AS NomRegion,
          CASE WHEN z2.NiveauZG = 'LAND' THEN z2.CodeZG
               WHEN z3.NiveauZG = 'LAND' THEN z3.CodeZG END AS CodeLand,
          CASE WHEN z2.NiveauZG = 'LAND' THEN z2.NomZG
               WHEN z3.NiveauZG = 'LAND' THEN z3.NomZG END AS NomLand,
          CASE WHEN z2.NiveauZG = 'LAND' AND z2.CodeZG IN ('DE02','DE04','DE11') THEN 'Stadtstaat'
               WHEN z2.NiveauZG = 'LAND' OR z3.NiveauZG = 'LAND'                 THEN 'Flächenland' END AS TypeLand,
          pa.CodePays                             AS CodePays,
          pa.NomPays                              AS NomPays,
          pa.TauxTVA                              AS TauxTVA
   FROM   EMPLOYE e
          JOIN SERVICE      se ON se.CodeSE   = e.CodeSE
          JOIN SOCIETE      so ON so.CodeSOC  = se.CodeSOC
          JOIN CATEGORIE    ca ON ca.CodeCAT  = e.CodeCAT
          JOIN ZONE_GEO     z0 ON z0.CodeZG   = so.CodeZG                  -- commune (FR) ou Gemeinde (DE)
          JOIN PAYS         pa ON pa.CodePays = z0.CodePays
          JOIN CATEGORIE_JURIDIQUE c3 ON c3.CodeCJ = so.CodeCJ             -- niveau 3 (obligatoire, FR et DE)
          JOIN CATEGORIE_JURIDIQUE c2 ON c2.CodeCJ = c3.CodeCJ_niveau_superieur
          JOIN CATEGORIE_JURIDIQUE c1 ON c1.CodeCJ = c2.CodeCJ_niveau_superieur
          LEFT JOIN TYPE_SOCIETE ty ON ty.CodeTy = so.CodeTy
          LEFT JOIN SALARIE_RH   rh ON rh.CodeE  = e.CodeE                 -- fiche RH facultative
          LEFT JOIN DOMAINE d1 ON d1.CodeDO = so.CodeDO                    -- NAF : pas de code en Allemagne
          LEFT JOIN DOMAINE d2 ON d2.CodeDO = d1.CodeDO_Sup                -- un niveau peut etre saute
          LEFT JOIN DOMAINE d3 ON d3.CodeDO = d2.CodeDO_Sup
          LEFT JOIN DOMAINE d4 ON d4.CodeDO = d3.CodeDO_Sup
          LEFT JOIN ZONE_GEO z1 ON z1.CodeZG = z0.CodeZG_zone_englobante  -- departement (FR) ou Kreis (DE)
          LEFT JOIN ZONE_GEO z2 ON z2.CodeZG = z1.CodeZG_zone_englobante  -- region (FR) ; district ou Land (DE)
          LEFT JOIN ZONE_GEO z3 ON z3.CodeZG = z2.CodeZG_zone_englobante; -- Land (DE) quand z2 est un district

ALTER TABLE EMPLOYE_MD2 ADD CONSTRAINT pk_employe_md2 PRIMARY KEY (CodeEmploye);

CREATE DIMENSION EMPLOYE_DIM2
   LEVEL CodeEmploye     IS (EMPLOYE_MD2.CodeEmploye)
   LEVEL CodeService     IS (EMPLOYE_MD2.CodeService)
   LEVEL CodeSociete     IS (EMPLOYE_MD2.CodeSociete)
   LEVEL CodeVille       IS (EMPLOYE_MD2.CodeVille)       SKIP WHEN NULL
   LEVEL CodeDepartement IS (EMPLOYE_MD2.CodeDepartement) SKIP WHEN NULL
   LEVEL CodeGemeinde    IS (EMPLOYE_MD2.CodeGemeinde)    SKIP WHEN NULL
   LEVEL CodeKreis       IS (EMPLOYE_MD2.CodeKreis)       SKIP WHEN NULL
   LEVEL CodeDistrict    IS (EMPLOYE_MD2.CodeDistrict)    SKIP WHEN NULL
   LEVEL CodeRegion      IS (EMPLOYE_MD2.CodeRegion)      SKIP WHEN NULL
   LEVEL CodeLand        IS (EMPLOYE_MD2.CodeLand)        SKIP WHEN NULL
   LEVEL CodePays        IS (EMPLOYE_MD2.CodePays)
   LEVEL CodeTy          IS (EMPLOYE_MD2.CodeTy)
   LEVEL CodeCJ3         IS (EMPLOYE_MD2.CodeCJ3)
   LEVEL CodeCJ2         IS (EMPLOYE_MD2.CodeCJ2)
   LEVEL CodeCJ1         IS (EMPLOYE_MD2.CodeCJ1)
   LEVEL SousClasseNAF   IS (EMPLOYE_MD2.SousClasseNAF)   SKIP WHEN NULL
   LEVEL ClasseNAF       IS (EMPLOYE_MD2.ClasseNAF)       SKIP WHEN NULL
   LEVEL GroupeNAF       IS (EMPLOYE_MD2.GroupeNAF)       SKIP WHEN NULL
   LEVEL DivisionNAF     IS (EMPLOYE_MD2.DivisionNAF)     SKIP WHEN NULL
   LEVEL CodeCategorie   IS (EMPLOYE_MD2.CodeCategorie)
   LEVEL SuperCategorie  IS (EMPLOYE_MD2.SuperCategorie)
   LEVEL TrancheAge      IS (EMPLOYE_MD2.TrancheAge)      SKIP WHEN NULL
HIERARCHY H_France (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                    CHILD OF CodeVille CHILD OF CodeDepartement CHILD OF CodeRegion
                    CHILD OF CodePays)
HIERARCHY H_Allemagne (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                       CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF CodeLand
                       CHILD OF CodePays)
HIERARCHY H_District (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                      CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF CodeDistrict
                      CHILD OF CodeLand CHILD OF CodePays)
HIERARCHY H_Type_Societe (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                          CHILD OF CodeTy)
HIERARCHY H_CJ (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                CHILD OF CodeCJ3 CHILD OF CodeCJ2 CHILD OF CodeCJ1)
HIERARCHY H_NAF (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                 CHILD OF SousClasseNAF CHILD OF ClasseNAF CHILD OF GroupeNAF
                 CHILD OF DivisionNAF)
HIERARCHY H_Categorie (CodeEmploye CHILD OF CodeCategorie CHILD OF SuperCategorie)
HIERARCHY H_Age (CodeEmploye CHILD OF TrancheAge)
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD2.NomEmploye
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD2.PrenomEmploye
ATTRIBUTE CodeService     DETERMINES EMPLOYE_MD2.NomService
ATTRIBUTE CodeSociete     DETERMINES EMPLOYE_MD2.NomSociete
ATTRIBUTE CodeVille       DETERMINES EMPLOYE_MD2.NomVille
ATTRIBUTE CodeDepartement DETERMINES EMPLOYE_MD2.NomDepartement
ATTRIBUTE CodeGemeinde    DETERMINES EMPLOYE_MD2.NomGemeinde
ATTRIBUTE CodeKreis       DETERMINES EMPLOYE_MD2.NomKreis
ATTRIBUTE CodeKreis       DETERMINES EMPLOYE_MD2.TypeKreis
ATTRIBUTE CodeDistrict    DETERMINES EMPLOYE_MD2.NomDistrict
ATTRIBUTE CodeRegion      DETERMINES EMPLOYE_MD2.NomRegion
ATTRIBUTE CodeLand        DETERMINES EMPLOYE_MD2.NomLand
ATTRIBUTE CodeLand        DETERMINES EMPLOYE_MD2.TypeLand
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD2.NomPays
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD2.TauxTVA
ATTRIBUTE CodeTy          DETERMINES EMPLOYE_MD2.LibelleTypeSoc
ATTRIBUTE CodeCJ3         DETERMINES EMPLOYE_MD2.LibelleCJ3
ATTRIBUTE CodeCJ2         DETERMINES EMPLOYE_MD2.LibelleCJ2
ATTRIBUTE CodeCJ1         DETERMINES EMPLOYE_MD2.LibelleCJ1
ATTRIBUTE SousClasseNAF   DETERMINES EMPLOYE_MD2.LibelleNAF
ATTRIBUTE CodeCategorie   DETERMINES EMPLOYE_MD2.NomCategorie;


-- =====================================================================
-- 5) FAIT ACHAT_MD2  (grain : un achat = CodeEmploye x CodeProduit x DateJ, + metier a la date)
--    Quantite_Achat_MD             = SUM(Achat.Qte)
--    Montant_Achat_MD              = SUM(Qte * prix public HT)
--                                    (prix HT = Prix_vente / (1 + TauxTVA) si Tarifer.ModePrix = 'TTC')
--    Montant_Achat_ReelPaye_MD     = SUM(Qte * prix public HT * (1 - PctReduc_Achat))
--    Montant_Achat_ReelPaye_TTC_MD = SUM(Qte * prix public HT * (1 - PctReduc_Achat) * (1 + TauxTVA))
--    Benefice_Achat_MD             = Montant_Achat_MD - Montant_Achat_ReelPaye_MD
--  Comme ACHAT a pour cle (CodeE, CodeP, DateA), chaque groupe ne contient qu'un achat.
--  Le fait est construit depuis l'ED (pas depuis les dimensions), comme LOCATION_MD1.
--  Tarif et reduction en jointures internes : aucun achat au prix public (annexe 1 :
--  PctReduc_Achat > 0) ; les achats ecartes sont listes par les controles (section 7).
-- =====================================================================
CREATE MATERIALIZED VIEW ACHAT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT x.CodeEmploye,
          x.CodeProduit,
          x.CodeAppellation,
          x.DateJ,
          SUM(x.Qte)                                                          AS Quantite_Achat_MD,
          ROUND(SUM(x.Qte * x.PrixHT), 2)                                     AS Montant_Achat_MD,
          ROUND(SUM(x.Qte * x.PrixHT * (1 - x.PctReduc)), 2)                  AS Montant_Achat_ReelPaye_MD,
          ROUND(SUM(x.Qte * x.PrixHT * (1 - x.PctReduc) * (1 + x.TauxTVA)), 2) AS Montant_Achat_ReelPaye_TTC_MD,
          ROUND(SUM(x.Qte * x.PrixHT), 2)
            - ROUND(SUM(x.Qte * x.PrixHT * (1 - x.PctReduc)), 2)              AS Benefice_Achat_MD
   FROM  (SELECT a.CodeE  AS CodeEmploye,
                 a.CodeP  AS CodeProduit,
                 a.DateA  AS DateJ,
                 a.Qte,
                 pa.TauxTVA,
                 CASE WHEN t.ModePrix = 'TTC' THEN t.Prix_vente / (1 + pa.TauxTVA)
                      ELSE t.Prix_vente END                                   AS PrixHT,
                 r.PctReduc_Achat                                             AS PctReduc,
                 -- metier exerce a la date d'achat (le plus recent si deux periodes se chevauchent)
                 NVL((SELECT MAX(ex.CodeAPP) KEEP (DENSE_RANK LAST ORDER BY ex.DateDebutMetier)
                      FROM   SALARIE_RH sr
                             JOIN EXERCER ex ON ex.MatriculeSAL = sr.MatriculeSAL
                                            AND ex.NumEtab      = sr.NumEtab
                      WHERE  sr.CodeE = a.CodeE
                      AND    ex.DateDebutMetier <= a.DateA
                      AND    (ex.DateFinMetier IS NULL OR ex.DateFinMetier >= a.DateA)), 'NR') AS CodeAppellation
          FROM   ACHAT a
                 JOIN EMPLOYE   e  ON e.CodeE     = a.CodeE
                 JOIN SERVICE   se ON se.CodeSE   = e.CodeSE
                 JOIN SOCIETE   so ON so.CodeSOC  = se.CodeSOC
                 JOIN ZONE_GEO  zg ON zg.CodeZG   = so.CodeZG
                 JOIN PAYS      pa ON pa.CodePays = zg.CodePays
                 JOIN PRODUIT   pr ON pr.CodeP    = a.CodeP
                 JOIN TARIFER   t  ON t.CodeP     = a.CodeP
                                  AND t.CodePays  = pa.CodePays
                                  AND t.DateDebutTarif <= a.DateA
                                  AND (t.DateFinTarif IS NULL OR t.DateFinTarif >= a.DateA)
                 JOIN REDUCTION r  ON r.CodeCAT   = e.CodeCAT
                                  AND r.CodeG     = pr.CodeG
                                  AND r.Annee     = EXTRACT(YEAR FROM a.DateA)) x
   GROUP BY x.CodeEmploye, x.CodeProduit, x.CodeAppellation, x.DateJ;

-- Cle primaire : concatenation des cles etrangeres
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT pk_achat_md2
   PRIMARY KEY (CodeEmploye, CodeProduit, CodeAppellation, DateJ);

-- Cles etrangeres : liaisons avec les dimensions
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_employe_md2
   FOREIGN KEY (CodeEmploye)     REFERENCES EMPLOYE_MD2(CodeEmploye);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_produit_md2
   FOREIGN KEY (CodeProduit)     REFERENCES PRODUIT_MD2(CodeProduit);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_metier_md2
   FOREIGN KEY (CodeAppellation) REFERENCES METIER_MD2(CodeAppellation);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_temps_md2
   FOREIGN KEY (DateJ)           REFERENCES TEMPS_MD2(DateJ);

-- NOT NULL sur les cles etrangeres (CHECK equivalent, comme LOCATION_MD1 ; deja garanti par la cle primaire)
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_employe_md2 CHECK (CodeEmploye IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_produit_md2 CHECK (CodeProduit IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_metier_md2  CHECK (CodeAppellation IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_temps_md2   CHECK (DateJ IS NOT NULL);


-- =====================================================================
-- 6) RAFRAICHISSEMENT DE LA STRUCTURE
--    Comme LOCATION_MD1 : on desactive les cles etrangeres du fait, on rafraichit
--    dimensions puis fait, puis on les reactive.
-- =====================================================================
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 DISABLE CONSTRAINT fk_achat_employe_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 DISABLE CONSTRAINT fk_achat_produit_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 DISABLE CONSTRAINT fk_achat_metier_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 DISABLE CONSTRAINT fk_achat_temps_md2';

  DBMS_MVIEW.REFRESH('TEMPS_MD2',   method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('PRODUIT_MD2', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('METIER_MD2',  method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EMPLOYE_MD2', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('ACHAT_MD2',   method => 'C', atomic_refresh => TRUE);

  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 ENABLE VALIDATE CONSTRAINT fk_achat_employe_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 ENABLE VALIDATE CONSTRAINT fk_achat_produit_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 ENABLE VALIDATE CONSTRAINT fk_achat_metier_md2';
  EXECUTE IMMEDIATE 'ALTER TABLE ACHAT_MD2 ENABLE VALIDATE CONSTRAINT fk_achat_temps_md2';
END;
/


-- =====================================================================
-- 7) CONTROLES (a lancer apres chargement)
-- =====================================================================
-- Quantites : le fait doit contenir toutes les quantites de l'ED (ecart = 0)
-- SELECT (SELECT SUM(Qte) FROM ACHAT) - (SELECT SUM(Quantite_Achat_MD) FROM ACHAT_MD2) AS ecart FROM dual;

-- Achats de l'ED absents du fait (pas de tarif ou pas de reduction a la date) :
-- SELECT a.CodeE, a.CodeP, a.DateA, a.Qte FROM ACHAT a
--  WHERE NOT EXISTS (SELECT 1 FROM ACHAT_MD2 f
--                     WHERE f.CodeEmploye = a.CodeE AND f.CodeProduit = a.CodeP AND f.DateJ = a.DateA);

-- Tarifs qui se chevauchent pour un meme produit et un meme pays (un achat serait compte deux fois) :
-- SELECT t1.CodeP, t1.CodePays, t1.DateDebutTarif, t2.DateDebutTarif FROM TARIFER t1, TARIFER t2
--  WHERE t1.CodeP = t2.CodeP AND t1.CodePays = t2.CodePays AND t1.DateDebutTarif < t2.DateDebutTarif
--    AND (t1.DateFinTarif IS NULL OR t1.DateFinTarif >= t2.DateDebutTarif);

-- Periodes de metier qui se chevauchent (le metier le plus recent est alors retenu) :
-- SELECT x1.MatriculeSAL, x1.NumEtab, x1.DateDebutMetier, x2.DateDebutMetier FROM EXERCER x1, EXERCER x2
--  WHERE x1.MatriculeSAL = x2.MatriculeSAL AND x1.NumEtab = x2.NumEtab
--    AND x1.DateDebutMetier < x2.DateDebutMetier
--    AND (x1.DateFinMetier IS NULL OR x1.DateFinMetier >= x2.DateDebutMetier);

-- Chaque employe doit avoir exactement UN des deux : region (France) ou Land (Allemagne) -> 0 attendu
-- SELECT COUNT(*) FROM EMPLOYE_MD2
--  WHERE (CodeRegion IS NULL AND CodeLand IS NULL) OR (CodeRegion IS NOT NULL AND CodeLand IS NOT NULL);

-- Validation des hierarchies declarees (creer d'abord DIMENSION_EXCEPTIONS avec utldim.sql) :
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('TEMPS_DIM2',   FALSE, TRUE, 'verif_temps2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('PRODUIT_DIM2', FALSE, TRUE, 'verif_prod2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('METIER_DIM2',  FALSE, TRUE, 'verif_met2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EMPLOYE_DIM2', FALSE, TRUE, 'verif_emp2');
-- SELECT * FROM DIMENSION_EXCEPTIONS;

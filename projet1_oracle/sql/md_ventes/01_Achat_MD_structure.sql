-- =====================================================================
-- MobiPass - Magasin ACHAT_MD (ventes, R-OLAP denormalise) - STRUCTURE
-- Dimensions TEMPS_MD2, PRODUIT_MD2, METIER_MD2, EMPLOYE_MD2 + fait ACHAT_MD2
--
-- Construit a partir de :
--   * l'entrepot de donnees (01_creation_ED.sql : tables sans suffixe _DW) ;
--   * le schema multidimensionnel Achat_MD (noms des parametres, attributs faibles,
--     hierarchies et mesures repris a l'identique).
-- Meme demarche que LOCATION_MD1 (cours F. Ravat) :
--   dimension : CREATE MATERIALIZED VIEW -> PRIMARY KEY -> CREATE DIMENSION
--   fait      : CREATE MATERIALIZED VIEW -> PRIMARY KEY -> FOREIGN KEY -> NOT NULL
--
-- Ecarts de nommage entre le schema et Oracle :
--   * parametre "Date"  -> colonne DateJ (DATE est un mot reserve Oracle)
--   * parametre "Année" -> colonne Annee (pas d'accent dans les noms Oracle)
--
-- Regles de calcul des mesures :
--   * tarif : celui du pays de la societe de l'employe, valable a la date d'achat ;
--     tarifs FR stockes TTC, tarifs DE stockes HT (Tarifer.ModePrix) ;
--     prix public HT = Prix_vente / (1 + TauxTVA) si ModePrix = 'TTC', sinon Prix_vente
--   * reduction : (categorie de l'employe, gamme du produit, annee d'achat) ;
--     aucun achat ne se fait au prix public (PctReduc_Achat > 0) : un achat sans tarif
--     ou sans reduction n'est pas charge et est liste par les controles (section 6)
--   * montant reellement paye en TTC (depense de l'employe, meme convention que Location_MD) ;
--     benefice en HT (la TVA est reversee a l'Etat)
--   * metier : celui exerce a la date d'achat (historique des metiers) ;
--     'NR' (non renseigne) s'il n'y en a pas (salaries allemands : le ROME est francais)
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
            WHERE mview_name IN ('ACHAT_MD2','TEMPS_MD2','PRODUIT_MD2','METIER_MD2','EMPLOYE_MD2')
            ORDER BY DECODE(mview_name,'ACHAT_MD2',1,2)) LOOP
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || v.mview_name;
  END LOOP;
END;
/


-- =====================================================================
-- 1) DIMENSION TEMPS_MD2
--    H_temps : DateJ -> Num_Mois -> Annee      (sujet : analyse par jour, mois, annee)
-- =====================================================================
CREATE MATERIALIZED VIEW TEMPS_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT DISTINCT DateA                                      AS DateJ,
                   TO_CHAR(DateA, 'YYYY-MM')                    AS Num_Mois,
                   TO_CHAR(DateA, 'fmMonth YYYY',
                           'NLS_DATE_LANGUAGE=FRENCH')          AS LibMois,
                   EXTRACT(YEAR FROM DateA)                     AS Annee
   FROM ACHAT;                                                  -- dates d'achat

ALTER TABLE TEMPS_MD2 ADD CONSTRAINT pk_temps_md2 PRIMARY KEY (DateJ);

CREATE DIMENSION TEMPS_DIM2
   LEVEL DateJ    IS (TEMPS_MD2.DateJ)
   LEVEL Num_Mois IS (TEMPS_MD2.Num_Mois)
   LEVEL Annee    IS (TEMPS_MD2.Annee)
HIERARCHY H_temps (DateJ CHILD OF Num_Mois CHILD OF Annee)
ATTRIBUTE Num_Mois DETERMINES TEMPS_MD2.LibMois;


-- =====================================================================
-- 2) DIMENSION PRODUIT_MD2
--    H_gamme     : CodeP -> CodeG -> SecteurG
--    H_marque    : CodeP -> MarqueP
--    H_autonomie : CodeP -> ClasseAutonomie            (0,1 : produits sans autonomie)
--    H_fabricant : CodeP -> CodeGEN -> CodeFAB -> PaysFAB
--    H_statut    : CodeP -> CodeGEN -> StatutGEN
-- =====================================================================
CREATE MATERIALIZED VIEW PRODUIT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT pr.CodeP,
          pr.NomP,
          pr.DescriptifP,
          pr.PoidsKg,
          pr.MarqueP,
          CASE WHEN pr.AutonomieKm IS NULL THEN NULL
               WHEN pr.AutonomieKm <  40   THEN 'Moins de 40 km'
               WHEN pr.AutonomieKm <= 80   THEN '40 à 80 km'
               ELSE 'Plus de 80 km' END                           AS ClasseAutonomie,
          ga.CodeG,
          ga.NomG,
          ga.SecteurG,
          ge.CodeGEN,
          ge.NomGEN,
          ge.DateSortieGEN,
          CASE WHEN ge.DateArretGEN IS NOT NULL AND ge.DateArretGEN <= SYSDATE
               THEN 'Arrêtée' ELSE 'Commercialisée' END           AS StatutGEN,
          fa.CodeFAB,
          fa.NomFAB,
          fa.PaysFAB
   FROM   PRODUIT    pr
          JOIN GAMME      ga ON ga.CodeG   = pr.CodeG
          JOIN GENERATION ge ON ge.CodeGEN = pr.CodeGEN
          JOIN FABRICANT  fa ON fa.CodeFAB = ge.CodeFAB;

ALTER TABLE PRODUIT_MD2 ADD CONSTRAINT pk_produit_md2 PRIMARY KEY (CodeP);

CREATE DIMENSION PRODUIT_DIM2
   LEVEL CodeP           IS (PRODUIT_MD2.CodeP)
   LEVEL CodeG           IS (PRODUIT_MD2.CodeG)
   LEVEL SecteurG        IS (PRODUIT_MD2.SecteurG)
   LEVEL MarqueP         IS (PRODUIT_MD2.MarqueP)
   LEVEL ClasseAutonomie IS (PRODUIT_MD2.ClasseAutonomie) SKIP WHEN NULL
   LEVEL CodeGEN         IS (PRODUIT_MD2.CodeGEN)
   LEVEL CodeFAB         IS (PRODUIT_MD2.CodeFAB)
   LEVEL PaysFAB         IS (PRODUIT_MD2.PaysFAB)
   LEVEL StatutGEN       IS (PRODUIT_MD2.StatutGEN)
HIERARCHY H_gamme     (CodeP CHILD OF CodeG CHILD OF SecteurG)
HIERARCHY H_marque    (CodeP CHILD OF MarqueP)
HIERARCHY H_autonomie (CodeP CHILD OF ClasseAutonomie)
HIERARCHY H_fabricant (CodeP CHILD OF CodeGEN CHILD OF CodeFAB CHILD OF PaysFAB)
HIERARCHY H_statut    (CodeP CHILD OF CodeGEN CHILD OF StatutGEN)
ATTRIBUTE CodeP   DETERMINES PRODUIT_MD2.NomP
ATTRIBUTE CodeP   DETERMINES PRODUIT_MD2.DescriptifP
ATTRIBUTE CodeP   DETERMINES PRODUIT_MD2.PoidsKg
ATTRIBUTE CodeG   DETERMINES PRODUIT_MD2.NomG
ATTRIBUTE CodeGEN DETERMINES PRODUIT_MD2.NomGEN
ATTRIBUTE CodeGEN DETERMINES PRODUIT_MD2.DateSortieGEN
ATTRIBUTE CodeFAB DETERMINES PRODUIT_MD2.NomFAB;


-- =====================================================================
-- 3) DIMENSION METIER_MD2
--    H_metier : CodeAPP -> CodeROME -> CodeDP -> CodeGD
--    + un membre 'NR' (Non renseigne) pour les achats sans metier connu
-- =====================================================================
CREATE MATERIALIZED VIEW METIER_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT ap.CodeAPP,
          ap.LibelleAPP,
          fm.CodeROME,
          fm.LibelleMetier,
          dp.CodeDP,
          dp.LibelleDP,
          gd.CodeGD,
          gd.LibelleGD
   FROM   APPELLATION ap
          JOIN FICHE_METIER  fm ON fm.CodeROME = ap.CodeROME
          JOIN DOMAINE_PRO   dp ON dp.CodeDP   = fm.CodeDP
          JOIN GRAND_DOMAINE gd ON gd.CodeGD   = dp.CodeGD
   UNION ALL
   SELECT 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné'
   FROM   dual;

ALTER TABLE METIER_MD2 ADD CONSTRAINT pk_metier_md2 PRIMARY KEY (CodeAPP);

CREATE DIMENSION METIER_DIM2
   LEVEL CodeAPP  IS (METIER_MD2.CodeAPP)
   LEVEL CodeROME IS (METIER_MD2.CodeROME)
   LEVEL CodeDP   IS (METIER_MD2.CodeDP)
   LEVEL CodeGD   IS (METIER_MD2.CodeGD)
HIERARCHY H_metier (CodeAPP CHILD OF CodeROME CHILD OF CodeDP CHILD OF CodeGD)
ATTRIBUTE CodeAPP  DETERMINES METIER_MD2.LibelleAPP
ATTRIBUTE CodeROME DETERMINES METIER_MD2.LibelleMetier
ATTRIBUTE CodeDP   DETERMINES METIER_MD2.LibelleDP
ATTRIBUTE CodeGD   DETERMINES METIER_MD2.LibelleGD;


-- =====================================================================
-- 4) DIMENSION EMPLOYE_MD2  (service / societe ACTUELS de l'employe, comme EMPLOYE_MD1)
--    H_AGE     : CodeE -> TrancheAge                                   (0,1 : sans fiche RH)
--    H_CAT     : CodeE -> CodeCAT -> SuperCAT
--    H_FR      : CodeE -> CodeSE -> CodeSOC -> CodeV -> CodeDep -> CodeRegion -> CodePays
--    H_ALL     : CodeE -> CodeSE -> CodeSOC -> CodeGem -> CodeKre -> CodeLand -> CodePays
--    H_DIST    : CodeE -> CodeSE -> CodeSOC -> CodeGem -> CodeKre -> CodeDist -> CodeLand -> CodePays
--    H_DOMAINE : CodeE -> CodeSE -> CodeSOC -> CodeDO -> CodeSuperDO       (0,1 : pas de NAF en DE)
--    H_CATJUR  : CodeE -> CodeSE -> CodeSOC -> CodeCJ3 -> CodeCJ2 -> CodeCJ1
--    H_TY      : CodeE -> CodeSE -> CodeSOC -> CodeTy
--  Geographie identique a EMPLOYE_MD1 : z0 = zone de la societe (commune ou Gemeinde),
--  z1 = parent (departement ou Kreis), z2 = parent (region, district ou Land),
--  z3 = Land quand z2 est un district ; une chaine absente donne NULL (SKIP WHEN NULL).
--  TrancheAge = age actuel (calcule avec SYSDATE a chaque rafraichissement).
-- =====================================================================
CREATE MATERIALIZED VIEW EMPLOYE_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT e.CodeE,
          e.NomE,
          e.PrenomE,
          CASE WHEN rh.DateNaissSAL IS NULL THEN NULL
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 25 * 12 THEN 'Moins de 25 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 35 * 12 THEN '25 à 34 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 45 * 12 THEN '35 à 44 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 55 * 12 THEN '45 à 54 ans'
               ELSE '55 ans et plus' END                               AS TrancheAge,
          ca.CodeCAT,
          ca.NomCAT,
          ca.SuperCAT,
          se.CodeSE,
          se.NomSE,
          so.CodeSOC,
          so.NomSOC,
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.CodeZG END     AS CodeV,
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.NomZG  END     AS NomV,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.CodeZG END     AS CodeDep,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.NomZG  END     AS NomDep,
          CASE WHEN z2.NiveauZG = 'REGION'      THEN z2.CodeZG END     AS CodeRegion,
          CASE WHEN z2.NiveauZG = 'REGION'      THEN z2.NomZG  END     AS NomRegion,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.CodeZG END     AS CodeGem,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.NomZG  END     AS NomGemeinde,
          CASE WHEN z1.NiveauZG IN ('LANDKREIS','KREISFREIE STADT') THEN z1.CodeZG END AS CodeKre,
          CASE WHEN z1.NiveauZG IN ('LANDKREIS','KREISFREIE STADT') THEN z1.NomZG  END AS NomKreis,
          CASE z1.NiveauZG WHEN 'LANDKREIS'        THEN 'Landkreis'
                           WHEN 'KREISFREIE STADT' THEN 'Kreisfreie Stadt' END     AS TypeKreis,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.CodeZG END     AS CodeDist,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.NomZG  END     AS NomDistrict,
          CASE WHEN z2.NiveauZG = 'LAND' THEN z2.CodeZG
               WHEN z3.NiveauZG = 'LAND' THEN z3.CodeZG END            AS CodeLand,
          CASE WHEN z2.NiveauZG = 'LAND' THEN z2.NomZG
               WHEN z3.NiveauZG = 'LAND' THEN z3.NomZG END             AS NomLand,
          CASE WHEN z2.NiveauZG = 'LAND' AND z2.CodeZG IN ('DE02','DE04','DE11') THEN 'Stadtstaat'
               WHEN z2.NiveauZG = 'LAND' OR z3.NiveauZG = 'LAND'                 THEN 'Flächenland'
          END                                                          AS TypeLand,
          pa.CodePays,
          pa.NomPays,
          pa.TauxTVA,
          d1.CodeDO,
          d1.NomDO,
          d2.CodeDO                                                    AS CodeSuperDO,
          d2.NomDO                                                     AS NomSuperDO,
          c3.CodeCJ                                                    AS CodeCJ3,
          c3.LibelleCJ                                                 AS LibelleCJ3,
          c2.CodeCJ                                                    AS CodeCJ2,
          c2.LibelleCJ                                                 AS LibelleCJ2,
          c1.CodeCJ                                                    AS CodeCJ1,
          c1.LibelleCJ                                                 AS LibelleCJ1,
          ty.CodeTy,
          ty.LibelleTypeSoc
   FROM   EMPLOYE e
          JOIN SERVICE      se ON se.CodeSE   = e.CodeSE
          JOIN SOCIETE      so ON so.CodeSOC  = se.CodeSOC
          JOIN CATEGORIE    ca ON ca.CodeCAT  = e.CodeCAT
          JOIN ZONE_GEO     z0 ON z0.CodeZG   = so.CodeZG                  -- commune (FR) ou Gemeinde (DE)
          JOIN PAYS         pa ON pa.CodePays = z0.CodePays
          JOIN CATEGORIE_JURIDIQUE c3 ON c3.CodeCJ = so.CodeCJ             -- niveau 3, obligatoire (FR et DE)
          JOIN CATEGORIE_JURIDIQUE c2 ON c2.CodeCJ = c3.CodeCJ_niveau_superieur
          JOIN CATEGORIE_JURIDIQUE c1 ON c1.CodeCJ = c2.CodeCJ_niveau_superieur
          LEFT JOIN TYPE_SOCIETE ty ON ty.CodeTy = so.CodeTy
          LEFT JOIN SALARIE_RH   rh ON rh.CodeE  = e.CodeE                 -- fiche RH facultative
          LEFT JOIN DOMAINE d1 ON d1.CodeDO = so.CodeDO                    -- pas de code NAF en Allemagne
          LEFT JOIN DOMAINE d2 ON d2.CodeDO = d1.CodeDO_Sup                -- super-domaine (code NAF plus court)
          LEFT JOIN ZONE_GEO z1 ON z1.CodeZG = z0.CodeZG_zone_englobante  -- departement (FR) ou Kreis (DE)
          LEFT JOIN ZONE_GEO z2 ON z2.CodeZG = z1.CodeZG_zone_englobante  -- region (FR) ; district ou Land (DE)
          LEFT JOIN ZONE_GEO z3 ON z3.CodeZG = z2.CodeZG_zone_englobante; -- Land (DE) quand z2 est un district

ALTER TABLE EMPLOYE_MD2 ADD CONSTRAINT pk_employe_md2 PRIMARY KEY (CodeE);

CREATE DIMENSION EMPLOYE_DIM2
   LEVEL CodeE       IS (EMPLOYE_MD2.CodeE)
   LEVEL TrancheAge  IS (EMPLOYE_MD2.TrancheAge)  SKIP WHEN NULL
   LEVEL CodeCAT     IS (EMPLOYE_MD2.CodeCAT)
   LEVEL SuperCAT    IS (EMPLOYE_MD2.SuperCAT)
   LEVEL CodeSE      IS (EMPLOYE_MD2.CodeSE)
   LEVEL CodeSOC     IS (EMPLOYE_MD2.CodeSOC)
   LEVEL CodeV       IS (EMPLOYE_MD2.CodeV)       SKIP WHEN NULL
   LEVEL CodeDep     IS (EMPLOYE_MD2.CodeDep)     SKIP WHEN NULL
   LEVEL CodeRegion  IS (EMPLOYE_MD2.CodeRegion)  SKIP WHEN NULL
   LEVEL CodeGem     IS (EMPLOYE_MD2.CodeGem)     SKIP WHEN NULL
   LEVEL CodeKre     IS (EMPLOYE_MD2.CodeKre)     SKIP WHEN NULL
   LEVEL CodeDist    IS (EMPLOYE_MD2.CodeDist)    SKIP WHEN NULL
   LEVEL CodeLand    IS (EMPLOYE_MD2.CodeLand)    SKIP WHEN NULL
   LEVEL CodePays    IS (EMPLOYE_MD2.CodePays)
   LEVEL CodeDO      IS (EMPLOYE_MD2.CodeDO)      SKIP WHEN NULL
   LEVEL CodeSuperDO IS (EMPLOYE_MD2.CodeSuperDO) SKIP WHEN NULL
   LEVEL CodeCJ3     IS (EMPLOYE_MD2.CodeCJ3)
   LEVEL CodeCJ2     IS (EMPLOYE_MD2.CodeCJ2)
   LEVEL CodeCJ1     IS (EMPLOYE_MD2.CodeCJ1)
   LEVEL CodeTy      IS (EMPLOYE_MD2.CodeTy)
HIERARCHY H_AGE (CodeE CHILD OF TrancheAge)
HIERARCHY H_CAT (CodeE CHILD OF CodeCAT CHILD OF SuperCAT)
HIERARCHY H_FR  (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeV
                 CHILD OF CodeDep CHILD OF CodeRegion CHILD OF CodePays)
HIERARCHY H_ALL (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeGem
                 CHILD OF CodeKre CHILD OF CodeLand CHILD OF CodePays)
HIERARCHY H_DIST (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeGem
                  CHILD OF CodeKre CHILD OF CodeDist CHILD OF CodeLand CHILD OF CodePays)
HIERARCHY H_DOMAINE (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeDO
                     CHILD OF CodeSuperDO)
HIERARCHY H_CATJUR (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeCJ3
                    CHILD OF CodeCJ2 CHILD OF CodeCJ1)
HIERARCHY H_TY (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeTy)
ATTRIBUTE CodeE        DETERMINES EMPLOYE_MD2.NomE
ATTRIBUTE CodeE        DETERMINES EMPLOYE_MD2.PrenomE
ATTRIBUTE CodeCAT      DETERMINES EMPLOYE_MD2.NomCAT
ATTRIBUTE CodeSE       DETERMINES EMPLOYE_MD2.NomSE
ATTRIBUTE CodeSOC      DETERMINES EMPLOYE_MD2.NomSOC
ATTRIBUTE CodeV        DETERMINES EMPLOYE_MD2.NomV
ATTRIBUTE CodeDep      DETERMINES EMPLOYE_MD2.NomDep
ATTRIBUTE CodeRegion   DETERMINES EMPLOYE_MD2.NomRegion
ATTRIBUTE CodeGem      DETERMINES EMPLOYE_MD2.NomGemeinde
ATTRIBUTE CodeKre      DETERMINES EMPLOYE_MD2.NomKreis
ATTRIBUTE CodeKre      DETERMINES EMPLOYE_MD2.TypeKreis
ATTRIBUTE CodeDist     DETERMINES EMPLOYE_MD2.NomDistrict
ATTRIBUTE CodeLand     DETERMINES EMPLOYE_MD2.NomLand
ATTRIBUTE CodeLand     DETERMINES EMPLOYE_MD2.TypeLand
ATTRIBUTE CodePays     DETERMINES EMPLOYE_MD2.NomPays
ATTRIBUTE CodePays     DETERMINES EMPLOYE_MD2.TauxTVA
ATTRIBUTE CodeDO       DETERMINES EMPLOYE_MD2.NomDO
ATTRIBUTE CodeSuperDO  DETERMINES EMPLOYE_MD2.NomSuperDO
ATTRIBUTE CodeCJ3      DETERMINES EMPLOYE_MD2.LibelleCJ3
ATTRIBUTE CodeCJ2      DETERMINES EMPLOYE_MD2.LibelleCJ2
ATTRIBUTE CodeCJ1      DETERMINES EMPLOYE_MD2.LibelleCJ1
ATTRIBUTE CodeTy       DETERMINES EMPLOYE_MD2.LibelleTypeSoc;


-- =====================================================================
-- 5) FAIT ACHAT_MD2  (grain : un achat = CodeE x CodeP x DateJ, avec le metier a la date)
--    Qte_Achat_MD            = SUM(Achat.Qte)
--    MontantPayeTTC_Achat_MD = SUM(Qte * prix public HT * (1 - PctReduc_Achat) * (1 + TauxTVA))
--    BeneficeHT_Achat_MD     = SUM(Qte * prix public HT) - SUM(Qte * prix public HT * (1 - PctReduc_Achat))
--  Le montant au prix public n'est pas stocke (non demande par le sujet) : il sert
--  uniquement de valeur intermediaire au calcul du benefice.
--  ACHAT a pour cle (CodeE, CodeP, DateA) : chaque groupe ne contient qu'un achat.
--  Le fait est construit depuis l'ED (independant des vues de dimensions), comme LOCATION_MD1.
-- =====================================================================
CREATE MATERIALIZED VIEW ACHAT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT x.CodeE,
          x.CodeP,
          x.CodeAPP,
          x.DateJ,
          SUM(x.Qte)                                                           AS Qte_Achat_MD,
          ROUND(SUM(x.Qte * x.PrixHT * (1 - x.PctReduc) * (1 + x.TauxTVA)), 2) AS MontantPayeTTC_Achat_MD,
          ROUND(SUM(x.Qte * x.PrixHT), 2)
            - ROUND(SUM(x.Qte * x.PrixHT * (1 - x.PctReduc)), 2)               AS BeneficeHT_Achat_MD
   FROM  (SELECT a.CodeE,
                 a.CodeP,
                 a.DateA  AS DateJ,
                 a.Qte,
                 pa.TauxTVA,
                 CASE WHEN t.ModePrix = 'TTC' THEN t.Prix_vente / (1 + pa.TauxTVA)
                      ELSE t.Prix_vente END                                    AS PrixHT,
                 r.PctReduc_Achat                                              AS PctReduc,
                 -- metier exerce a la date d'achat (le plus recent si deux periodes se chevauchent)
                 NVL((SELECT MAX(ex.CodeAPP) KEEP (DENSE_RANK LAST ORDER BY ex.DateDebutMetier)
                      FROM   SALARIE_RH sr
                             JOIN EXERCER ex ON ex.MatriculeSAL = sr.MatriculeSAL
                                            AND ex.NumEtab      = sr.NumEtab
                      WHERE  sr.CodeE = a.CodeE
                      AND    ex.DateDebutMetier <= a.DateA
                      AND    (ex.DateFinMetier IS NULL OR ex.DateFinMetier >= a.DateA)), 'NR') AS CodeAPP
          FROM   ACHAT a
                 JOIN EMPLOYE   e  ON e.CodeE     = a.CodeE
                 JOIN SERVICE   se ON se.CodeSE   = e.CodeSE
                 JOIN SOCIETE   so ON so.CodeSOC  = se.CodeSOC
                 JOIN ZONE_GEO  zg ON zg.CodeZG   = so.CodeZG
                 JOIN PAYS      pa ON pa.CodePays = zg.CodePays
                 JOIN PRODUIT   pr ON pr.CodeP    = a.CodeP
                 JOIN TARIFER   t  ON t.CodeP     = a.CodeP                 -- tarif du pays, valable a la date
                                  AND t.CodePays  = pa.CodePays
                                  AND t.DateDebutTarif <= a.DateA
                                  AND (t.DateFinTarif IS NULL OR t.DateFinTarif >= a.DateA)
                 JOIN REDUCTION r  ON r.CodeCAT   = e.CodeCAT               -- profil, gamme, annee
                                  AND r.CodeG     = pr.CodeG
                                  AND r.Annee     = EXTRACT(YEAR FROM a.DateA)) x
   GROUP BY x.CodeE, x.CodeP, x.CodeAPP, x.DateJ;

-- Cle primaire : concatenation des cles etrangeres
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT pk_achat_md2
   PRIMARY KEY (CodeE, CodeP, CodeAPP, DateJ);

-- Cles etrangeres : liaisons avec les dimensions
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_employe_md2
   FOREIGN KEY (CodeE)   REFERENCES EMPLOYE_MD2(CodeE);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_produit_md2
   FOREIGN KEY (CodeP)   REFERENCES PRODUIT_MD2(CodeP);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_metier_md2
   FOREIGN KEY (CodeAPP) REFERENCES METIER_MD2(CodeAPP);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT fk_achat_temps_md2
   FOREIGN KEY (DateJ)   REFERENCES TEMPS_MD2(DateJ);

-- NOT NULL sur les cles etrangeres (CHECK equivalent, comme LOCATION_MD1)
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_employe_md2 CHECK (CodeE   IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_produit_md2 CHECK (CodeP   IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_metier_md2  CHECK (CodeAPP IS NOT NULL);
ALTER TABLE ACHAT_MD2 ADD CONSTRAINT nn_achat_temps_md2   CHECK (DateJ   IS NOT NULL);


-- =====================================================================
-- 6) RAFRAICHISSEMENT DE LA STRUCTURE (comme LOCATION_MD1)
--    On desactive les cles etrangeres du fait, on rafraichit dimensions puis fait,
--    puis on les reactive.
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
-- SELECT (SELECT SUM(Qte) FROM ACHAT) - (SELECT SUM(Qte_Achat_MD) FROM ACHAT_MD2) AS ecart FROM dual;

-- Achats de l'ED absents du fait (pas de tarif ou pas de reduction a la date) :
-- SELECT a.CodeE, a.CodeP, a.DateA, a.Qte FROM ACHAT a
--  WHERE NOT EXISTS (SELECT 1 FROM ACHAT_MD2 f
--                     WHERE f.CodeE = a.CodeE AND f.CodeP = a.CodeP AND f.DateJ = a.DateA);

-- Tarifs qui se chevauchent pour un meme produit et un meme pays (achat compte deux fois) :
-- SELECT t1.CodeP, t1.CodePays, t1.DateDebutTarif, t2.DateDebutTarif FROM TARIFER t1, TARIFER t2
--  WHERE t1.CodeP = t2.CodeP AND t1.CodePays = t2.CodePays AND t1.DateDebutTarif < t2.DateDebutTarif
--    AND (t1.DateFinTarif IS NULL OR t1.DateFinTarif >= t2.DateDebutTarif);

-- Periodes de metier qui se chevauchent (le metier le plus recent est alors retenu) :
-- SELECT x1.MatriculeSAL, x1.NumEtab, x1.DateDebutMetier, x2.DateDebutMetier FROM EXERCER x1, EXERCER x2
--  WHERE x1.MatriculeSAL = x2.MatriculeSAL AND x1.NumEtab = x2.NumEtab
--    AND x1.DateDebutMetier < x2.DateDebutMetier
--    AND (x1.DateFinMetier IS NULL OR x1.DateFinMetier >= x2.DateDebutMetier);

-- Chaque employe a exactement UN des deux : region (France) ou Land (Allemagne) -> 0 attendu
-- SELECT COUNT(*) FROM EMPLOYE_MD2
--  WHERE (CodeRegion IS NULL AND CodeLand IS NULL) OR (CodeRegion IS NOT NULL AND CodeLand IS NOT NULL);

-- Validation des hierarchies declarees (creer d'abord DIMENSION_EXCEPTIONS avec utldim.sql) :
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('TEMPS_DIM2',   FALSE, TRUE, 'verif_temps2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('PRODUIT_DIM2', FALSE, TRUE, 'verif_prod2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('METIER_DIM2',  FALSE, TRUE, 'verif_met2');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EMPLOYE_DIM2', FALSE, TRUE, 'verif_emp2');
-- SELECT * FROM DIMENSION_EXCEPTIONS;

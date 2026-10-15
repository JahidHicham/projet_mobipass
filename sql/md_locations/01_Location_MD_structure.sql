-- =====================================================================
-- MobiPass - Magasin LOCATION_MD - 01 STRUCTURE (dimensions + fait)
-- Methode du cours (F. Ravat) : pour chaque dimension
--   1) CREATE MATERIALIZED VIEW  (table + alimentation depuis l'ED)
--   2) ALTER TABLE ... PRIMARY KEY
--   3) CREATE DIMENSION          (niveaux, hierarchies, attributs faibles)
-- puis le fait (MV + PK + FK).
-- Les agregats (treillis partiel) sont dans 02_Location_MD_agregats.sql.
--
-- Conventions :
--  * Tables de l'ED (entrepot) suffixees _DW (comme dans le cours : CLIENTS_DW...).
--  * Noms ASCII sans accent cote Oracle (DateL, ...).
--  * Niveau "Date" du schema en etoile -> colonne DateJ (DATE est un mot reserve).
--  * Noms des colonnes/niveaux = ceux du JSON Location_MD
--    (CodeReg/NomReg, H_DIST, SecteurP). Lignes marquees [ISO] = Annee_ISO,
--    decision en attente.
-- =====================================================================


-- =====================================================================
-- 0) Vue utilitaire : ancetres d'une zone geographique (ZONE_GEO_DW)
--    Une ligne par couple (zone de depart, zone ancetre, y compris elle-meme)
--    -> permet d'extraire COMMUNE / DEPARTEMENT / REGION / GEMEINDE / KREIS /
--       DISTRICT / LAND quelle que soit la profondeur de la hierarchie.
-- =====================================================================
CREATE OR REPLACE VIEW ZG_ANCETRES_V AS
SELECT CONNECT_BY_ROOT CodeZG AS CodeZG_base,
       CodeZG                 AS CodeZG_anc,
       NomZG                  AS NomZG_anc,
       NiveauZG               AS NiveauZG_anc
FROM   ZONE_GEO_DW
CONNECT BY PRIOR CodeZG_zone_englobante = CodeZG;


-- =====================================================================
-- 1) DIMENSION TEMPS_MD
--    H_SEM  : DateJ -> Num_Semaine -> Annee_ISO   [ISO]
--    H_MOIS : DateJ -> Num_Mois    -> Annee
-- =====================================================================
CREATE MATERIALIZED VIEW TEMPS_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT d.DateJ                                              AS DateJ,
          TO_CHAR(d.DateJ, 'IYYY-"S"IW')                       AS Num_Semaine,
          'Semaine ' || TO_CHAR(d.DateJ, 'IW') || ' - '
                     || TO_CHAR(d.DateJ, 'IYYY')               AS LibSemaine,
          TO_NUMBER(TO_CHAR(d.DateJ, 'IYYY'))                  AS Annee_ISO,   -- [ISO]
          TO_CHAR(d.DateJ, 'YYYY-MM')                          AS Num_Mois,
          TO_CHAR(d.DateJ, 'fmMonth YYYY',
                  'NLS_DATE_LANGUAGE=FRENCH')                  AS LibMois,
          EXTRACT(YEAR FROM d.DateJ)                           AS Annee
   FROM   (SELECT DISTINCT DateL AS DateJ FROM LOUER_DW) d;   -- dates de debut de location

ALTER TABLE TEMPS_MD ADD CONSTRAINT pk_temps_md PRIMARY KEY (DateJ);

CREATE DIMENSION TEMPS_MD_DIM
   LEVEL DateJ       IS (TEMPS_MD.DateJ)
   LEVEL Num_Semaine IS (TEMPS_MD.Num_Semaine)
   LEVEL Annee_ISO   IS (TEMPS_MD.Annee_ISO)                                  -- [ISO]
   LEVEL Num_Mois    IS (TEMPS_MD.Num_Mois)
   LEVEL Annee       IS (TEMPS_MD.Annee)
HIERARCHY H_SEM  (DateJ CHILD OF Num_Semaine CHILD OF Annee_ISO)             -- [ISO]
HIERARCHY H_MOIS (DateJ CHILD OF Num_Mois    CHILD OF Annee)
ATTRIBUTE Num_Semaine DETERMINES TEMPS_MD.LibSemaine
ATTRIBUTE Num_Mois    DETERMINES TEMPS_MD.LibMois;


-- =====================================================================
-- 2) DIMENSION EXEMPLAIRE_MD
--    H_GEN : CodeEX -> CodeP -> CodeGEN -> CodeFAB -> PaysFAB
--    H_MAR : CodeEX -> CodeP -> MarqueP
--    H_GAM : CodeEX -> CodeP -> CodeG -> SecteurP
-- =====================================================================
CREATE MATERIALIZED VIEW EXEMPLAIRE_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT ex.CodeEX,
          ex.NumSerieEX,
          ex.DateMiseServiceEX,
          ex.DateReformeEX,
          pr.CodeP,
          pr.NomP,
          pr.DescriptifP,
          pr.PoidsKg,
          pr.AutonomieKm,
          pr.MarqueP,
          ge.CodeGEN,
          ge.NomGEN,
          ge.DateSortieGEN,
          ge.DateArretGEN,
          fa.CodeFAB,
          fa.NomFAB,
          fa.PaysFAB,
          ga.CodeG,
          ga.NomG,
          ga.SecteurG AS SecteurP          -- nom du JSON ; SecteurG dans l'ED (a harmoniser)
   FROM   EXEMPLAIRE_DW ex,
          PRODUIT_DW    pr,
          GENERATION_DW ge,
          FABRICANT_DW  fa,
          GAMME_DW      ga
   WHERE  ex.CodeP   = pr.CodeP
   AND    pr.CodeGEN = ge.CodeGEN
   AND    ge.CodeFAB = fa.CodeFAB
   AND    pr.CodeG   = ga.CodeG;

ALTER TABLE EXEMPLAIRE_MD ADD CONSTRAINT pk_exemplaire_md PRIMARY KEY (CodeEX);

CREATE DIMENSION EXEMPLAIRE_MD_DIM
   LEVEL CodeEX  IS (EXEMPLAIRE_MD.CodeEX)
   LEVEL CodeP   IS (EXEMPLAIRE_MD.CodeP)
   LEVEL CodeGEN IS (EXEMPLAIRE_MD.CodeGEN)
   LEVEL CodeFAB IS (EXEMPLAIRE_MD.CodeFAB)
   LEVEL PaysFAB IS (EXEMPLAIRE_MD.PaysFAB)
   LEVEL MarqueP IS (EXEMPLAIRE_MD.MarqueP)
   LEVEL CodeG   IS (EXEMPLAIRE_MD.CodeG)
   LEVEL SecteurP IS (EXEMPLAIRE_MD.SecteurP)
HIERARCHY H_GEN (CodeEX CHILD OF CodeP CHILD OF CodeGEN CHILD OF CodeFAB CHILD OF PaysFAB)
HIERARCHY H_MAR (CodeEX CHILD OF CodeP CHILD OF MarqueP)
HIERARCHY H_GAM (CodeEX CHILD OF CodeP CHILD OF CodeG CHILD OF SecteurP)
ATTRIBUTE CodeEX  DETERMINES (EXEMPLAIRE_MD.NumSerieEX,
                              EXEMPLAIRE_MD.DateMiseServiceEX,
                              EXEMPLAIRE_MD.DateReformeEX)
ATTRIBUTE CodeP   DETERMINES (EXEMPLAIRE_MD.NomP,
                              EXEMPLAIRE_MD.DescriptifP,
                              EXEMPLAIRE_MD.PoidsKg,
                              EXEMPLAIRE_MD.AutonomieKm)
ATTRIBUTE CodeGEN DETERMINES (EXEMPLAIRE_MD.NomGEN,
                              EXEMPLAIRE_MD.DateSortieGEN,
                              EXEMPLAIRE_MD.DateArretGEN)
ATTRIBUTE CodeG   DETERMINES EXEMPLAIRE_MD.NomG
ATTRIBUTE CodeFAB DETERMINES EXEMPLAIRE_MD.NomFAB;


-- =====================================================================
-- 3) DIMENSION EMPLOYE_MD
--    H_FR   : CodeE -> CodeSE -> CodeSOC -> CodeV -> CodeDep -> CodeReg -> CodePays
--    H_ALL  : CodeE -> CodeSE -> CodeSOC -> CodeGem -> CodeKre -> CodeReg
--    H_DIST : CodeE -> CodeSE -> CodeSOC -> CodeGem -> CodeKre -> CodeDist -> CodeReg
--    H_TY   : CodeE -> CodeSE -> CodeSOC -> CodeTy
--    H_CAT  : CodeE -> CodeCAT -> SuperCAT
--  Hierarchies incompletes : une societe francaise a CodeGem/CodeKre/CodeDist NULL,
--  une societe allemande a CodeV/CodeDep NULL. CodeReg = REGION (FR) ou LAND (DE).
--  Service/societe = situation ACTUELLE de l'employe (hypothese H7).
-- =====================================================================
CREATE MATERIALIZED VIEW EMPLOYE_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT e.CodeE,
          e.NomE,
          e.PrenomE,
          se.CodeSE,
          se.NomSE,
          so.CodeSOC,
          so.NomSOC,
          ty.CodeTy,
          ty.LibelleTypeSoc,
          ca.CodeCAT,
          ca.NomCAT,
          ca.SuperCAT,
          com.CodeZG_anc                          AS CodeV,
          com.NomZG_anc                           AS NomV,
          dep.CodeZG_anc                          AS CodeDep,
          dep.NomZG_anc                           AS NomDep,
          gem.CodeZG_anc                          AS CodeGem,
          gem.NomZG_anc                           AS NomGemeinde,
          kre.CodeZG_anc                          AS CodeKre,
          kre.NomZG_anc                           AS NomKreis,
          dis.CodeZG_anc                          AS CodeDist,
          dis.NomZG_anc                           AS NomDistrict,
          COALESCE(reg.CodeZG_anc, lan.CodeZG_anc) AS CodeReg,
          COALESCE(reg.NomZG_anc,  lan.NomZG_anc)  AS NomReg,
          pa.CodePays,
          pa.NomPays,
          pa.TauxTVA
   FROM   EMPLOYE_DW e
          JOIN SERVICE_DW      se ON se.CodeSE  = e.CodeSE
          JOIN SOCIETE_DW      so ON so.CodeSOC = se.CodeSOC
          JOIN CATEGORIE_DW    ca ON ca.CodeCAT = e.CodeCAT
          JOIN ZONE_GEO_DW     zg ON zg.CodeZG  = so.CodeZG
          JOIN PAYS_DW         pa ON pa.CodePays = zg.CodePays
          LEFT JOIN TYPE_SOCIETE_DW ty ON ty.CodeTy = so.CodeTy
          LEFT JOIN ZG_ANCETRES_V com ON com.CodeZG_base = so.CodeZG AND com.NiveauZG_anc = 'COMMUNE'
          LEFT JOIN ZG_ANCETRES_V dep ON dep.CodeZG_base = so.CodeZG AND dep.NiveauZG_anc = 'DEPARTEMENT'
          LEFT JOIN ZG_ANCETRES_V reg ON reg.CodeZG_base = so.CodeZG AND reg.NiveauZG_anc = 'REGION'
          LEFT JOIN ZG_ANCETRES_V gem ON gem.CodeZG_base = so.CodeZG AND gem.NiveauZG_anc = 'GEMEINDE'
          LEFT JOIN ZG_ANCETRES_V kre ON kre.CodeZG_base = so.CodeZG AND kre.NiveauZG_anc = 'KREIS'
          LEFT JOIN ZG_ANCETRES_V dis ON dis.CodeZG_base = so.CodeZG AND dis.NiveauZG_anc = 'DISTRICT'
          LEFT JOIN ZG_ANCETRES_V lan ON lan.CodeZG_base = so.CodeZG AND lan.NiveauZG_anc = 'LAND';

ALTER TABLE EMPLOYE_MD ADD CONSTRAINT pk_employe_md PRIMARY KEY (CodeE);

CREATE DIMENSION EMPLOYE_MD_DIM
   LEVEL CodeE    IS (EMPLOYE_MD.CodeE)
   LEVEL CodeSE   IS (EMPLOYE_MD.CodeSE)
   LEVEL CodeSOC  IS (EMPLOYE_MD.CodeSOC)
   LEVEL CodeV    IS (EMPLOYE_MD.CodeV)
   LEVEL CodeDep  IS (EMPLOYE_MD.CodeDep)
   LEVEL CodeGem  IS (EMPLOYE_MD.CodeGem)
   LEVEL CodeKre  IS (EMPLOYE_MD.CodeKre)
   LEVEL CodeDist IS (EMPLOYE_MD.CodeDist)
   LEVEL CodeReg  IS (EMPLOYE_MD.CodeReg)
   LEVEL CodePays IS (EMPLOYE_MD.CodePays)
   LEVEL CodeTy   IS (EMPLOYE_MD.CodeTy)
   LEVEL CodeCAT  IS (EMPLOYE_MD.CodeCAT)
   LEVEL SuperCAT IS (EMPLOYE_MD.SuperCAT)
HIERARCHY H_FR (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeV
                CHILD OF CodeDep CHILD OF CodeReg CHILD OF CodePays)
HIERARCHY H_ALL (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeGem
                 CHILD OF CodeKre CHILD OF CodeReg)
HIERARCHY H_DIST (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeGem
                  CHILD OF CodeKre CHILD OF CodeDist CHILD OF CodeReg)
HIERARCHY H_TY  (CodeE CHILD OF CodeSE CHILD OF CodeSOC CHILD OF CodeTy)
HIERARCHY H_CAT (CodeE CHILD OF CodeCAT CHILD OF SuperCAT)
ATTRIBUTE CodeE    DETERMINES (EMPLOYE_MD.NomE, EMPLOYE_MD.PrenomE)
ATTRIBUTE CodeSE   DETERMINES EMPLOYE_MD.NomSE
ATTRIBUTE CodeSOC  DETERMINES EMPLOYE_MD.NomSOC
ATTRIBUTE CodeV    DETERMINES EMPLOYE_MD.NomV
ATTRIBUTE CodeDep  DETERMINES EMPLOYE_MD.NomDep
ATTRIBUTE CodeGem  DETERMINES EMPLOYE_MD.NomGemeinde
ATTRIBUTE CodeKre  DETERMINES EMPLOYE_MD.NomKreis
ATTRIBUTE CodeDist DETERMINES EMPLOYE_MD.NomDistrict
ATTRIBUTE CodeReg  DETERMINES EMPLOYE_MD.NomReg
ATTRIBUTE CodePays DETERMINES (EMPLOYE_MD.NomPays, EMPLOYE_MD.TauxTVA)
ATTRIBUTE CodeTy   DETERMINES EMPLOYE_MD.LibelleTypeSoc
ATTRIBUTE CodeCAT  DETERMINES EMPLOYE_MD.NomCAT;


-- =====================================================================
-- 4) FAIT LOCATION_MD  (grain : une location = CodeE x CodeEX x DateJ)
--    Duree_MD        = Louer.Duree_Loc
--    Montant_MD      = Duree_Loc * Prix_loc_jour, ramene en HT :
--                      /(1+TauxTVA) si Tarifer.ModePrix = 'TTC'
--    MontantReelP_MD = Montant_MD * (1 - PctReduc_Loc)   (0 si pas de reduction)
--  Tarif : celui du pays de la societe de l'employe, valide a la date de debut.
--  Reduction : (categorie de l'employe, gamme du produit, annee de debut).
--  Le fait lit EMPLOYE_MD (CodePays, TauxTVA, CodeCAT) : creer/rafraichir
--  EMPLOYE_MD avant LOCATION_MD.
-- =====================================================================
CREATE MATERIALIZED VIEW LOCATION_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT x.CodeE,
          x.CodeEX,
          x.DateJ,
          x.Duree_MD,
          ROUND(x.montant_ht, 2)                                  AS Montant_MD,
          ROUND(x.montant_ht * (1 - NVL(x.PctReduc_Loc, 0)), 2)   AS MontantReelP_MD
   FROM (SELECT l.CodeE,
                l.CodeEX,
                l.DateL AS DateJ,
                l.Duree_Loc        AS Duree_MD,
                r.PctReduc_Loc,
                CASE WHEN t.ModePrix = 'TTC'
                     THEN l.Duree_Loc * t.Prix_loc_jour / (1 + em.TauxTVA)
                     ELSE l.Duree_Loc * t.Prix_loc_jour
                END AS montant_ht
         FROM   LOUER_DW l
                JOIN EMPLOYE_MD    em ON em.CodeE   = l.CodeE
                JOIN EXEMPLAIRE_DW ex ON ex.CodeEX  = l.CodeEX
                JOIN PRODUIT_DW    pr ON pr.CodeP   = ex.CodeP
                LEFT JOIN TARIFER_DW t
                       ON t.CodeP    = ex.CodeP
                      AND t.CodePays = em.CodePays
                      AND t.DateDebutTarif <= l.DateL
                      AND (t.DateFinTarif IS NULL OR t.DateFinTarif >= l.DateL)
                LEFT JOIN REDUCTION_DW r
                       ON r.CodeCAT = em.CodeCAT
                      AND r.CodeG   = pr.CodeG
                      AND r.Annee   = EXTRACT(YEAR FROM l.DateL)
        ) x;

-- Cle primaire = concatenation des cles etrangeres (le PK implique NOT NULL)
ALTER TABLE LOCATION_MD ADD CONSTRAINT pk_location_md
   PRIMARY KEY (CodeE, CodeEX, DateJ);

ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_employe
   FOREIGN KEY (CodeE)  REFERENCES EMPLOYE_MD(CodeE);
ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_exemplaire
   FOREIGN KEY (CodeEX) REFERENCES EXEMPLAIRE_MD(CodeEX);
ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_temps
   FOREIGN KEY (DateJ)  REFERENCES TEMPS_MD(DateJ);


-- =====================================================================
-- 5) RAFRAICHISSEMENT DE LA STRUCTURE (ordre important ; atomic_refresh => TRUE
--    car des cles etrangeres referencent les dimensions : un TRUNCATE echouerait)
-- =====================================================================
BEGIN
  DBMS_MVIEW.REFRESH('TEMPS_MD',      method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EXEMPLAIRE_MD', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EMPLOYE_MD',    method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('LOCATION_MD',   method => 'C', atomic_refresh => TRUE);
END;
/


-- =====================================================================
-- 6) CONTROLES (a lancer apres chargement)
-- =====================================================================
-- Locations de l'ED absentes du fait (jointure employe/exemplaire) :
-- SELECT (SELECT COUNT(*) FROM LOUER_DW) - (SELECT COUNT(*) FROM LOCATION_MD) AS ecart FROM dual;

-- Locations sans tarif trouve (Montant NULL) :
-- SELECT COUNT(*) FROM LOCATION_MD WHERE Montant_MD IS NULL;

-- Plusieurs tarifs valides pour une meme location (ne doit rien renvoyer, sinon doublons -> PK en erreur) :
-- SELECT CodeP, CodePays, COUNT(*) FROM TARIFER_DW t1 WHERE EXISTS
--   (SELECT 1 FROM TARIFER_DW t2 WHERE t2.CodeP=t1.CodeP AND t2.CodePays=t1.CodePays
--    AND t2.DateDebutTarif < t1.DateDebutTarif
--    AND (t2.DateFinTarif IS NULL OR t2.DateFinTarif >= t1.DateDebutTarif))
--   GROUP BY CodeP, CodePays;

-- Validation des hierarchies declarees (necessite UTLDIM.sql / table DIMENSION_EXCEPTIONS) :
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EMPLOYE_MD_DIM', FALSE, TRUE, 'verif_emp');

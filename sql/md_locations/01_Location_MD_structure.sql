-- =====================================================================
-- MobiPass - Magasin LOCATION_MD (R-OLAP denormalise) - 01 STRUCTURE
-- Dimensions TEMPS_MD, EXEMPLAIRE_MD, EMPLOYE_MD + fait LOCATION_MD
--
-- Demarche du cours (F. Ravat) :
--   dimension : CREATE MATERIALIZED VIEW -> ALTER TABLE ... PRIMARY KEY
--               -> CREATE DIMENSION (niveaux, hierarchies, attributs faibles)
--   fait      : CREATE MATERIALIZED VIEW -> PRIMARY KEY -> FOREIGN KEY -> NOT NULL
--
-- Source : tables de l'ED (sql/ed/01_creation_ED.sql, branche main : noms SANS
-- suffixe _DW). Noms des colonnes du magasin = schema en etoile final
-- (Location_MD.json). Les agregats sont dans 02_Location_MD_agregats.sql.
--
-- Ecarts volontaires entre schema en etoile et Oracle :
--   * niveau "Date" -> colonne DateJ (DATE est un mot reserve Oracle)
--   * CodeGeminede / NomGemiende : noms du schema (fautes de frappe a corriger
--     dans le schema, puis a renommer ici)
-- =====================================================================


-- =====================================================================
-- 1) DIMENSION TEMPS_MD
--    H_SEM  : DateJ -> Num_Semaine -> Annee_ISO   (semaine ISO 8601, lundi-dimanche)
--    H_MOIS : DateJ -> Num_Mois    -> Annee       (annee civile)
-- =====================================================================
CREATE MATERIALIZED VIEW TEMPS_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT DISTINCT DateL                                      AS DateJ,
                   TO_CHAR(DateL, 'IYYY-"S"IW')                 AS Num_Semaine,
                   TO_NUMBER(TO_CHAR(DateL, 'IYYY'))            AS Annee_ISO,
                   TO_CHAR(DateL, 'YYYY-MM')                    AS Num_Mois,
                   TO_CHAR(DateL, 'fmMonth YYYY',
                           'NLS_DATE_LANGUAGE=FRENCH')          AS LibMois,
                   EXTRACT(YEAR FROM DateL)                     AS Annee
   FROM LOUER;                                                  -- dates de debut de location

ALTER TABLE TEMPS_MD ADD CONSTRAINT pk_temps_md PRIMARY KEY (DateJ);

CREATE DIMENSION TEMPS_MD_DIM
   LEVEL DateJ       IS (TEMPS_MD.DateJ)
   LEVEL Num_Semaine IS (TEMPS_MD.Num_Semaine)
   LEVEL Annee_ISO   IS (TEMPS_MD.Annee_ISO)
   LEVEL Num_Mois    IS (TEMPS_MD.Num_Mois)
   LEVEL Annee       IS (TEMPS_MD.Annee)
HIERARCHY H_SEM  (DateJ CHILD OF Num_Semaine CHILD OF Annee_ISO)
HIERARCHY H_MOIS (DateJ CHILD OF Num_Mois    CHILD OF Annee)
ATTRIBUTE Num_Mois DETERMINES TEMPS_MD.LibMois;


-- =====================================================================
-- 2) DIMENSION EXEMPLAIRE_MD
--    H_GENERATION : CodeExemplaire -> CodeProduit -> CodeGeneration
--                   -> CodeFabricant -> PaysFabricant
--    H_MAR        : CodeExemplaire -> CodeProduit -> MarqueProduit
--    H_GAMME      : CodeExemplaire -> CodeProduit -> CodeGamme -> SecteurProduit
-- =====================================================================
CREATE MATERIALIZED VIEW EXEMPLAIRE_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT ex.CodeEX          AS CodeExemplaire,
          ex.NumSerieEX      AS NumeroSerieEXemplaire,
          ex.DateMiseServiceEX AS DateMiseServiceEXemplaire,
          ex.DateReformeEX   AS DateReformeEXemplaire,
          pr.CodeP           AS CodeProduit,
          pr.NomP            AS NomProduit,
          pr.DescriptifP     AS DescriptifProduit,
          pr.PoidsKg         AS PoidsKgProduit,
          pr.AutonomieKm     AS AutonomieKilometreProduit,
          pr.MarqueP         AS MarqueProduit,
          ge.CodeGEN         AS CodeGeneration,
          ge.NomGEN          AS NomGeneration,
          ge.DateSortieGEN   AS DateSortieGeneration,
          ge.DateArretGEN    AS DateArretGeneration,
          fa.CodeFAB         AS CodeFabricant,
          fa.NomFAB          AS NomFabricant,
          fa.PaysFAB         AS PaysFabricant,
          ga.CodeG           AS CodeGamme,
          ga.NomG            AS NomGamme,
          ga.SecteurG        AS SecteurProduit
   FROM   EXEMPLAIRE ex,
          PRODUIT    pr,
          GENERATION ge,
          FABRICANT  fa,
          GAMME      ga
   WHERE  ex.CodeP   = pr.CodeP
   AND    pr.CodeGEN = ge.CodeGEN
   AND    ge.CodeFAB = fa.CodeFAB
   AND    pr.CodeG   = ga.CodeG;

ALTER TABLE EXEMPLAIRE_MD ADD CONSTRAINT pk_exemplaire_md PRIMARY KEY (CodeExemplaire);

CREATE DIMENSION EXEMPLAIRE_MD_DIM
   LEVEL CodeExemplaire IS (EXEMPLAIRE_MD.CodeExemplaire)
   LEVEL CodeProduit    IS (EXEMPLAIRE_MD.CodeProduit)
   LEVEL CodeGeneration IS (EXEMPLAIRE_MD.CodeGeneration)
   LEVEL CodeFabricant  IS (EXEMPLAIRE_MD.CodeFabricant)
   LEVEL PaysFabricant  IS (EXEMPLAIRE_MD.PaysFabricant)
   LEVEL MarqueProduit  IS (EXEMPLAIRE_MD.MarqueProduit)
   LEVEL CodeGamme      IS (EXEMPLAIRE_MD.CodeGamme)
   LEVEL SecteurProduit IS (EXEMPLAIRE_MD.SecteurProduit)
HIERARCHY H_GENERATION (CodeExemplaire CHILD OF CodeProduit CHILD OF CodeGeneration
                        CHILD OF CodeFabricant CHILD OF PaysFabricant)
HIERARCHY H_MAR   (CodeExemplaire CHILD OF CodeProduit CHILD OF MarqueProduit)
HIERARCHY H_GAMME (CodeExemplaire CHILD OF CodeProduit CHILD OF CodeGamme
                   CHILD OF SecteurProduit)
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD.NumeroSerieEXemplaire
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD.DateMiseServiceEXemplaire
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD.DateReformeEXemplaire
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD.NomProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD.DescriptifProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD.PoidsKgProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD.AutonomieKilometreProduit
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD.NomGeneration
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD.DateSortieGeneration
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD.DateArretGeneration
ATTRIBUTE CodeFabricant  DETERMINES EXEMPLAIRE_MD.NomFabricant
ATTRIBUTE CodeGamme      DETERMINES EXEMPLAIRE_MD.NomGamme;


-- =====================================================================
-- 3) DIMENSION EMPLOYE_MD  (service / societe ACTUELS de l'employe)
--    H_France      : CodeEmploye -> CodeService -> CodeSociete -> CodeVille
--                    -> CodeDepartement -> CodeRegion -> CodePays
--    H_Allemagne   : CodeEmploye -> CodeService -> CodeSociete -> CodeGeminede
--                    -> CodeKreis -> CodeRegion -> CodePays
--    H_District    : ... -> CodeGeminede -> CodeKreis -> CodeDistrict -> CodeRegion -> CodePays
--    H_Type_Societe: CodeEmploye -> CodeService -> CodeSociete -> CodeTy
--    H_Categorie   : CodeEmploye -> CodeCategorie -> SuperCategorie
--  Hierarchies incompletes : societe francaise -> CodeGeminede/CodeKreis/CodeDistrict NULL ;
--  societe allemande -> CodeVille/CodeDepartement NULL ; Kreis sans District -> NULL.
--  CodeRegion = REGION (France) ou LAND (Allemagne).
--  Geographie : jointures de ZONE_GEO sur elle-meme (z0 = zone de la societe,
--  z1 = parent de z0, z2 = parent de z1, z3 = parent de z2) ; le niveau (NiveauZG) decide
--  de la colonne a renseigner ; une chaine absente donne NULL.
-- =====================================================================
CREATE MATERIALIZED VIEW EMPLOYE_MD
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
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.CodeZG END AS CodeVille,
          CASE WHEN z0.NiveauZG = 'COMMUNE'     THEN z0.NomZG  END AS NomVille,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.CodeZG END AS CodeDepartement,
          CASE WHEN z1.NiveauZG = 'DEPARTEMENT' THEN z1.NomZG  END AS NomDepartement,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.CodeZG END AS CodeGeminede,
          CASE WHEN z0.NiveauZG = 'GEMEINDE'    THEN z0.NomZG  END AS NomGemiende,
          CASE WHEN z1.NiveauZG = 'KREIS'       THEN z1.CodeZG END AS CodeKreis,
          CASE WHEN z1.NiveauZG = 'KREIS'       THEN z1.NomZG  END AS NomKreis,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.CodeZG END AS CodeDistrict,
          CASE WHEN z2.NiveauZG = 'DISTRICT'    THEN z2.NomZG  END AS NomDistrict,
          CASE WHEN z2.NiveauZG IN ('REGION','LAND') THEN z2.CodeZG
               WHEN z3.NiveauZG = 'LAND'               THEN z3.CodeZG END AS CodeRegion,
          CASE WHEN z2.NiveauZG IN ('REGION','LAND') THEN z2.NomZG
               WHEN z3.NiveauZG = 'LAND'               THEN z3.NomZG END AS NomRegion,
          pa.CodePays                             AS CodePays,
          pa.NomPays                              AS NomPays,
          pa.TauxTVA                              AS TauxTVA
   FROM   EMPLOYE e
          JOIN SERVICE      se ON se.CodeSE   = e.CodeSE
          JOIN SOCIETE      so ON so.CodeSOC  = se.CodeSOC
          JOIN CATEGORIE    ca ON ca.CodeCAT  = e.CodeCAT
          JOIN ZONE_GEO     z0 ON z0.CodeZG   = so.CodeZG                  -- commune (FR) ou Gemeinde (DE)
          JOIN PAYS         pa ON pa.CodePays = z0.CodePays
          LEFT JOIN TYPE_SOCIETE ty ON ty.CodeTy = so.CodeTy
          LEFT JOIN ZONE_GEO z1 ON z1.CodeZG = z0.CodeZG_zone_englobante  -- departement (FR) ou Kreis (DE)
          LEFT JOIN ZONE_GEO z2 ON z2.CodeZG = z1.CodeZG_zone_englobante  -- region (FR) ; district ou Land (DE)
          LEFT JOIN ZONE_GEO z3 ON z3.CodeZG = z2.CodeZG_zone_englobante; -- Land (DE) quand z2 est un district

ALTER TABLE EMPLOYE_MD ADD CONSTRAINT pk_employe_md PRIMARY KEY (CodeEmploye);

CREATE DIMENSION EMPLOYE_MD_DIM
   LEVEL CodeEmploye    IS (EMPLOYE_MD.CodeEmploye)
   LEVEL CodeService    IS (EMPLOYE_MD.CodeService)
   LEVEL CodeSociete    IS (EMPLOYE_MD.CodeSociete)
   LEVEL CodeVille      IS (EMPLOYE_MD.CodeVille)
   LEVEL CodeDepartement IS (EMPLOYE_MD.CodeDepartement)
   LEVEL CodeGeminede   IS (EMPLOYE_MD.CodeGeminede)
   LEVEL CodeKreis      IS (EMPLOYE_MD.CodeKreis)
   LEVEL CodeDistrict   IS (EMPLOYE_MD.CodeDistrict)
   LEVEL CodeRegion     IS (EMPLOYE_MD.CodeRegion)
   LEVEL CodePays       IS (EMPLOYE_MD.CodePays)
   LEVEL CodeTy         IS (EMPLOYE_MD.CodeTy)
   LEVEL CodeCategorie  IS (EMPLOYE_MD.CodeCategorie)
   LEVEL SuperCategorie IS (EMPLOYE_MD.SuperCategorie)
HIERARCHY H_France (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                    CHILD OF CodeVille CHILD OF CodeDepartement CHILD OF CodeRegion
                    CHILD OF CodePays)
HIERARCHY H_Allemagne (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                       CHILD OF CodeGeminede CHILD OF CodeKreis CHILD OF CodeRegion
                       CHILD OF CodePays)
HIERARCHY H_District (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                      CHILD OF CodeGeminede CHILD OF CodeKreis CHILD OF CodeDistrict
                      CHILD OF CodeRegion CHILD OF CodePays)
HIERARCHY H_Type_Societe (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                          CHILD OF CodeTy)
HIERARCHY H_Categorie (CodeEmploye CHILD OF CodeCategorie CHILD OF SuperCategorie)
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD.NomEmploye
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD.PrenomEmploye
ATTRIBUTE CodeService     DETERMINES EMPLOYE_MD.NomService
ATTRIBUTE CodeSociete     DETERMINES EMPLOYE_MD.NomSociete
ATTRIBUTE CodeVille       DETERMINES EMPLOYE_MD.NomVille
ATTRIBUTE CodeDepartement DETERMINES EMPLOYE_MD.NomDepartement
ATTRIBUTE CodeGeminede    DETERMINES EMPLOYE_MD.NomGemiende
ATTRIBUTE CodeKreis       DETERMINES EMPLOYE_MD.NomKreis
ATTRIBUTE CodeDistrict    DETERMINES EMPLOYE_MD.NomDistrict
ATTRIBUTE CodeRegion      DETERMINES EMPLOYE_MD.NomRegion
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD.NomPays
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD.TauxTVA
ATTRIBUTE CodeTy          DETERMINES EMPLOYE_MD.LibelleTypeSoc
ATTRIBUTE CodeCategorie   DETERMINES EMPLOYE_MD.NomCategorie;


-- =====================================================================
-- 4) FAIT LOCATION_MD  (grain : une location = CodeEmploye x CodeExemplaire x DateJ)
--    Duree_Location_MD            = SUM(Louer.Duree_Loc)
--    Montant_Location_MD          = SUM(Duree_Loc * Prix_loc_jour), ramene en HT :
--                                   / (1 + TauxTVA) si Tarifer.ModePrix = 'TTC'
--    Montant_Location_ReelPaye_MD = SUM(Montant HT * (1 - PctReduc_Loc))
--                                   (0 si aucune reduction trouvee)
--  Les SUM suivent le dictionnaire de mesures ; comme LOUER a pour cle
--  (CodeE, CodeEX, DateL), chaque groupe ne contient qu'une location.
--  Tarif     : pays de la societe de l'employe, valide a la date de debut de location.
--  Reduction : (categorie de l'employe, gamme du produit, annee de debut).
--  Le fait est construit depuis l'ED (pas depuis les dimensions) : les MV
--  de dimensions et de fait sont independantes les unes des autres.
-- =====================================================================
CREATE MATERIALIZED VIEW LOCATION_MD
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT l.CodeE   AS CodeEmploye,
          l.CodeEX  AS CodeExemplaire,
          l.DateL   AS DateJ,
          SUM(l.Duree_Loc) AS Duree_Location_MD,
          ROUND(SUM(CASE WHEN t.ModePrix = 'TTC'
                         THEN l.Duree_Loc * t.Prix_loc_jour / (1 + pa.TauxTVA)
                         ELSE l.Duree_Loc * t.Prix_loc_jour
                    END), 2) AS Montant_Location_MD,
          ROUND(SUM(CASE WHEN t.ModePrix = 'TTC'
                         THEN l.Duree_Loc * t.Prix_loc_jour / (1 + pa.TauxTVA)
                         ELSE l.Duree_Loc * t.Prix_loc_jour
                    END * (1 - NVL(r.PctReduc_Loc, 0))), 2) AS Montant_Location_ReelPaye_MD
   FROM   LOUER l
          JOIN EMPLOYE    e  ON e.CodeE    = l.CodeE
          JOIN SERVICE    se ON se.CodeSE  = e.CodeSE
          JOIN SOCIETE    so ON so.CodeSOC = se.CodeSOC
          JOIN ZONE_GEO   zg ON zg.CodeZG  = so.CodeZG
          JOIN PAYS       pa ON pa.CodePays = zg.CodePays
          JOIN EXEMPLAIRE ex ON ex.CodeEX  = l.CodeEX
          JOIN PRODUIT    pr ON pr.CodeP   = ex.CodeP
          LEFT JOIN TARIFER t
                 ON t.CodeP    = ex.CodeP
                AND t.CodePays = pa.CodePays
                AND t.DateDebutTarif <= l.DateL
                AND (t.DateFinTarif IS NULL OR t.DateFinTarif >= l.DateL)
          LEFT JOIN REDUCTION r
                 ON r.CodeCAT = e.CodeCAT
                AND r.CodeG   = pr.CodeG
                AND r.Annee   = EXTRACT(YEAR FROM l.DateL)
   GROUP BY l.CodeE, l.CodeEX, l.DateL;

-- Cle primaire : concatenation des cles etrangeres
ALTER TABLE LOCATION_MD ADD CONSTRAINT pk_location_md
   PRIMARY KEY (CodeEmploye, CodeExemplaire, DateJ);

-- Cles etrangeres : liaisons avec les dimensions
ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_employe
   FOREIGN KEY (CodeEmploye)    REFERENCES EMPLOYE_MD(CodeEmploye);
ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_exemplaire
   FOREIGN KEY (CodeExemplaire) REFERENCES EXEMPLAIRE_MD(CodeExemplaire);
ALTER TABLE LOCATION_MD ADD CONSTRAINT fk_location_temps
   FOREIGN KEY (DateJ)          REFERENCES TEMPS_MD(DateJ);

-- NOT NULL sur les cles etrangeres. Le cours ecrit ADD CONSTRAINT nn_... NOT NULL (col),
-- forme qu'Oracle n'accepte pas a ma connaissance : on utilise un CHECK equivalent.
-- (Deja garanti par la cle primaire.)
ALTER TABLE LOCATION_MD ADD CONSTRAINT nn_location_employe
   CHECK (CodeEmploye IS NOT NULL);
ALTER TABLE LOCATION_MD ADD CONSTRAINT nn_location_exemplaire
   CHECK (CodeExemplaire IS NOT NULL);
ALTER TABLE LOCATION_MD ADD CONSTRAINT nn_location_temps
   CHECK (DateJ IS NOT NULL);


-- =====================================================================
-- 5) RAFRAICHISSEMENT DE LA STRUCTURE
--    Un rafraichissement complet vide les dimensions : il est impossible tant
--    que les cles etrangeres du fait sont actives (ORA-02292 / ORA-02266).
--    On les desactive, on rafraichit dimensions puis fait, puis on les reactive.
-- =====================================================================
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD DISABLE CONSTRAINT fk_location_employe';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD DISABLE CONSTRAINT fk_location_exemplaire';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD DISABLE CONSTRAINT fk_location_temps';

  DBMS_MVIEW.REFRESH('TEMPS_MD',      method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EXEMPLAIRE_MD', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EMPLOYE_MD',    method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('LOCATION_MD',   method => 'C', atomic_refresh => TRUE);

  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD ENABLE VALIDATE CONSTRAINT fk_location_employe';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD ENABLE VALIDATE CONSTRAINT fk_location_exemplaire';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD ENABLE VALIDATE CONSTRAINT fk_location_temps';
END;
/


-- =====================================================================
-- 6) CONTROLES (a lancer apres chargement)
-- =====================================================================
-- Locations de l'ED absentes du fait (jointure employe/service/societe/zone/exemplaire) :
-- SELECT (SELECT COUNT(*) FROM LOUER) - (SELECT COUNT(*) FROM LOCATION_MD) AS ecart FROM dual;

-- Locations sans tarif valide (montants NULL) :
-- SELECT COUNT(*) FROM LOCATION_MD WHERE Montant_Location_MD IS NULL;

-- Jours dont l'annee civile et l'annee ISO different (quelques jours autour du 1er janvier) :
-- SELECT DateJ, Annee, Num_Semaine, Annee_ISO FROM TEMPS_MD WHERE Annee <> Annee_ISO ORDER BY DateJ;

-- Validation des hierarchies declarees (creer d'abord DIMENSION_EXCEPTIONS avec utldim.sql) :
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('TEMPS_MD_DIM',      FALSE, TRUE, 'verif_temps');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EXEMPLAIRE_MD_DIM', FALSE, TRUE, 'verif_ex');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EMPLOYE_MD_DIM',    FALSE, TRUE, 'verif_emp');
-- SELECT * FROM DIMENSION_EXCEPTIONS;

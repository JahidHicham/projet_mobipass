-- =====================================================================
-- MobiPass - Magasin LOCATION_MD1 (R-OLAP denormalise) - 01 STRUCTURE
-- Dimensions TEMPS_MD1, EXEMPLAIRE_MD1, EMPLOYE_MD1 + fait LOCATION_MD1
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
--   * TypeKreis / TypeLand : niveaux de hierarchie (H_Type_Kreis, H_Type_Land). TypeKreis vient du
--     NiveauZG du Kreis (LANDKREIS / KREISFREIE STADT, colonne TypeKreise du fichier source) ;
--     TypeLand est calcule ici ('Stadtstaat' pour Berlin, Hamburg, Bremen ; 'Flächenland' pour
--     les autres Laender).
-- =====================================================================


-- =====================================================================
-- 1) DIMENSION TEMPS_MD1
--    H_SEM  : DateJ -> Num_Semaine -> Annee_ISO   (semaine ISO 8601, lundi-dimanche)
--    H_MOIS : DateJ -> Num_Mois    -> Annee       (annee civile)
-- =====================================================================
CREATE MATERIALIZED VIEW TEMPS_MD1
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

ALTER TABLE TEMPS_MD1 ADD CONSTRAINT pk_temps_md1 PRIMARY KEY (DateJ);

CREATE DIMENSION TEMPS_DIM1
   LEVEL DateJ       IS (TEMPS_MD1.DateJ)
   LEVEL Num_Semaine IS (TEMPS_MD1.Num_Semaine)
   LEVEL Annee_ISO   IS (TEMPS_MD1.Annee_ISO)
   LEVEL Num_Mois    IS (TEMPS_MD1.Num_Mois)
   LEVEL Annee       IS (TEMPS_MD1.Annee)
HIERARCHY H_SEM  (DateJ CHILD OF Num_Semaine CHILD OF Annee_ISO)
HIERARCHY H_MOIS (DateJ CHILD OF Num_Mois    CHILD OF Annee)
ATTRIBUTE Num_Mois DETERMINES TEMPS_MD1.LibMois;


-- =====================================================================
-- 2) DIMENSION EXEMPLAIRE_MD1
--    H_GENERATION : CodeExemplaire -> CodeProduit -> CodeGeneration
--                   -> CodeFabricant -> PaysFabricant
--    H_MAR        : CodeExemplaire -> CodeProduit -> MarqueProduit
--    H_GAMME      : CodeExemplaire -> CodeProduit -> CodeGamme -> SecteurProduit
-- =====================================================================
CREATE MATERIALIZED VIEW EXEMPLAIRE_MD1
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

ALTER TABLE EXEMPLAIRE_MD1 ADD CONSTRAINT pk_exemplaire_md1 PRIMARY KEY (CodeExemplaire);

CREATE DIMENSION EXEMPLAIRE_DIM1
   LEVEL CodeExemplaire IS (EXEMPLAIRE_MD1.CodeExemplaire)
   LEVEL CodeProduit    IS (EXEMPLAIRE_MD1.CodeProduit)
   LEVEL CodeGeneration IS (EXEMPLAIRE_MD1.CodeGeneration)
   LEVEL CodeFabricant  IS (EXEMPLAIRE_MD1.CodeFabricant)
   LEVEL PaysFabricant  IS (EXEMPLAIRE_MD1.PaysFabricant)
   LEVEL MarqueProduit  IS (EXEMPLAIRE_MD1.MarqueProduit)
   LEVEL CodeGamme      IS (EXEMPLAIRE_MD1.CodeGamme)
   LEVEL SecteurProduit IS (EXEMPLAIRE_MD1.SecteurProduit)
HIERARCHY H_GENERATION (CodeExemplaire CHILD OF CodeProduit CHILD OF CodeGeneration
                        CHILD OF CodeFabricant CHILD OF PaysFabricant)
HIERARCHY H_MAR   (CodeExemplaire CHILD OF CodeProduit CHILD OF MarqueProduit)
HIERARCHY H_GAMME (CodeExemplaire CHILD OF CodeProduit CHILD OF CodeGamme
                   CHILD OF SecteurProduit)
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD1.NumeroSerieEXemplaire
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD1.DateMiseServiceEXemplaire
ATTRIBUTE CodeExemplaire DETERMINES EXEMPLAIRE_MD1.DateReformeEXemplaire
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD1.NomProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD1.DescriptifProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD1.PoidsKgProduit
ATTRIBUTE CodeProduit DETERMINES EXEMPLAIRE_MD1.AutonomieKilometreProduit
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD1.NomGeneration
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD1.DateSortieGeneration
ATTRIBUTE CodeGeneration DETERMINES EXEMPLAIRE_MD1.DateArretGeneration
ATTRIBUTE CodeFabricant  DETERMINES EXEMPLAIRE_MD1.NomFabricant
ATTRIBUTE CodeGamme      DETERMINES EXEMPLAIRE_MD1.NomGamme;


-- =====================================================================
-- 3) DIMENSION EMPLOYE_MD1  (service / societe ACTUELS de l'employe)
--    H_France      : CodeEmploye -> CodeService -> CodeSociete -> CodeVille
--                    -> CodeDepartement -> CodeRegion -> CodePays
--    H_Allemagne   : CodeEmploye -> CodeService -> CodeSociete -> CodeGemeinde
--                    -> CodeKreis -> CodeLand -> CodePays
--    H_District    : ... -> CodeGemeinde -> CodeKreis -> CodeDistrict -> CodeLand -> CodePays
--    H_Type_Kreis  : ... -> CodeGemeinde -> CodeKreis -> TypeKreis
--    H_Type_Land   : ... -> CodeGemeinde -> CodeKreis -> CodeLand -> TypeLand
--    H_Type_Societe: CodeEmploye -> CodeService -> CodeSociete -> CodeTy
--    H_Categorie   : CodeEmploye -> CodeCategorie -> SuperCategorie
--  Hierarchies incompletes : societe francaise -> CodeGemeinde/CodeKreis/CodeDistrict/CodeLand NULL ;
--  societe allemande -> CodeVille/CodeDepartement/CodeRegion NULL ; Kreis sans District -> NULL.
--  CodeRegion = region francaise (NiveauZG 'REGION') ; CodeLand = Land allemand (NiveauZG 'LAND').
--  Les villes-Etats (Berlin, Hamburg, Bremen) sont des Laender : Gemeinde -> Kreis -> Land, sans district.
--  Geographie : jointures de ZONE_GEO sur elle-meme (z0 = zone de la societe,
--  z1 = parent de z0, z2 = parent de z1, z3 = parent de z2) ; le niveau (NiveauZG) decide
--  de la colonne a renseigner ; une chaine absente donne NULL.
-- =====================================================================
CREATE MATERIALIZED VIEW EMPLOYE_MD1
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
          CASE WHEN z0.NiveauZG = 'GEMEINDEN'    THEN z0.CodeZG END AS CodeGemeinde,
          CASE WHEN z0.NiveauZG = 'GEMEINDEN'    THEN z0.NomZG  END AS NomGemeinde,
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
          LEFT JOIN TYPE_SOCIETE ty ON ty.CodeTy = so.CodeTy
          LEFT JOIN ZONE_GEO z1 ON z1.CodeZG = z0.CodeZG_zone_englobante  -- departement (FR) ou Kreis (DE)
          LEFT JOIN ZONE_GEO z2 ON z2.CodeZG = z1.CodeZG_zone_englobante  -- region (FR) ; district ou Land (DE)
          LEFT JOIN ZONE_GEO z3 ON z3.CodeZG = z2.CodeZG_zone_englobante; -- Land (DE) quand z2 est un district

ALTER TABLE EMPLOYE_MD1 ADD CONSTRAINT pk_employe_md1 PRIMARY KEY (CodeEmploye);

CREATE DIMENSION EMPLOYE_DIM1
   LEVEL CodeEmploye    IS (EMPLOYE_MD1.CodeEmploye)
   LEVEL CodeService    IS (EMPLOYE_MD1.CodeService)
   LEVEL CodeSociete    IS (EMPLOYE_MD1.CodeSociete)
   LEVEL CodeVille      IS (EMPLOYE_MD1.CodeVille)
   LEVEL CodeDepartement IS (EMPLOYE_MD1.CodeDepartement)
   LEVEL CodeGemeinde   IS (EMPLOYE_MD1.CodeGemeinde)
   LEVEL CodeKreis      IS (EMPLOYE_MD1.CodeKreis)
   LEVEL TypeKreis      IS (EMPLOYE_MD1.TypeKreis)
   LEVEL CodeDistrict   IS (EMPLOYE_MD1.CodeDistrict)
   LEVEL CodeRegion     IS (EMPLOYE_MD1.CodeRegion)
   LEVEL CodeLand       IS (EMPLOYE_MD1.CodeLand)
   LEVEL TypeLand       IS (EMPLOYE_MD1.TypeLand)
   LEVEL CodePays       IS (EMPLOYE_MD1.CodePays)
   LEVEL CodeTy         IS (EMPLOYE_MD1.CodeTy)
   LEVEL CodeCategorie  IS (EMPLOYE_MD1.CodeCategorie)
   LEVEL SuperCategorie IS (EMPLOYE_MD1.SuperCategorie)
HIERARCHY H_France (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                    CHILD OF CodeVille CHILD OF CodeDepartement CHILD OF CodeRegion
                    CHILD OF CodePays)
HIERARCHY H_Allemagne (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                       CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF CodeLand
                       CHILD OF CodePays)
HIERARCHY H_District (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                      CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF CodeDistrict
                      CHILD OF CodeLand CHILD OF CodePays)
HIERARCHY H_Type_Kreis (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                        CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF TypeKreis)
HIERARCHY H_Type_Land (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                       CHILD OF CodeGemeinde CHILD OF CodeKreis CHILD OF CodeLand
                       CHILD OF TypeLand)
HIERARCHY H_Type_Societe (CodeEmploye CHILD OF CodeService CHILD OF CodeSociete
                          CHILD OF CodeTy)
HIERARCHY H_Categorie (CodeEmploye CHILD OF CodeCategorie CHILD OF SuperCategorie)
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD1.NomEmploye
ATTRIBUTE CodeEmploye DETERMINES EMPLOYE_MD1.PrenomEmploye
ATTRIBUTE CodeService     DETERMINES EMPLOYE_MD1.NomService
ATTRIBUTE CodeSociete     DETERMINES EMPLOYE_MD1.NomSociete
ATTRIBUTE CodeVille       DETERMINES EMPLOYE_MD1.NomVille
ATTRIBUTE CodeDepartement DETERMINES EMPLOYE_MD1.NomDepartement
ATTRIBUTE CodeGemeinde    DETERMINES EMPLOYE_MD1.NomGemeinde
ATTRIBUTE CodeKreis       DETERMINES EMPLOYE_MD1.NomKreis
ATTRIBUTE CodeDistrict    DETERMINES EMPLOYE_MD1.NomDistrict
ATTRIBUTE CodeRegion      DETERMINES EMPLOYE_MD1.NomRegion
ATTRIBUTE CodeLand        DETERMINES EMPLOYE_MD1.NomLand
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD1.NomPays
ATTRIBUTE CodePays DETERMINES EMPLOYE_MD1.TauxTVA
ATTRIBUTE CodeTy          DETERMINES EMPLOYE_MD1.LibelleTypeSoc
ATTRIBUTE CodeCategorie   DETERMINES EMPLOYE_MD1.NomCategorie;


-- =====================================================================
-- 4) FAIT LOCATION_MD1  (grain : une location = CodeEmploye x CodeExemplaire x DateJ)
--    Duree_Location_MD            = SUM(Louer.Duree_Loc)
--    Montant_Location_MD          = SUM(Duree_Loc * Prix_loc_jour), ramene en TTC :
--                                   * (1 + TauxTVA) si Tarifer.ModePrix = 'HT' (tarifs allemands)
--                                   (les tarifs francais sont deja en TTC)
--    Montant_Location_ReelPaye_MD = SUM(Montant TTC * (1 - PctReduc_Loc))
--                                   (0 si aucune reduction trouvee)
--  Les SUM suivent le dictionnaire de mesures ; comme LOUER a pour cle
--  (CodeE, CodeEX, DateL), chaque groupe ne contient qu'une location.
--  Tarif     : pays de la societe de l'employe, valide a la date de debut de location.
--  Reduction : (categorie de l'employe, gamme du produit, annee de debut).
--  Le fait est construit depuis l'ED (pas depuis les dimensions) : les MV
--  de dimensions et de fait sont independantes les unes des autres.
-- =====================================================================
CREATE MATERIALIZED VIEW LOCATION_MD1
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT l.CodeE   AS CodeEmploye,
          l.CodeEX  AS CodeExemplaire,
          l.DateL   AS DateJ,
          SUM(l.Duree_Loc) AS Duree_Location_MD,
          ROUND(SUM(CASE WHEN t.ModePrix = 'HT'
                         THEN l.Duree_Loc * t.Prix_loc_jour * (1 + pa.TauxTVA)
                         ELSE l.Duree_Loc * t.Prix_loc_jour
                    END), 2) AS Montant_Location_MD,
          ROUND(SUM(CASE WHEN t.ModePrix = 'HT'
                         THEN l.Duree_Loc * t.Prix_loc_jour * (1 + pa.TauxTVA)
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
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT pk_location_md1
   PRIMARY KEY (CodeEmploye, CodeExemplaire, DateJ);

-- Cles etrangeres : liaisons avec les dimensions
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT fk_location_employe_md1
   FOREIGN KEY (CodeEmploye)    REFERENCES EMPLOYE_MD1(CodeEmploye);
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT fk_location_exemplaire_md1
   FOREIGN KEY (CodeExemplaire) REFERENCES EXEMPLAIRE_MD1(CodeExemplaire);
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT fk_location_temps_md1
   FOREIGN KEY (DateJ)          REFERENCES TEMPS_MD1(DateJ);

-- NOT NULL sur les cles etrangeres. Le cours ecrit ADD CONSTRAINT nn_... NOT NULL (col),
-- forme qu'Oracle n'accepte pas a ma connaissance : on utilise un CHECK equivalent.
-- (Deja garanti par la cle primaire.)
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT nn_location_employe_md1
   CHECK (CodeEmploye IS NOT NULL);
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT nn_location_exemplaire_md1
   CHECK (CodeExemplaire IS NOT NULL);
ALTER TABLE LOCATION_MD1 ADD CONSTRAINT nn_location_temps_md1
   CHECK (DateJ IS NOT NULL);


-- =====================================================================
-- 5) RAFRAICHISSEMENT DE LA STRUCTURE
--    Un rafraichissement complet vide les dimensions : il est impossible tant
--    que les cles etrangeres du fait sont actives (ORA-02292 / ORA-02266).
--    On les desactive, on rafraichit dimensions puis fait, puis on les reactive.
-- =====================================================================
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 DISABLE CONSTRAINT fk_location_employe_md1';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 DISABLE CONSTRAINT fk_location_exemplaire_md1';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 DISABLE CONSTRAINT fk_location_temps_md1';

  DBMS_MVIEW.REFRESH('TEMPS_MD1',      method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EXEMPLAIRE_MD1', method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('EMPLOYE_MD1',    method => 'C', atomic_refresh => TRUE);
  DBMS_MVIEW.REFRESH('LOCATION_MD1',   method => 'C', atomic_refresh => TRUE);

  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 ENABLE VALIDATE CONSTRAINT fk_location_employe_md1';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 ENABLE VALIDATE CONSTRAINT fk_location_exemplaire_md1';
  EXECUTE IMMEDIATE 'ALTER TABLE LOCATION_MD1 ENABLE VALIDATE CONSTRAINT fk_location_temps_md1';
END;
/


-- =====================================================================
-- 6) CONTROLES (a lancer apres chargement)
-- =====================================================================
-- Locations de l'ED absentes du fait (jointure employe/service/societe/zone/exemplaire) :
-- SELECT (SELECT COUNT(*) FROM LOUER) - (SELECT COUNT(*) FROM LOCATION_MD1) AS ecart FROM dual;

-- Locations sans tarif valide (montants NULL) :
-- SELECT COUNT(*) FROM LOCATION_MD1 WHERE Montant_Location_MD IS NULL;

-- Jours dont l'annee civile et l'annee ISO different (quelques jours autour du 1er janvier) :
-- SELECT DateJ, Annee, Num_Semaine, Annee_ISO FROM TEMPS_MD1 WHERE Annee <> Annee_ISO ORDER BY DateJ;

-- Chaque employe doit avoir exactement UN des deux : region (France) ou Land (Allemagne) :
-- SELECT COUNT(*) FROM EMPLOYE_MD1
--  WHERE (CodeRegion IS NULL AND CodeLand IS NULL) OR (CodeRegion IS NOT NULL AND CodeLand IS NOT NULL);   -- doit renvoyer 0

-- Validation des hierarchies declarees (creer d'abord DIMENSION_EXCEPTIONS avec utldim.sql) :
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('TEMPS_DIM1',      FALSE, TRUE, 'verif_temps');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EXEMPLAIRE_DIM1', FALSE, TRUE, 'verif_ex');
-- EXEC DBMS_DIMENSION.VALIDATE_DIMENSION('EMPLOYE_DIM1',    FALSE, TRUE, 'verif_emp');
-- SELECT * FROM DIMENSION_EXCEPTIONS;

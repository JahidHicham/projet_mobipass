-- MobiPass - Projet 2 : entrepôt du cube « Locations » sous SQL Server (schéma dw)
-- Schéma en étoile issu de la conception du projet 1 (docs/Location_MD.json) : dimensions DIM_TEMPS,
--   DIM_EMPLOYE, DIM_PRODUIT, DIM_EXEMPLAIRE (clés de substitution) et un seul fait, FAIT_LOCATION.
-- Séquence S1 (« quand et où les employés ne trouvent pas de produit ») : le produit n'est pas disponible quand
--   tous ses exemplaires sont déjà loués ; le cube le déduit des locations (taux d'occupation, jours de rupture).
-- Ajouts par rapport au projet 1 :
--   * le produit est rangé dans sa propre table, reliée à l'exemplaire (flocon) ; l'exemplaire garde son agence ;
--   * domaine NAF/WZ de la société (séquence S2) ; géographies française et allemande séparées, comme dans la conception ;
-- Contraintes du dictionnaire de données du sujet initial : durée > 0, pourcentage de réduction dans ]0 ; 1],
--   dates cohérentes, aucune location au prix public, pas de chevauchement d'un exemplaire (CHECK, UNIQUE et trigger).
-- Grain du fait Location : un jour loué (comme LOCATION_MD1 du projet 1), voir plus bas.
-- Clés de substitution : numéros attribués au chargement (03_chargement_dw.sql), indépendants des codes sources ;
--   pour le temps, la date au format AAAAMMJJ. Montants en euros TTC (prix allemands HT + TVA allemande).
-- Avant d'exécuter : choisir la base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro
--   étudiant à la fac). Relançable : supprime puis recrée les tables (les faits avant les dimensions).

IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    RAISERROR(N'Choisissez d''abord votre base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro étudiant à la fac), puis relancez.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO
IF SCHEMA_ID(N'dw') IS NULL
    EXEC (N'CREATE SCHEMA dw');
GO

DROP TABLE IF EXISTS dw.FAIT_RESERVATION;   -- table d'une ancienne version (supprimée à la demande du prof)
DROP TABLE IF EXISTS dw.FAIT_LOCATION, dw.DIM_EXEMPLAIRE, dw.DIM_PRODUIT,
                     dw.DIM_EMPLOYE, dw.DIM_TEMPS;
DROP TABLE IF EXISTS dw.JOURNAL_QUALITE;   -- table d'une ancienne version (plus de données à nettoyer)
GO

-- Dimension Temps : une ligne par jour ; clé de substitution = date au format AAAAMMJJ.
-- Semaine ISO 8601 (lundi-dimanche) : une semaine à cheval sur deux années appartient à l'année
-- qui contient son jeudi (AnneeISO). Ex. : le lundi 30/12/2024 est dans la semaine 1 de 2025.
CREATE TABLE dw.DIM_TEMPS(
   CleTemps        INT,
   DateJour        DATE         NOT NULL,
   NumJourSemaine  TINYINT      NOT NULL,   -- 1 = lundi ... 7 = dimanche
   LibJour         NVARCHAR(10) NOT NULL,   -- lundi ... dimanche
   EstWeekEnd      BIT          NOT NULL,
   NumSemaineISO   TINYINT      NOT NULL,
   AnneeISO        SMALLINT     NOT NULL,
   CleSemaine      INT          NOT NULL,   -- AnneeISO * 100 + NumSemaineISO, ex. 202501
   LibSemaine      VARCHAR(8)   NOT NULL,   -- ex. 2025-S01
   NumMois         TINYINT      NOT NULL,
   LibMois         NVARCHAR(10) NOT NULL,   -- janvier ... décembre
   CleMois         INT          NOT NULL,   -- Annee * 100 + NumMois, ex. 202504
   LibMoisAnnee    NVARCHAR(20) NOT NULL,   -- ex. avril 2025
   NumTrimestre    TINYINT      NOT NULL,
   CleTrimestre    INT          NOT NULL,   -- Annee * 10 + NumTrimestre, ex. 20252
   LibTrimestre    VARCHAR(7)   NOT NULL,   -- ex. T2 2025
   Saison          NVARCHAR(10) NOT NULL,   -- printemps (mars-mai), été (juin-août), automne (sept.-nov.), hiver
   Annee           SMALLINT     NOT NULL,
   CONSTRAINT pk_dim_temps PRIMARY KEY(CleTemps),
   CONSTRAINT uq_dim_temps_date UNIQUE(DateJour),
   CONSTRAINT ck_dim_temps_cle CHECK(CleTemps = YEAR(DateJour) * 10000 + MONTH(DateJour) * 100 + DAY(DateJour)),
   CONSTRAINT ck_dim_temps_jour CHECK(NumJourSemaine BETWEEN 1 AND 7),
   CONSTRAINT ck_dim_temps_semaine CHECK(NumSemaineISO BETWEEN 1 AND 53),
   CONSTRAINT ck_dim_temps_mois CHECK(NumMois BETWEEN 1 AND 12),
   CONSTRAINT ck_dim_temps_trimestre CHECK(NumTrimestre BETWEEN 1 AND 4)
);
GO

-- Dimension Employé : mêmes attributs et mêmes noms que la dimension Employe_MD de la conception du projet 1
-- (docs/Location_MD.json), plus le domaine NAF/WZ de la société (ajout pour la séquence S2).
-- Hiérarchies de la conception : H_France (Employé > Service > Société > Ville > Département > Région > Pays),
--   H_Allemagne (... Société > Gemeinde > Kreis > Land > Pays), H_District (... Kreis > District > Land),
--   H_Type_Kreis (... Kreis > TypeKreis), H_Type_Land (... Land > TypeLand), H_Categorie (Employé > Catégorie >
--   SuperCatégorie), H_Type_Societe (... Société > Type). Ajout : Société > Domaine > Division.
-- Les niveaux de l'autre pays valent « Sans objet » (code SO-FR ou SO-DE) au lieu de NULL ; un Kreis sans district
--   a le district « Sans district (Land) » (code du Land + -SD) : chaque hiérarchie reste stricte pour le cube.
CREATE TABLE dw.DIM_EMPLOYE(
   CleEmploye       INT,
   CodeEmploye      INT           NOT NULL,   -- code de l'employé dans les données sources
   NomEmploye       NVARCHAR(50)  NOT NULL,
   PrenomEmploye    NVARCHAR(50)  NOT NULL,
   CodeCategorie    CHAR(5)       NOT NULL,   -- profil de trajet (annexe 2 du sujet initial), ex. TC-01
   NomCategorie     NVARCHAR(100) NOT NULL,
   SuperCategorie   NVARCHAR(100) NOT NULL,   -- classe de trajet : court, moyen, long ou intermodal
   CodeService      INT           NOT NULL,
   NomService       NVARCHAR(50)  NOT NULL,
   CodeSociete      VARCHAR(14)   NOT NULL,   -- SIREN (FR) ou USt-IdNr (DE)
   NomSociete       NVARCHAR(100) NOT NULL,
   CodeTy           VARCHAR(5)    NOT NULL,   -- type de société : MICRO, PME, ETI, GE
   LibelleTypeSoc   NVARCHAR(60)  NOT NULL,
   CodeDomaine      VARCHAR(7)    NOT NULL,   -- sous-classe NAF (FR) ou équivalent WZ (DE), ex. 62.01Z
   LibDomaine       NVARCHAR(150) NOT NULL,
   CodeDivision     VARCHAR(2)    NOT NULL,   -- division NAF/WZ, ex. 62
   LibDivision      NVARCHAR(150) NOT NULL,
   CodeVille        VARCHAR(10)   NOT NULL,   -- France : commune
   NomVille         NVARCHAR(100) NOT NULL,
   CodeDepartement  VARCHAR(10)   NOT NULL,   -- France : département
   NomDepartement   NVARCHAR(100) NOT NULL,
   CodeRegion       VARCHAR(10)   NOT NULL,   -- France : région
   NomRegion        NVARCHAR(100) NOT NULL,
   CodeGemeinde     VARCHAR(10)   NOT NULL,   -- Allemagne : Gemeinde
   NomGemeinde      NVARCHAR(100) NOT NULL,
   CodeKreis        VARCHAR(10)   NOT NULL,   -- Allemagne : Kreis
   NomKreis         NVARCHAR(100) NOT NULL,
   TypeKreis        NVARCHAR(30)  NOT NULL,   -- Landkreis ou Kreisfreie Stadt
   CodeDistrict     VARCHAR(10)   NOT NULL,   -- Allemagne : Regierungsbezirk
   NomDistrict      NVARCHAR(100) NOT NULL,
   CodeLand         VARCHAR(10)   NOT NULL,   -- Allemagne : Land
   NomLand          NVARCHAR(100) NOT NULL,
   TypeLand         NVARCHAR(30)  NOT NULL,   -- Stadtstaat (Berlin, Hamburg, Bremen) ou Flächenland
   CodePays         CHAR(2)       NOT NULL,
   NomPays          NVARCHAR(50)  NOT NULL,
   TauxTVA          DECIMAL(4,3)  NOT NULL,
   CONSTRAINT pk_dim_employe PRIMARY KEY(CleEmploye),
   CONSTRAINT uq_dim_employe_code UNIQUE(CodeEmploye),
   CONSTRAINT ck_dim_employe_categorie CHECK(CodeCategorie LIKE '[A-Z][A-Z]-[0-9][0-9]'),
   CONSTRAINT ck_dim_employe_division CHECK(CodeDomaine LIKE CodeDivision + '%'),
   CONSTRAINT ck_dim_employe_pays CHECK(CodePays IN ('FR', 'DE')),
   CONSTRAINT ck_dim_employe_tva CHECK(TauxTVA > 0 AND TauxTVA <= 1)
);
GO

-- Dimension Produit : le produit, sa gamme et son secteur, sa génération et son fabricant.
-- Hiérarchies : Secteur > Gamme > Produit ; Pays fabricant > Fabricant > Génération > Produit ; Marque > Produit.
CREATE TABLE dw.DIM_PRODUIT(
   CleProduit            INT,
   CodeProduit           INT           NOT NULL,   -- code du produit dans les données sources
   NomProduit            NVARCHAR(50)  NOT NULL,
   MarqueProduit         NVARCHAR(50)  NOT NULL,
   DescriptifProduit     NVARCHAR(500),
   PoidsKg               DECIMAL(6,2),
   AutonomieKm           INT,
   CodeGamme             CHAR(5)       NOT NULL,
   NomGamme              NVARCHAR(50)  NOT NULL,
   Secteur               NVARCHAR(50)  NOT NULL,
   CodeGeneration        VARCHAR(10)   NOT NULL,
   NomGeneration         NVARCHAR(50)  NOT NULL,
   DateSortieGeneration  DATE          NOT NULL,
   DateArretGeneration   DATE,
   CodeFabricant         VARCHAR(10)   NOT NULL,
   NomFabricant          NVARCHAR(50)  NOT NULL,
   PaysFabricant         NVARCHAR(50)  NOT NULL,
   CONSTRAINT pk_dim_produit PRIMARY KEY(CleProduit),
   CONSTRAINT uq_dim_produit_code UNIQUE(CodeProduit),
   CONSTRAINT ck_dim_pro_generation CHECK(DateArretGeneration IS NULL OR DateArretGeneration > DateSortieGeneration),
   CONSTRAINT ck_dim_pro_poids CHECK(PoidsKg IS NULL OR PoidsKg > 0),
   CONSTRAINT ck_dim_pro_autonomie CHECK(AutonomieKm IS NULL OR AutonomieKm > 0)
);
GO

-- Dimension Exemplaire : l'exemplaire loué et son agence ; il est rattaché à son produit.
-- Hiérarchie : Pays > Agence > Exemplaire.
CREATE TABLE dw.DIM_EXEMPLAIRE(
   CleExemplaire    INT,
   CodeExemplaire   INT          NOT NULL,   -- code de l'exemplaire dans les données sources
   NumeroSerie      VARCHAR(30)  NOT NULL,
   DateMiseService  DATE         NOT NULL,
   DateReforme      DATE,
   CodeAgence       VARCHAR(10)  NOT NULL,
   NomAgence        NVARCHAR(50) NOT NULL,
   VilleAgence      NVARCHAR(50) NOT NULL,
   PaysAgence       CHAR(2)      NOT NULL,
   CleProduit       INT          NOT NULL,
   CONSTRAINT pk_dim_exemplaire PRIMARY KEY(CleExemplaire),
   CONSTRAINT uq_dim_exemplaire_code UNIQUE(CodeExemplaire),
   CONSTRAINT uq_dim_exemplaire_serie UNIQUE(NumeroSerie),
   CONSTRAINT uq_dim_exemplaire_produit UNIQUE(CleExemplaire, CleProduit),   -- garantit le bon produit dans le fait
   CONSTRAINT fk_dex_produit FOREIGN KEY(CleProduit) REFERENCES dw.DIM_PRODUIT(CleProduit),
   CONSTRAINT ck_dim_ex_reforme CHECK(DateReforme IS NULL OR DateReforme > DateMiseService),
   CONSTRAINT ck_dim_ex_pays CHECK(PaysAgence IN ('FR', 'DE'))
);
GO

-- Fait Location : une ligne par JOUR loué (comme LOCATION_MD1 du projet 1, sql/md_locations/01_Location_MD_structure.sql) :
-- une location de 5 jours donne 5 lignes. Les jours loués tombent ainsi dans le bon mois et la bonne semaine
-- (une location du 28 juin au 3 juillet compte 3 jours en juin et 3 en juillet).
-- Mesures par ligne : durée = 1 jour ; montant public = prix de location journalier TTC du tarif en vigueur au
-- début de la location ; montant payé = montant public x (1 - taux de réduction de la gamme et du profil de trajet
-- pour l'année de début). DebutLocation = 1 sur le premier jour seulement : la somme de DebutLocation compte les
-- locations, la somme de DureeLocation compte les jours loués.
CREATE TABLE dw.FAIT_LOCATION(
   CleTemps       INT           NOT NULL,   -- jour loué
   CleEmploye     INT           NOT NULL,
   CleExemplaire  INT           NOT NULL,
   CleProduit     INT           NOT NULL,   -- produit de l'exemplaire
   DureeLocation  INT           NOT NULL,   -- 1 jour par ligne
   DebutLocation  TINYINT       NOT NULL,   -- 1 = premier jour de la location, 0 = jour suivant
   TauxReduction  DECIMAL(4,3)  NOT NULL,   -- %Reduc_loc appliqué
   MontantPublic  DECIMAL(12,2) NOT NULL,   -- euros TTC, pour ce jour
   MontantPaye    DECIMAL(12,2) NOT NULL,   -- euros TTC, pour ce jour
   CONSTRAINT pk_fait_location PRIMARY KEY(CleEmploye, CleExemplaire, CleTemps),
   CONSTRAINT uq_fait_location_jour UNIQUE(CleExemplaire, CleTemps),   -- un exemplaire n'est pas loué deux fois le même jour
   CONSTRAINT fk_fl_temps FOREIGN KEY(CleTemps) REFERENCES dw.DIM_TEMPS(CleTemps),
   CONSTRAINT fk_fl_employe FOREIGN KEY(CleEmploye) REFERENCES dw.DIM_EMPLOYE(CleEmploye),
   CONSTRAINT fk_fl_exemplaire FOREIGN KEY(CleExemplaire, CleProduit) REFERENCES dw.DIM_EXEMPLAIRE(CleExemplaire, CleProduit),
   CONSTRAINT fk_fl_produit FOREIGN KEY(CleProduit) REFERENCES dw.DIM_PRODUIT(CleProduit),
   CONSTRAINT ck_fl_duree CHECK(DureeLocation = 1),
   CONSTRAINT ck_fl_debut CHECK(DebutLocation IN (0, 1)),
   CONSTRAINT ck_fl_taux CHECK(TauxReduction > 0 AND TauxReduction <= 1),
   CONSTRAINT ck_fl_montant_public CHECK(MontantPublic > 0),
   CONSTRAINT ck_fl_prix_public CHECK(MontantPaye >= 0 AND MontantPaye < MontantPublic),   -- aucune location au prix public
   CONSTRAINT ck_fl_montant_paye CHECK(ABS(MontantPaye - MontantPublic * (1 - TauxReduction)) < 0.01)
);
GO
CREATE INDEX ix_fl_temps ON dw.FAIT_LOCATION(CleTemps);
GO

-- Règles qui portent sur plusieurs tables, vérifiées à chaque insertion ou modification de locations
-- (le chevauchement de deux locations d'un même exemplaire est interdit par uq_fait_location_jour)
CREATE TRIGGER dw.trg_fait_location_controle ON dw.FAIT_LOCATION
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- dates cohérentes : location commencée dans le passé, jours loués après la mise en service
    -- et avant la réforme de l'exemplaire
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dw.DIM_TEMPS t      ON t.CleTemps = i.CleTemps
               JOIN dw.DIM_EXEMPLAIRE x ON x.CleExemplaire = i.CleExemplaire
               WHERE (i.DebutLocation = 1 AND t.DateJour >= CAST(GETDATE() AS DATE))
                  OR t.DateJour < x.DateMiseService
                  OR (x.DateReforme IS NOT NULL AND t.DateJour >= x.DateReforme))
        THROW 50001, N'Location incohérente : date future, avant la mise en service ou après la réforme de l''exemplaire.', 1;
END;
GO

-- Vérification : 5 tables, 5 clés étrangères, 1 trigger attendus
SELECT (SELECT COUNT(*) FROM sys.tables       WHERE schema_id = SCHEMA_ID(N'dw')) AS nb_tables,
       (SELECT COUNT(*) FROM sys.foreign_keys WHERE schema_id = SCHEMA_ID(N'dw')) AS nb_cles_etrangeres,
       (SELECT COUNT(*) FROM sys.triggers t JOIN sys.tables tb ON tb.object_id = t.parent_id
         WHERE tb.schema_id = SCHEMA_ID(N'dw')) AS nb_triggers;
GO
SET NOEXEC OFF;
GO

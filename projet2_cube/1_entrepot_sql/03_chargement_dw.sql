-- MobiPass - Projet 2 : chargement de l'entrepôt dw à partir des fichiers sources CSV
-- À lancer après 01_creation_dw.sql et 02_dimension_temps.sql, dans la même base (liste déroulante de SSMS).
-- Les CSV (3_donnees/csv) sont produits par 3_donnees/gen_donnees_projet2.py. Ils sont complets et cohérents
-- (consigne du prof : pas de données manquantes, seulement des phénomènes visibles dans le cube).
-- Démarche (étape 2 du sujet) :
--   1. lecture de chaque CSV dans une table temporaire (BULK INSERT) ;
--   2. chargement des dimensions (clés de substitution numérotées de 1 à n) ;
--   3. chargement du fait : les codes sont remplacés par les clés et les mesures calculées. Chaque location est
--      découpée en une ligne par jour loué (comme LOCATION_MD1 du projet 1) : durée = 1,
--      MontantPublic = prix journalier TTC, MontantPaye = MontantPublic x (1 - taux de réduction),
--      DebutLocation = 1 le premier jour ;
--   4. bilans. Les contraintes des tables (CHECK, UNIQUE, clés étrangères, trigger) refusent toute ligne
--      incohérente ; 04_controles_entrepot.sql vérifie ensuite toutes les règles.
-- Relançable : vide l'entrepôt (sauf la dimension Temps) avant de le recharger.
-- Seule ligne à adapter : @dossier. BULK INSERT lit les fichiers sur la machine du serveur SQL : sur etu-mssql3,
--   il ne voit pas les fichiers de votre PC (utiliser 03_chargement_dw_fac.sql).

IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    RAISERROR(N'Choisissez d''abord votre base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro étudiant à la fac), puis relancez.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO

SET NOCOUNT ON;
DECLARE @dossier NVARCHAR(400) = N'C:\Users\JAHID\Desktop\projet_mobipass\projet2_cube\3_donnees\csv\';

-- ============================================================ 0. on vide l'entrepôt (le fait puis les dimensions)
DELETE FROM dw.FAIT_LOCATION;
DELETE FROM dw.DIM_EXEMPLAIRE;
DELETE FROM dw.DIM_PRODUIT;
DELETE FROM dw.DIM_EMPLOYE;

-- ============================================================ 1. lecture des fichiers sources
DROP TABLE IF EXISTS #employe, #produit, #exemplaire, #location, #bilan;
CREATE TABLE #employe(CodeEmploye INT, NomEmploye NVARCHAR(50), PrenomEmploye NVARCHAR(50), CodeCategorie VARCHAR(10),
    NomCategorie NVARCHAR(100), SuperCategorie NVARCHAR(100), CodeService INT, NomService NVARCHAR(60), CodeSociete VARCHAR(14),
    NomSociete NVARCHAR(100), CodeTy VARCHAR(5), LibelleTypeSoc NVARCHAR(60), CodeDomaine VARCHAR(7), LibDomaine NVARCHAR(150),
    CodeDivision VARCHAR(2), LibDivision NVARCHAR(150), CodeVille VARCHAR(10), NomVille NVARCHAR(100), CodeDepartement VARCHAR(10),
    NomDepartement NVARCHAR(100), CodeRegion VARCHAR(10), NomRegion NVARCHAR(100), CodeGemeinde VARCHAR(10), NomGemeinde NVARCHAR(100),
    CodeKreis VARCHAR(10), NomKreis NVARCHAR(100), TypeKreis NVARCHAR(30), CodeDistrict VARCHAR(10), NomDistrict NVARCHAR(100),
    CodeLand VARCHAR(10), NomLand NVARCHAR(100), TypeLand NVARCHAR(30), CodePays CHAR(2), NomPays NVARCHAR(50), TauxTVA DECIMAL(4,3));
CREATE TABLE #produit(CodeProduit INT, NomProduit NVARCHAR(50), MarqueProduit NVARCHAR(50), DescriptifProduit NVARCHAR(500),
    PoidsKg DECIMAL(6,2), AutonomieKm INT, CodeGamme CHAR(5), NomGamme NVARCHAR(50), Secteur NVARCHAR(50),
    CodeGeneration VARCHAR(10), NomGeneration NVARCHAR(50), DateSortieGeneration DATE, DateArretGeneration DATE,
    CodeFabricant VARCHAR(10), NomFabricant NVARCHAR(50), PaysFabricant NVARCHAR(50));
CREATE TABLE #exemplaire(CodeExemplaire INT, NumeroSerie VARCHAR(30), DateMiseService DATE, DateReforme DATE,
    CodeAgence VARCHAR(10), NomAgence NVARCHAR(50), VilleAgence NVARCHAR(50), PaysAgence CHAR(2), CodeProduit INT);
CREATE TABLE #location(CodeEmploye INT, CodeExemplaire INT, DateLocation DATE, DureeLocation INT,
    PrixJourTTC DECIMAL(10,2), TauxReduction DECIMAL(9,3));

DECLARE @sql NVARCHAR(MAX), @options NVARCHAR(200) = N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK)';
SET @sql = N'BULK INSERT #employe FROM '''    + @dossier + N'employe.csv'    + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #produit FROM '''    + @dossier + N'produit.csv'    + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #exemplaire FROM ''' + @dossier + N'exemplaire.csv' + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #location FROM '''   + @dossier + N'location.csv'   + @options; EXEC (@sql);
CREATE INDEX ix_location ON #location(CodeExemplaire, DateLocation);

CREATE TABLE #bilan(Ordre INT, Fichier VARCHAR(20), LignesLues INT, LignesChargees INT);
INSERT INTO #bilan(Ordre, Fichier, LignesLues) VALUES
    (1, 'employe.csv', (SELECT COUNT(*) FROM #employe)), (2, 'produit.csv', (SELECT COUNT(*) FROM #produit)),
    (3, 'exemplaire.csv', (SELECT COUNT(*) FROM #exemplaire)), (4, 'location.csv', (SELECT COUNT(*) FROM #location));

-- ============================================================ 2. chargement des dimensions
INSERT INTO dw.DIM_PRODUIT(CleProduit, CodeProduit, NomProduit, MarqueProduit, DescriptifProduit, PoidsKg, AutonomieKm,
    CodeGamme, NomGamme, Secteur, CodeGeneration, NomGeneration, DateSortieGeneration, DateArretGeneration,
    CodeFabricant, NomFabricant, PaysFabricant)
SELECT ROW_NUMBER() OVER (ORDER BY CodeProduit), CodeProduit, NomProduit, MarqueProduit, DescriptifProduit, PoidsKg, AutonomieKm,
       CodeGamme, NomGamme, Secteur, CodeGeneration, NomGeneration, DateSortieGeneration, DateArretGeneration,
       CodeFabricant, NomFabricant, PaysFabricant
FROM #produit;

INSERT INTO dw.DIM_EMPLOYE(CleEmploye, CodeEmploye, NomEmploye, PrenomEmploye, CodeCategorie, NomCategorie, SuperCategorie,
    CodeService, NomService, CodeSociete, NomSociete, CodeTy, LibelleTypeSoc, CodeDomaine, LibDomaine, CodeDivision, LibDivision,
    CodeVille, NomVille, CodeDepartement, NomDepartement, CodeRegion, NomRegion, CodeGemeinde, NomGemeinde, CodeKreis, NomKreis,
    TypeKreis, CodeDistrict, NomDistrict, CodeLand, NomLand, TypeLand, CodePays, NomPays, TauxTVA)
SELECT ROW_NUMBER() OVER (ORDER BY CodeEmploye), CodeEmploye, NomEmploye, PrenomEmploye, CodeCategorie, NomCategorie, SuperCategorie,
       CodeService, NomService, CodeSociete, NomSociete, CodeTy, LibelleTypeSoc, CodeDomaine, LibDomaine, CodeDivision, LibDivision,
       CodeVille, NomVille, CodeDepartement, NomDepartement, CodeRegion, NomRegion, CodeGemeinde, NomGemeinde, CodeKreis, NomKreis,
       TypeKreis, CodeDistrict, NomDistrict, CodeLand, NomLand, TypeLand, CodePays, NomPays, TauxTVA
FROM #employe;

INSERT INTO dw.DIM_EXEMPLAIRE(CleExemplaire, CodeExemplaire, NumeroSerie, DateMiseService, DateReforme, CodeAgence,
    NomAgence, VilleAgence, PaysAgence, CleProduit)
SELECT ROW_NUMBER() OVER (ORDER BY x.CodeExemplaire), x.CodeExemplaire, x.NumeroSerie, x.DateMiseService, x.DateReforme,
       x.CodeAgence, x.NomAgence, x.VilleAgence, x.PaysAgence, p.CleProduit
FROM #exemplaire x
JOIN dw.DIM_PRODUIT p ON p.CodeProduit = x.CodeProduit;

-- ============================================================ 3. chargement du fait Location (codes -> clés, mesures calculées)
-- une ligne par jour loué : jours de la dimension Temps du premier au dernier jour de la location
INSERT INTO dw.FAIT_LOCATION(CleTemps, CleEmploye, CleExemplaire, CleProduit, DureeLocation, DebutLocation, TauxReduction,
    MontantPublic, MontantPaye)
SELECT t.CleTemps, e.CleEmploye, x.CleExemplaire, x.CleProduit, 1,
       CASE WHEN t.DateJour = l.DateLocation THEN 1 ELSE 0 END,
       l.TauxReduction, l.PrixJourTTC, ROUND(l.PrixJourTTC * (1 - l.TauxReduction), 2)
FROM #location l
JOIN dw.DIM_TEMPS t      ON t.DateJour >= l.DateLocation AND t.DateJour < DATEADD(DAY, l.DureeLocation, l.DateLocation)
JOIN dw.DIM_EMPLOYE e    ON e.CodeEmploye = l.CodeEmploye
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire;

-- ============================================================ 4. bilans
UPDATE #bilan SET LignesChargees = CASE Fichier
    WHEN 'employe.csv'     THEN (SELECT COUNT(*) FROM dw.DIM_EMPLOYE)
    WHEN 'produit.csv'     THEN (SELECT COUNT(*) FROM dw.DIM_PRODUIT)
    WHEN 'exemplaire.csv'  THEN (SELECT COUNT(*) FROM dw.DIM_EXEMPLAIRE)
    WHEN 'location.csv'    THEN (SELECT SUM(DebutLocation) FROM dw.FAIT_LOCATION) END;   -- locations (pas jours)

-- 1) lignes lues et chargées par fichier (écart attendu : 0)
SELECT Fichier, LignesLues, LignesChargees, LignesLues - LignesChargees AS Ecart FROM #bilan ORDER BY Ordre;

-- 2) volumes minimaux du sujet
SELECT Element, Nb, Minimum, CASE WHEN Nb >= Minimum THEN 'OK' ELSE 'INSUFFISANT' END AS Verdict
FROM (SELECT 1 AS o, N'Sociétés' AS Element, COUNT(DISTINCT CodeSociete) AS Nb, 40 AS Minimum FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 2, N'Régions (FR) et Länder (DE)', COUNT(DISTINCT CASE WHEN CodePays = 'FR' THEN CodeRegion ELSE CodeLand END), 5 FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 3, N'Employés', COUNT(*), 3000 FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 4, N'Produits', COUNT(*), 60 FROM dw.DIM_PRODUIT
      UNION ALL SELECT 5, N'Secteurs', COUNT(DISTINCT Secteur), 3 FROM dw.DIM_PRODUIT
      UNION ALL SELECT 6, N'Exemplaires', COUNT(*), 400 FROM dw.DIM_EXEMPLAIRE
      UNION ALL SELECT 7, N'Locations', SUM(DebutLocation), 60000 FROM dw.FAIT_LOCATION
      UNION ALL SELECT 8, N'Années complètes (12 mois de locations)', COUNT(*), 3
                FROM (SELECT t.Annee FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
                      GROUP BY t.Annee HAVING COUNT(DISTINCT t.NumMois) = 12) a) v
ORDER BY o;

-- 3) totaux de référence de l'entrepôt, à retrouver dans le cube après son traitement
SELECT (SELECT SUM(DebutLocation) FROM dw.FAIT_LOCATION) AS NbLocations,
       (SELECT SUM(DureeLocation) FROM dw.FAIT_LOCATION) AS DureeTotale,   -- = nombre de lignes (jours loués)
       (SELECT SUM(MontantPublic) FROM dw.FAIT_LOCATION) AS MontantPublicTotal,
       (SELECT SUM(MontantPaye) FROM dw.FAIT_LOCATION)   AS MontantPayeTotal;

DROP TABLE IF EXISTS #employe, #produit, #exemplaire, #location, #bilan;
GO
SET NOEXEC OFF;
GO

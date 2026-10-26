-- MobiPass - Projet 2 : chargement de l'entrepôt dw à partir des fichiers sources CSV, avec contrôle qualité
-- À lancer après 01_creation_dw.sql et 02_dimension_temps.sql, dans la même base (liste déroulante de SSMS).
-- Les CSV (3_donnees/csv) sont produits par 3_donnees/gen_donnees_projet2.py. Comme de vraies sources, ils
-- contiennent des données manquantes et erronées (liste exacte : 3_donnees/referentiels/anomalies_injectees.csv).
-- Démarche (étape 2 du sujet) :
--   1. lecture de chaque CSV, tel quel, dans une table temporaire (BULK INSERT) ;
--   2. contrôle qualité : doublons supprimés, libellés harmonisés, valeurs manquantes complétées, valeurs
--      erronées corrigées, lignes inutilisables rejetées ; chaque cas est noté dans dw.JOURNAL_QUALITE ;
--   3. chargement des dimensions (clés de substitution numérotées de 1 à n), puis des faits : les codes sont
--      remplacés par les clés et les mesures calculées. MontantPublic = durée x prix journalier TTC ;
--      MontantPaye = MontantPublic x (1 - taux de réduction) ; une réservation est non honorée si aucune
--      location du produit par l'employé ne commence à la date prévue.
-- Relançable : vide l'entrepôt (sauf la dimension Temps) avant de le recharger.
-- Seule ligne à adapter : @dossier. BULK INSERT lit les fichiers sur la machine du serveur SQL : sur etu-mssql3,
--   il ne voit pas les fichiers de votre PC.

IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    RAISERROR(N'Choisissez d''abord votre base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro étudiant à la fac), puis relancez.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO

SET NOCOUNT ON;
DECLARE @dossier NVARCHAR(400) = N'C:\Users\JAHID\Desktop\projet_mobipass\projet2_cube\3_donnees\csv\';

-- ============================================================ 0. on vide l'entrepôt (faits puis dimensions) et le journal
DELETE FROM dw.FAIT_RESERVATION;
DELETE FROM dw.FAIT_LOCATION;
DELETE FROM dw.DIM_EXEMPLAIRE;
DELETE FROM dw.DIM_PRODUIT;
DELETE FROM dw.DIM_EMPLOYE;
TRUNCATE TABLE dw.JOURNAL_QUALITE;

-- ============================================================ 1. lecture des fichiers sources, tels quels
DROP TABLE IF EXISTS #employe, #produit, #exemplaire, #location, #reservation, #rejet, #bilan, #prix, #taux_emp, #taux_profil;
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
CREATE TABLE #reservation(CodeEmploye INT, CodeProduit INT, DateLocationPrevue DATE, DateReservation DATE,
    NbExemplaires INT, DureePrevue INT);

DECLARE @sql NVARCHAR(MAX), @options NVARCHAR(200) = N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK)';
SET @sql = N'BULK INSERT #employe FROM '''    + @dossier + N'employe.csv'    + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #produit FROM '''    + @dossier + N'produit.csv'    + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #exemplaire FROM ''' + @dossier + N'exemplaire.csv' + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #location FROM '''   + @dossier + N'location.csv'   + @options; EXEC (@sql);
SET @sql = N'BULK INSERT #reservation FROM '''+ @dossier + N'reservation.csv'+ @options; EXEC (@sql);
CREATE INDEX ix_location ON #location(CodeExemplaire, DateLocation);

CREATE TABLE #bilan(Ordre INT, Fichier VARCHAR(20), LignesLues INT, LignesChargees INT);
INSERT INTO #bilan(Ordre, Fichier, LignesLues) VALUES
    (1, 'employe.csv', (SELECT COUNT(*) FROM #employe)), (2, 'produit.csv', (SELECT COUNT(*) FROM #produit)),
    (3, 'exemplaire.csv', (SELECT COUNT(*) FROM #exemplaire)), (4, 'location.csv', (SELECT COUNT(*) FROM #location)),
    (5, 'reservation.csv', (SELECT COUNT(*) FROM #reservation));
-- lignes rejetées d'un fichier de faits : clé de la ligne, anomalie et valeur lue
CREATE TABLE #rejet(CodeEmploye INT, CodeAutre INT, DateLigne DATE, Anomalie NVARCHAR(80), ValeurLue NVARCHAR(100));

-- ============================================================ 2. contrôle qualité des dimensions
-- lignes en double (même code) : on n'en garde qu'une
WITH d AS (SELECT CodeEmploye, ROW_NUMBER() OVER (PARTITION BY CodeEmploye ORDER BY (SELECT NULL)) AS n FROM #employe)
DELETE FROM d
OUTPUT 'employe.csv', N'ligne en double', N'doublon supprimé', CONCAT(N'employé ', deleted.CodeEmploye), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE n > 1;
WITH d AS (SELECT CodeProduit, ROW_NUMBER() OVER (PARTITION BY CodeProduit ORDER BY (SELECT NULL)) AS n FROM #produit)
DELETE FROM d
OUTPUT 'produit.csv', N'ligne en double', N'doublon supprimé', CONCAT(N'produit ', deleted.CodeProduit), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE n > 1;
WITH d AS (SELECT CodeExemplaire, ROW_NUMBER() OVER (PARTITION BY CodeExemplaire ORDER BY (SELECT NULL)) AS n FROM #exemplaire)
DELETE FROM d
OUTPUT 'exemplaire.csv', N'ligne en double', N'doublon supprimé', CONCAT(N'exemplaire ', deleted.CodeExemplaire), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE n > 1;

-- libellé de service mal écrit (casse, espaces) : on reprend le libellé le plus fréquent pour ce code de service
WITH f AS (SELECT CodeService, TRIM(NomService) COLLATE French_CS_AS AS Nom, COUNT(*) AS nb
           FROM #employe GROUP BY CodeService, TRIM(NomService) COLLATE French_CS_AS),
     r AS (SELECT CodeService, Nom, ROW_NUMBER() OVER (PARTITION BY CodeService ORDER BY nb DESC, Nom) AS n FROM f)
UPDATE e SET NomService = r.Nom
OUTPUT 'employe.csv', N'libellé de service mal écrit (casse, espaces)', N'corrigée',
       CONCAT(N'employé ', inserted.CodeEmploye), CONCAT(N'« ', deleted.NomService, N' »')
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
FROM #employe e JOIN r ON r.CodeService = e.CodeService AND r.n = 1
WHERE e.NomService + N'|' COLLATE French_CS_AS <> r.Nom + N'|';

-- valeurs manquantes : membre « non renseigné »
UPDATE #employe SET CodeCategorie = 'NR-00', NomCategorie = N'Profil non renseigné', SuperCategorie = N'Non renseignée'
OUTPUT 'employe.csv', N'profil de trajet manquant', N'complétée', CONCAT(N'employé ', inserted.CodeEmploye), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE CodeCategorie IS NULL;
UPDATE #employe SET CodeDomaine = 'ND', LibDomaine = N'Non renseigné', CodeDivision = 'ND', LibDivision = N'Non renseigné'
OUTPUT 'employe.csv', N'domaine de la société manquant', N'complétée', CONCAT(N'employé ', inserted.CodeEmploye),
       inserted.NomSociete
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE CodeDomaine IS NULL;
UPDATE #produit SET MarqueProduit = N'Non renseignée'
OUTPUT 'produit.csv', N'marque manquante', N'complétée', CONCAT(N'produit ', inserted.CodeProduit), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE MarqueProduit IS NULL;

-- date de réforme antérieure à la mise en service : date erronée, supprimée
UPDATE #exemplaire SET DateReforme = NULL
OUTPUT 'exemplaire.csv', N'date de réforme antérieure à la mise en service', N'corrigée',
       CONCAT(N'exemplaire ', inserted.CodeExemplaire), CONVERT(NVARCHAR(10), deleted.DateReforme, 23)
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE DateReforme <= DateMiseService;

-- ============================================================ 3. chargement des dimensions
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

-- ============================================================ 4. contrôle qualité des locations
WITH d AS (SELECT CodeEmploye, CodeExemplaire, DateLocation,
                  ROW_NUMBER() OVER (PARTITION BY CodeEmploye, CodeExemplaire, DateLocation ORDER BY (SELECT NULL)) AS n
           FROM #location)
DELETE FROM d
OUTPUT 'location.csv', N'ligne en double', N'doublon supprimé',
       CONCAT(N'employé ', deleted.CodeEmploye, N', exemplaire ', deleted.CodeExemplaire, N', ', CONVERT(CHAR(10), deleted.DateLocation, 23)), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE n > 1;

-- taux de réduction saisi en pourcentage (ex. 15 au lieu de 0,15) : ramené dans ]0 ; 1]
UPDATE #location SET TauxReduction = TauxReduction / 100
OUTPUT 'location.csv', N'taux de réduction saisi en pourcentage', N'corrigée',
       CONCAT(N'employé ', inserted.CodeEmploye, N', exemplaire ', inserted.CodeExemplaire, N', ', CONVERT(CHAR(10), inserted.DateLocation, 23)),
       CAST(deleted.TauxReduction AS NVARCHAR(20))
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE TauxReduction > 1;

-- lignes inutilisables : codes inconnus, dates hors période ou futures, durées nulles, négatives ou aberrantes
INSERT INTO #rejet(CodeEmploye, CodeAutre, DateLigne, Anomalie, ValeurLue)
SELECT l.CodeEmploye, l.CodeExemplaire, l.DateLocation, m.Anomalie,
       CONCAT(CONVERT(CHAR(10), l.DateLocation, 23), N', ', l.DureeLocation, N' j')
FROM #location l
LEFT JOIN dw.DIM_EMPLOYE e    ON e.CodeEmploye = l.CodeEmploye
LEFT JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
LEFT JOIN dw.DIM_TEMPS t      ON t.DateJour = l.DateLocation
CROSS APPLY (SELECT CASE
    WHEN e.CleEmploye IS NULL THEN N'employé inconnu'
    WHEN x.CleExemplaire IS NULL THEN N'exemplaire inconnu'
    WHEN t.CleTemps IS NULL OR l.DateLocation >= CAST(GETDATE() AS DATE) THEN N'date future ou hors période'
    WHEN l.DureeLocation IS NULL OR l.DureeLocation <= 0 THEN N'durée nulle ou négative'
    WHEN l.DureeLocation > 90 THEN N'durée aberrante (plus de 90 jours)'
    WHEN l.DateLocation < x.DateMiseService
      OR (x.DateReforme IS NOT NULL AND DATEADD(DAY, l.DureeLocation, l.DateLocation) > x.DateReforme)
         THEN N'location hors période de service de l''exemplaire'
    END AS Anomalie) m
WHERE m.Anomalie IS NOT NULL;

-- prix journalier manquant : prix observé pour le même produit, dans le même pays, le mois le plus proche de la même année
SELECT x.CleProduit, x.PaysAgence, YEAR(l.DateLocation) AS Annee, MONTH(l.DateLocation) AS Mois, MAX(l.PrixJourTTC) AS Prix
INTO #prix
FROM #location l JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
WHERE l.PrixJourTTC IS NOT NULL
GROUP BY x.CleProduit, x.PaysAgence, YEAR(l.DateLocation), MONTH(l.DateLocation);
UPDATE l SET PrixJourTTC = p.Prix
OUTPUT 'location.csv', N'prix journalier manquant', N'complétée',
       CONCAT(N'employé ', inserted.CodeEmploye, N', exemplaire ', inserted.CodeExemplaire, N', ', CONVERT(CHAR(10), inserted.DateLocation, 23)), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
FROM #location l
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
CROSS APPLY (SELECT TOP (1) p.Prix FROM #prix p
             WHERE p.CleProduit = x.CleProduit AND p.PaysAgence = x.PaysAgence AND p.Annee = YEAR(l.DateLocation)
             ORDER BY ABS(p.Mois - MONTH(l.DateLocation)), p.Mois) p
WHERE l.PrixJourTTC IS NULL
  AND NOT EXISTS (SELECT 1 FROM #rejet r WHERE r.CodeEmploye = l.CodeEmploye AND r.CodeAutre = l.CodeExemplaire AND r.DateLigne = l.DateLocation);

-- taux de réduction manquant : taux du même employé pour la même gamme et la même année,
-- à défaut celui du même profil de trajet (le taux dépend du profil, de la gamme et de l'année)
SELECT l.CodeEmploye, p.CodeGamme, YEAR(l.DateLocation) AS Annee, MAX(l.TauxReduction) AS Taux
INTO #taux_emp
FROM #location l
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
JOIN dw.DIM_PRODUIT p    ON p.CleProduit = x.CleProduit
WHERE l.TauxReduction IS NOT NULL
GROUP BY l.CodeEmploye, p.CodeGamme, YEAR(l.DateLocation);
SELECT e.CodeCategorie, p.CodeGamme, YEAR(l.DateLocation) AS Annee, MAX(l.TauxReduction) AS Taux
INTO #taux_profil
FROM #location l
JOIN dw.DIM_EMPLOYE e    ON e.CodeEmploye = l.CodeEmploye
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
JOIN dw.DIM_PRODUIT p    ON p.CleProduit = x.CleProduit
WHERE l.TauxReduction IS NOT NULL AND e.CodeCategorie <> 'NR-00'
GROUP BY e.CodeCategorie, p.CodeGamme, YEAR(l.DateLocation);
UPDATE l SET TauxReduction = COALESCE(te.Taux, tp.Taux)
OUTPUT 'location.csv', N'taux de réduction manquant', N'complétée',
       CONCAT(N'employé ', inserted.CodeEmploye, N', exemplaire ', inserted.CodeExemplaire, N', ', CONVERT(CHAR(10), inserted.DateLocation, 23)), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
FROM #location l
JOIN dw.DIM_EMPLOYE e    ON e.CodeEmploye = l.CodeEmploye
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire
JOIN dw.DIM_PRODUIT p    ON p.CleProduit = x.CleProduit
LEFT JOIN #taux_emp te   ON te.CodeEmploye = l.CodeEmploye AND te.CodeGamme = p.CodeGamme AND te.Annee = YEAR(l.DateLocation)
LEFT JOIN #taux_profil tp ON tp.CodeCategorie = e.CodeCategorie AND tp.CodeGamme = p.CodeGamme AND tp.Annee = YEAR(l.DateLocation)
WHERE l.TauxReduction IS NULL AND COALESCE(te.Taux, tp.Taux) IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM #rejet r WHERE r.CodeEmploye = l.CodeEmploye AND r.CodeAutre = l.CodeExemplaire AND r.DateLigne = l.DateLocation);

-- prix ou taux toujours manquant : ligne rejetée
INSERT INTO #rejet(CodeEmploye, CodeAutre, DateLigne, Anomalie, ValeurLue)
SELECT l.CodeEmploye, l.CodeExemplaire, l.DateLocation, N'prix ou taux manquant, impossible à retrouver', NULL
FROM #location l
WHERE (l.PrixJourTTC IS NULL OR l.TauxReduction IS NULL)
  AND NOT EXISTS (SELECT 1 FROM #rejet r WHERE r.CodeEmploye = l.CodeEmploye AND r.CodeAutre = l.CodeExemplaire AND r.DateLigne = l.DateLocation);

-- exemplaire loué deux fois sur des périodes qui se chevauchent : on garde la location commencée la première
INSERT INTO #rejet(CodeEmploye, CodeAutre, DateLigne, Anomalie, ValeurLue)
SELECT DISTINCT b.CodeEmploye, b.CodeExemplaire, b.DateLocation, N'exemplaire loué deux fois en même temps',
       CONCAT(N'chevauche la location de l''employé ', a.CodeEmploye, N' du ', CONVERT(CHAR(10), a.DateLocation, 23))
FROM #location a
JOIN #location b ON b.CodeExemplaire = a.CodeExemplaire
                AND (b.DateLocation > a.DateLocation OR (b.DateLocation = a.DateLocation AND b.CodeEmploye > a.CodeEmploye))
                AND b.DateLocation < DATEADD(DAY, a.DureeLocation, a.DateLocation)
WHERE a.DureeLocation BETWEEN 1 AND 90 AND b.DureeLocation BETWEEN 1 AND 90
  AND NOT EXISTS (SELECT 1 FROM #rejet r WHERE r.CodeEmploye = a.CodeEmploye AND r.CodeAutre = a.CodeExemplaire AND r.DateLigne = a.DateLocation)
  AND NOT EXISTS (SELECT 1 FROM #rejet r WHERE r.CodeEmploye = b.CodeEmploye AND r.CodeAutre = b.CodeExemplaire AND r.DateLigne = b.DateLocation);

INSERT INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
SELECT 'location.csv', Anomalie, N'rejetée',
       CONCAT(N'employé ', CodeEmploye, N', exemplaire ', CodeAutre, N', ', CONVERT(CHAR(10), DateLigne, 23)), ValeurLue
FROM #rejet;
DELETE l FROM #location l
JOIN #rejet r ON r.CodeEmploye = l.CodeEmploye AND r.CodeAutre = l.CodeExemplaire AND r.DateLigne = l.DateLocation;

-- ============================================================ 5. chargement du fait Location (codes -> clés, mesures calculées)
INSERT INTO dw.FAIT_LOCATION(CleTemps, CleEmploye, CleExemplaire, CleProduit, DureeLocation, TauxReduction, MontantPublic, MontantPaye)
SELECT t.CleTemps, e.CleEmploye, x.CleExemplaire, x.CleProduit, l.DureeLocation, l.TauxReduction,
       l.DureeLocation * l.PrixJourTTC,
       ROUND(l.DureeLocation * l.PrixJourTTC * (1 - l.TauxReduction), 2)
FROM #location l
JOIN dw.DIM_TEMPS t      ON t.DateJour = l.DateLocation
JOIN dw.DIM_EMPLOYE e    ON e.CodeEmploye = l.CodeEmploye
JOIN dw.DIM_EXEMPLAIRE x ON x.CodeExemplaire = l.CodeExemplaire;

-- ============================================================ 6. contrôle qualité et chargement du fait Réservation
WITH d AS (SELECT CodeEmploye, CodeProduit, DateLocationPrevue,
                  ROW_NUMBER() OVER (PARTITION BY CodeEmploye, CodeProduit, DateLocationPrevue ORDER BY (SELECT NULL)) AS n
           FROM #reservation)
DELETE FROM d
OUTPUT 'reservation.csv', N'ligne en double', N'doublon supprimé',
       CONCAT(N'employé ', deleted.CodeEmploye, N', produit ', deleted.CodeProduit, N', ', CONVERT(CHAR(10), deleted.DateLocationPrevue, 23)), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE n > 1;

UPDATE #reservation SET NbExemplaires = 1
OUTPUT 'reservation.csv', N'nombre d''exemplaires manquant', N'complétée',
       CONCAT(N'employé ', inserted.CodeEmploye, N', produit ', inserted.CodeProduit, N', ', CONVERT(CHAR(10), inserted.DateLocationPrevue, 23)), NULL
INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
WHERE NbExemplaires IS NULL;

TRUNCATE TABLE #rejet;
INSERT INTO #rejet(CodeEmploye, CodeAutre, DateLigne, Anomalie, ValeurLue)
SELECT r.CodeEmploye, r.CodeProduit, r.DateLocationPrevue, m.Anomalie,
       CONCAT(N'réservée le ', CONVERT(CHAR(10), r.DateReservation, 23), N' pour le ', CONVERT(CHAR(10), r.DateLocationPrevue, 23))
FROM #reservation r
LEFT JOIN dw.DIM_EMPLOYE e ON e.CodeEmploye = r.CodeEmploye
LEFT JOIN dw.DIM_PRODUIT p ON p.CodeProduit = r.CodeProduit
LEFT JOIN dw.DIM_TEMPS t   ON t.DateJour = r.DateLocationPrevue
CROSS APPLY (SELECT CASE
    WHEN e.CleEmploye IS NULL THEN N'employé inconnu'
    WHEN p.CleProduit IS NULL THEN N'produit inconnu'
    WHEN t.CleTemps IS NULL OR r.DateLocationPrevue >= CAST(GETDATE() AS DATE) THEN N'date future ou hors période'
    WHEN r.DateReservation IS NULL OR r.DateReservation > r.DateLocationPrevue THEN N'date de réservation après la location prévue'
    WHEN r.DureePrevue IS NULL OR r.DureePrevue <= 0 OR r.NbExemplaires <= 0 THEN N'durée ou nombre d''exemplaires nul ou négatif'
    END AS Anomalie) m
WHERE m.Anomalie IS NOT NULL;
INSERT INTO dw.JOURNAL_QUALITE(Fichier, Anomalie, Traitement, Ligne, ValeurLue)
SELECT 'reservation.csv', Anomalie, N'rejetée',
       CONCAT(N'employé ', CodeEmploye, N', produit ', CodeAutre, N', ', CONVERT(CHAR(10), DateLigne, 23)), ValeurLue
FROM #rejet;
DELETE r FROM #reservation r
JOIN #rejet j ON j.CodeEmploye = r.CodeEmploye AND j.CodeAutre = r.CodeProduit AND j.DateLigne = r.DateLocationPrevue;

INSERT INTO dw.FAIT_RESERVATION(CleTemps, CleEmploye, CleProduit, NbExemplaires, DureePrevue, DelaiReservation, NonHonoree)
SELECT t.CleTemps, e.CleEmploye, p.CleProduit, r.NbExemplaires, r.DureePrevue,
       DATEDIFF(DAY, r.DateReservation, r.DateLocationPrevue),
       CASE WHEN EXISTS (SELECT 1 FROM dw.FAIT_LOCATION f
                         WHERE f.CleEmploye = e.CleEmploye AND f.CleProduit = p.CleProduit AND f.CleTemps = t.CleTemps)
            THEN 0 ELSE 1 END
FROM #reservation r
JOIN dw.DIM_TEMPS t   ON t.DateJour = r.DateLocationPrevue
JOIN dw.DIM_EMPLOYE e ON e.CodeEmploye = r.CodeEmploye
JOIN dw.DIM_PRODUIT p ON p.CodeProduit = r.CodeProduit;

-- ============================================================ 7. bilans
UPDATE #bilan SET LignesChargees = CASE Fichier
    WHEN 'employe.csv'     THEN (SELECT COUNT(*) FROM dw.DIM_EMPLOYE)
    WHEN 'produit.csv'     THEN (SELECT COUNT(*) FROM dw.DIM_PRODUIT)
    WHEN 'exemplaire.csv'  THEN (SELECT COUNT(*) FROM dw.DIM_EXEMPLAIRE)
    WHEN 'location.csv'    THEN (SELECT COUNT(*) FROM dw.FAIT_LOCATION)
    WHEN 'reservation.csv' THEN (SELECT COUNT(*) FROM dw.FAIT_RESERVATION) END;

-- 1) lignes lues et chargées par fichier (l'écart = doublons supprimés + lignes rejetées)
SELECT Fichier, LignesLues, LignesChargees, LignesLues - LignesChargees AS Ecart FROM #bilan ORDER BY Ordre;

-- 2) journal de qualité : à comparer avec 3_donnees/referentiels/anomalies_injectees.csv
SELECT Fichier, Anomalie, Traitement, COUNT(*) AS NbLignes
FROM dw.JOURNAL_QUALITE
GROUP BY Fichier, Anomalie, Traitement
ORDER BY Fichier, Traitement, Anomalie;

-- 3) volumes minimaux du sujet
SELECT Element, Nb, Minimum, CASE WHEN Nb >= Minimum THEN 'OK' ELSE 'INSUFFISANT' END AS Verdict
FROM (SELECT 1 AS o, N'Sociétés' AS Element, COUNT(DISTINCT CodeSociete) AS Nb, 40 AS Minimum FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 2, N'Régions (FR) et Länder (DE)', COUNT(DISTINCT CASE WHEN CodePays = 'FR' THEN CodeRegion ELSE CodeLand END), 5 FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 3, N'Employés', COUNT(*), 3000 FROM dw.DIM_EMPLOYE
      UNION ALL SELECT 4, N'Produits', COUNT(*), 60 FROM dw.DIM_PRODUIT
      UNION ALL SELECT 5, N'Secteurs', COUNT(DISTINCT Secteur), 3 FROM dw.DIM_PRODUIT
      UNION ALL SELECT 6, N'Exemplaires', COUNT(*), 400 FROM dw.DIM_EXEMPLAIRE
      UNION ALL SELECT 7, N'Locations', COUNT(*), 60000 FROM dw.FAIT_LOCATION
      UNION ALL SELECT 8, N'Années complètes (12 mois de locations)', COUNT(*), 3
                FROM (SELECT t.Annee FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
                      GROUP BY t.Annee HAVING COUNT(DISTINCT t.NumMois) = 12) a) v
ORDER BY o;

-- 4) totaux de référence de l'entrepôt, à retrouver dans le cube après son traitement
SELECT (SELECT COUNT(*) FROM dw.FAIT_LOCATION)           AS NbLocations,
       (SELECT SUM(DureeLocation) FROM dw.FAIT_LOCATION) AS DureeTotale,
       (SELECT SUM(MontantPublic) FROM dw.FAIT_LOCATION) AS MontantPublicTotal,
       (SELECT SUM(MontantPaye) FROM dw.FAIT_LOCATION)   AS MontantPayeTotal,
       (SELECT COUNT(*) FROM dw.FAIT_RESERVATION)        AS NbReservations,
       (SELECT SUM(NonHonoree) FROM dw.FAIT_RESERVATION) AS NbReservationsNonHonorees;

DROP TABLE IF EXISTS #employe, #produit, #exemplaire, #location, #reservation, #rejet, #bilan, #prix, #taux_emp, #taux_profil;
GO
SET NOEXEC OFF;
GO

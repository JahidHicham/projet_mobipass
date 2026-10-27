-- MobiPass - Projet 2 : contrôles de l'entrepôt dw (après 03_chargement_dw.sql)
-- 1. Règles du dictionnaire de données et du sujet : chaque requête doit renvoyer 0 ligne en anomalie.
--    Le fait Location a une ligne par jour loué : une location = ses lignes, DebutLocation = 1 le premier jour.
-- 2. Volumes minimaux du sujet.
-- 3. Totaux de référence (global, par année, par mois) à retrouver dans le cube : 04_controles_cube.mdx
--    renvoie les mêmes totaux en MDX (étape 5 du sujet : vérification des totaux entre l'entrepôt et le cube).
-- 4. Résumé du journal de qualité du chargement.
-- À lancer dans la base de l'entrepôt (liste déroulante de SSMS). Ne modifie rien.

IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    RAISERROR(N'Choisissez d''abord votre base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro étudiant à la fac), puis relancez.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO
SET NOCOUNT ON;

-- ============================================================ 1. règles : nombre de lignes en anomalie (0 attendu partout)
SELECT Controle, NbAnomalies, CASE WHEN NbAnomalies = 0 THEN 'OK' ELSE 'A CORRIGER' END AS Verdict
FROM (
    SELECT 1 AS o, N'Ligne de location qui ne vaut pas 1 jour (grain : un jour loué)' AS Controle,
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION WHERE DureeLocation <> 1) AS NbAnomalies
    UNION ALL SELECT 2, N'Taux de réduction hors ]0 ; 1]',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION WHERE TauxReduction <= 0 OR TauxReduction > 1)
    UNION ALL SELECT 3, N'Location au prix public ou plus (payé >= public)',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION WHERE MontantPaye >= MontantPublic)
    UNION ALL SELECT 4, N'Montant payé différent de public x (1 - taux)',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION WHERE ABS(MontantPaye - MontantPublic * (1 - TauxReduction)) >= 0.01)
    UNION ALL SELECT 5, N'Location commencée dans le futur',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
             WHERE f.DebutLocation = 1 AND t.DateJour >= CAST(GETDATE() AS DATE))
    UNION ALL SELECT 6, N'Jour loué avant la mise en service ou après la réforme de l''exemplaire',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
             JOIN dw.DIM_EXEMPLAIRE x ON x.CleExemplaire = f.CleExemplaire
             WHERE t.DateJour < x.DateMiseService
                OR (x.DateReforme IS NOT NULL AND t.DateJour >= x.DateReforme))
    UNION ALL SELECT 7, N'Exemplaire loué deux fois le même jour (locations qui se chevauchent)',
           (SELECT COUNT(*) FROM (SELECT CleExemplaire, CleTemps FROM dw.FAIT_LOCATION
                                  GROUP BY CleExemplaire, CleTemps HAVING COUNT(*) > 1) d)
    UNION ALL SELECT 8, N'Produit de la location différent du produit de l''exemplaire',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION f JOIN dw.DIM_EXEMPLAIRE x ON x.CleExemplaire = f.CleExemplaire
             WHERE x.CleProduit <> f.CleProduit)
    UNION ALL SELECT 9, N'Exemplaire réformé avant sa mise en service',
           (SELECT COUNT(*) FROM dw.DIM_EXEMPLAIRE WHERE DateReforme <= DateMiseService)
    UNION ALL SELECT 10, N'Réservation : durée ou nombre d''exemplaires nul, délai négatif',
           (SELECT COUNT(*) FROM dw.FAIT_RESERVATION WHERE DureePrevue <= 0 OR NbExemplaires <= 0 OR DelaiReservation < 0)
    UNION ALL SELECT 11, N'Réservation marquée honorée sans location correspondante',
           (SELECT COUNT(*) FROM dw.FAIT_RESERVATION r WHERE r.NonHonoree = 0
              AND NOT EXISTS (SELECT 1 FROM dw.FAIT_LOCATION f WHERE f.CleEmploye = r.CleEmploye
                                AND f.CleProduit = r.CleProduit AND f.CleTemps = r.CleTemps AND f.DebutLocation = 1))
    UNION ALL SELECT 12, N'Taux de TVA hors ]0 ; 1]',
           (SELECT COUNT(*) FROM dw.DIM_EMPLOYE WHERE TauxTVA <= 0 OR TauxTVA > 1)
    UNION ALL SELECT 13, N'Semaine ISO mal rattachée (année ISO différente de l''année du jeudi)',
           (SELECT COUNT(*) FROM dw.DIM_TEMPS
             WHERE AnneeISO <> YEAR(DATEADD(DAY, 4 - NumJourSemaine, DateJour)))
    UNION ALL SELECT 14, N'Jour de location sans le jour précédent (location découpée avec un trou)',
           (SELECT COUNT(*) FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
             WHERE f.DebutLocation = 0
               AND NOT EXISTS (SELECT 1 FROM dw.FAIT_LOCATION p JOIN dw.DIM_TEMPS tp ON tp.CleTemps = p.CleTemps
                               WHERE p.CleEmploye = f.CleEmploye AND p.CleExemplaire = f.CleExemplaire
                                 AND tp.DateJour = DATEADD(DAY, -1, t.DateJour)))
) c
ORDER BY o;

-- ============================================================ 2. volumes minimaux du sujet
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

-- ============================================================ 3. totaux de référence (à comparer avec 04_controles_cube.mdx)
-- 3a. global
SELECT (SELECT SUM(DebutLocation) FROM dw.FAIT_LOCATION) AS NombreDeLocations,
       (SELECT SUM(DureeLocation) FROM dw.FAIT_LOCATION) AS Duree,
       (SELECT SUM(MontantPublic) FROM dw.FAIT_LOCATION) AS MontantPublic,
       (SELECT SUM(MontantPaye) FROM dw.FAIT_LOCATION)   AS MontantPaye,
       (SELECT COUNT(*) FROM dw.FAIT_RESERVATION)        AS NombreDeReservations,
       (SELECT SUM(NonHonoree) FROM dw.FAIT_RESERVATION) AS ReservationsNonHonorees;

-- 3b. par année (locations comptées l'année de leur début, jours et montants l'année du jour loué)
SELECT t.Annee, SUM(f.DebutLocation) AS NombreDeLocations, SUM(f.DureeLocation) AS Duree,
       SUM(f.MontantPublic) AS MontantPublic, SUM(f.MontantPaye) AS MontantPaye
FROM dw.FAIT_LOCATION f JOIN dw.DIM_TEMPS t ON t.CleTemps = f.CleTemps
GROUP BY t.Annee
ORDER BY t.Annee;

-- 3c. par pays de la société de l'employé
SELECT e.NomPays, SUM(f.DebutLocation) AS NombreDeLocations, SUM(f.DureeLocation) AS Duree, SUM(f.MontantPaye) AS MontantPaye
FROM dw.FAIT_LOCATION f JOIN dw.DIM_EMPLOYE e ON e.CleEmploye = f.CleEmploye
GROUP BY e.NomPays
ORDER BY e.NomPays;

-- 3d. par secteur de produit
SELECT p.Secteur, SUM(f.DebutLocation) AS NombreDeLocations, SUM(f.DureeLocation) AS Duree, SUM(f.MontantPaye) AS MontantPaye
FROM dw.FAIT_LOCATION f JOIN dw.DIM_PRODUIT p ON p.CleProduit = f.CleProduit
GROUP BY p.Secteur
ORDER BY p.Secteur;

-- ============================================================ 4. journal de qualité du chargement
SELECT Fichier, Anomalie, Traitement, COUNT(*) AS NbLignes
FROM dw.JOURNAL_QUALITE
GROUP BY Fichier, Anomalie, Traitement
ORDER BY Fichier, Traitement, Anomalie;
GO
SET NOEXEC OFF;
GO

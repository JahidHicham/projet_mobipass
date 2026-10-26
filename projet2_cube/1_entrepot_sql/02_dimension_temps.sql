-- MobiPass - Projet 2 : remplissage de la dimension Temps (dw.DIM_TEMPS)
-- Une ligne par jour sur toute la période couverte par les locations (années complètes).
-- Libellés français écrits en clair (CHOOSE) : le résultat ne dépend pas de la langue du serveur.
-- Règle des semaines à cheval sur deux années : semaine ISO 8601 (lundi-dimanche), rattachée à l'année
-- qui contient son jeudi. Ex. : dimanche 01/01/2023 = semaine 52 de 2022 ; lundi 30/12/2024 = semaine 1 de 2025.
-- C'est la norme en France et en Allemagne, et celle de la hiérarchie H_SEM du projet 1 (Annee_ISO).
-- Relançable : n'ajoute que les jours absents (aucune suppression, même si des locations sont déjà chargées).
-- À lancer après 01_creation_dw.sql, dans la même base (liste déroulante de SSMS).

IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    RAISERROR(N'Choisissez d''abord votre base dans la liste déroulante de SSMS (MobiPass sur votre PC, votre numéro étudiant à la fac), puis relancez.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO

DECLARE @debut DATE = '2023-01-01',   -- période couverte : à adapter si les données changent
        @fin   DATE = '2026-12-31';

WITH jours AS (
    SELECT @debut AS DateJour
    UNION ALL
    SELECT DATEADD(DAY, 1, DateJour) FROM jours WHERE DateJour < @fin
)
INSERT INTO dw.DIM_TEMPS(CleTemps, DateJour, NumJourSemaine, LibJour, EstWeekEnd, NumSemaineISO, AnneeISO,
                         CleSemaine, LibSemaine, NumMois, LibMois, CleMois, LibMoisAnnee, NumTrimestre,
                         CleTrimestre, LibTrimestre, Saison, Annee)
SELECT YEAR(j.DateJour) * 10000 + MONTH(j.DateJour) * 100 + DAY(j.DateJour),
       j.DateJour,
       s.NumJour,
       CHOOSE(s.NumJour, N'lundi', N'mardi', N'mercredi', N'jeudi', N'vendredi', N'samedi', N'dimanche'),
       CASE WHEN s.NumJour >= 6 THEN 1 ELSE 0 END,
       DATEPART(ISO_WEEK, j.DateJour),
       YEAR(s.Jeudi),
       YEAR(s.Jeudi) * 100 + DATEPART(ISO_WEEK, j.DateJour),
       CONCAT(YEAR(s.Jeudi), '-S', RIGHT('0' + CAST(DATEPART(ISO_WEEK, j.DateJour) AS VARCHAR(2)), 2)),
       MONTH(j.DateJour),
       m.LibMois,
       YEAR(j.DateJour) * 100 + MONTH(j.DateJour),
       CONCAT(m.LibMois, N' ', YEAR(j.DateJour)),
       DATEPART(QUARTER, j.DateJour),
       YEAR(j.DateJour) * 10 + DATEPART(QUARTER, j.DateJour),
       CONCAT('T', DATEPART(QUARTER, j.DateJour), ' ', YEAR(j.DateJour)),
       CASE WHEN MONTH(j.DateJour) IN (3, 4, 5)   THEN N'printemps'
            WHEN MONTH(j.DateJour) IN (6, 7, 8)   THEN N'été'
            WHEN MONTH(j.DateJour) IN (9, 10, 11) THEN N'automne'
            ELSE N'hiver' END,
       YEAR(j.DateJour)
FROM jours j
-- NumJour : 1 = lundi (le 01/01/1900 était un lundi) ; Jeudi : jeudi de la même semaine ISO
CROSS APPLY (SELECT DATEDIFF(DAY, '19000101', j.DateJour) % 7 + 1 AS NumJour) n
CROSS APPLY (SELECT n.NumJour, DATEADD(DAY, 4 - n.NumJour, j.DateJour) AS Jeudi) s
CROSS APPLY (SELECT CHOOSE(MONTH(j.DateJour), N'janvier', N'février', N'mars', N'avril', N'mai', N'juin',
                           N'juillet', N'août', N'septembre', N'octobre', N'novembre', N'décembre') AS LibMois) m
WHERE NOT EXISTS (SELECT 1 FROM dw.DIM_TEMPS t WHERE t.DateJour = j.DateJour)
OPTION (MAXRECURSION 0);
GO

-- Vérification : 1 461 jours attendus (2023 à 2026), puis les jours autour des changements d'année
SELECT COUNT(*) AS nb_jours, MIN(DateJour) AS premier_jour, MAX(DateJour) AS dernier_jour FROM dw.DIM_TEMPS;

SELECT DateJour, LibJour, LibSemaine, NumSemaineISO, AnneeISO, Annee, LibMoisAnnee, Saison
FROM dw.DIM_TEMPS
WHERE DateJour BETWEEN '2023-01-01' AND '2023-01-02'
   OR DateJour BETWEEN '2024-12-29' AND '2025-01-05'
   OR DateJour BETWEEN '2025-12-28' AND '2026-01-04'
ORDER BY DateJour;
GO
SET NOEXEC OFF;
GO

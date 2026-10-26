-- vérification
SELECT COUNT(*) FROM louer;
SELECT COUNT(*) FROM location_md1;


-- Décomposition de la durée de location en mois

WITH location_md AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        duree_location_md,
        datej AS date_deb_loc,
        datej + duree_location_md AS date_fin_loc
    FROM location_md1
),
decomposition_mois AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        date_deb_loc,
        date_fin_loc,
        duree_location_md,
        ADD_MONTHS(TRUNC(date_deb_loc, 'MM'), LEVEL - 1) AS date_deb_mois,
        LAST_DAY(ADD_MONTHS(TRUNC(date_deb_loc, 'MM'), LEVEL - 1)) AS date_fin_mois
    FROM location_md
    CONNECT BY LEVEL <= MONTHS_BETWEEN(TRUNC(date_fin_loc, 'MM'), TRUNC(date_deb_loc, 'MM')) + 1
        AND PRIOR codeemploye = codeemploye
        AND PRIOR codeexemplaire = codeexemplaire
        AND PRIOR date_deb_loc = date_deb_loc
        AND PRIOR date_fin_loc = date_fin_loc
        AND PRIOR DBMS_RANDOM.VALUE IS NOT NULL
),
calcul_duree_hebdo AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        date_deb_loc,
        date_fin_loc,
        duree_location_md,
        CASE
            WHEN date_deb_loc > date_deb_mois
                THEN date_deb_loc
            ELSE date_deb_mois
        END AS date_deb_mois,
        CASE
            WHEN date_fin_loc < date_fin_mois
                THEN date_fin_loc
            ELSE date_fin_mois
        END AS date_fin_mois
    FROM decomposition_mois
)
SELECT *
FROM calcul_duree_hebdo
--WHERE codeemploye = 2 AND codeexemplaire = 184
ORDER BY
    codeemploye, codeexemplaire, date_deb_loc, date_deb_mois;

-- Décomposition de la période de location par semaine
WITH location_md AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        duree_location_md,
        datej AS date_deb_loc,
        datej + duree_location_md AS date_fin_loc
    FROM location_md1
),
decomposition_semaine AS
(
    SELECT
        codeemploye, codeexemplaire,
        date_deb_loc, date_fin_loc, duree_location_md,
        TRUNC(date_deb_loc, 'IW') + 7 * (LEVEL - 1) AS date_deb_semaine,
        TRUNC(date_deb_loc, 'IW') + 7 * (LEVEL - 1) + 6 AS date_fin_semaine
    FROM location_md
    CONNECT BY LEVEL <= CEIL((TRUNC(date_fin_loc, 'IW') - TRUNC(date_deb_loc, 'IW') + 1) / 7)
        AND PRIOR codeemploye = codeemploye
        AND PRIOR codeexemplaire = codeexemplaire
        AND PRIOR date_deb_loc = date_deb_loc
        AND PRIOR date_fin_loc = date_fin_loc
        AND PRIOR DBMS_RANDOM.VALUE IS NOT NULL
),
calcul_duree_hebdo AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        date_deb_loc,
        date_fin_loc,
        duree_location_md,

        CASE
            WHEN date_deb_loc > date_deb_semaine
                THEN date_deb_loc
            ELSE date_deb_semaine
        END AS date_deb_semaine,

        CASE
            WHEN date_fin_loc < date_fin_semaine
                THEN date_fin_loc
            ELSE date_fin_semaine
        END AS date_fin_semaine

    FROM decomposition_semaine
)
SELECT *
FROM calcul_duree_hebdo
ORDER BY
    codeemploye,
    codeexemplaire,
    date_deb_loc,
    date_deb_semaine;
    
    
WITH location_md AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        duree_location_md,
        datej AS date_deb_loc,
        datej + duree_location_md AS date_fin_loc
    FROM location_md1
),
decomposition_semaine AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        date_deb_loc,
        date_fin_loc,
        duree_location_md,

        TRUNC(date_deb_loc, 'IW') + 7 * (LEVEL - 1)
            AS date_deb_semaine,

        TRUNC(date_deb_loc, 'IW') + 7 * (LEVEL - 1) + 6
            AS date_fin_semaine

    FROM location_md
    CONNECT BY LEVEL <=
        FLOOR(
            (
                TRUNC(date_fin_loc, 'IW')
                - TRUNC(date_deb_loc, 'IW')
            ) / 7
        ) + 1

        AND PRIOR codeemploye = codeemploye
        AND PRIOR codeexemplaire = codeexemplaire
        AND PRIOR date_deb_loc = date_deb_loc
        AND PRIOR date_fin_loc = date_fin_loc
        AND PRIOR DBMS_RANDOM.VALUE IS NOT NULL
),
calcul_duree_hebdo AS
(
    SELECT
        codeemploye,
        codeexemplaire,
        date_deb_loc,
        date_fin_loc,
        duree_location_md,

        CASE
            WHEN date_deb_loc > date_deb_semaine
                THEN date_deb_loc
            ELSE date_deb_semaine
        END AS date_deb_semaine,

        CASE
            WHEN date_fin_loc < date_fin_semaine
                THEN date_fin_loc
            ELSE date_fin_semaine
        END AS date_fin_semaine

    FROM decomposition_semaine
)
SELECT *
FROM calcul_duree_hebdo
WHERE codeemploye = 2
  AND codeexemplaire = 184
ORDER BY
    codeemploye,
    codeexemplaire,
    date_deb_loc,
    date_deb_semaine;
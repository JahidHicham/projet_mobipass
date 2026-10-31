SELECT codezg, nomzg, codezg_zone_englobante, niveauzg, LEVEL AS lvl
FROM ZONE_GEO
START WITH codezg_zone_englobante IS NULL
CONNECT BY PRIOR codezg = codezg_zone_englobante
ORDER BY LEVEL, niveauzg;

SELECT codepays,
       LISTAGG(niveauzg, ' ---> ')
           WITHIN GROUP (ORDER BY lvl) AS hierarchie
FROM (
    SELECT DISTINCT
           codepays,
           niveauzg,
           LEVEL AS lvl
    FROM ZONE_GEO
    START WITH codezg_zone_englobante IS NULL
    CONNECT BY PRIOR codezg = codezg_zone_englobante
)
GROUP BY codepays
ORDER BY codepays DESC;


SELECT codepays,
       LISTAGG(niveaux, ' ---> ')
           WITHIN GROUP (ORDER BY lvl) AS hierarchie
FROM (
    SELECT codepays,
           lvl,
           '(' || LISTAGG(niveauzg, ' | ')
                      WITHIN GROUP (ORDER BY niveauzg) || ')' AS niveaux
    FROM (
        SELECT DISTINCT
               codepays,
               niveauzg,
               LEVEL AS lvl
        FROM ZONE_GEO
        START WITH codezg_zone_englobante IS NULL
        CONNECT BY PRIOR codezg = codezg_zone_englobante
    )
    GROUP BY codepays, lvl
)
GROUP BY codepays;
    
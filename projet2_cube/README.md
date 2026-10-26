# Projet 2 : cube OLAP MobiPass « Locations » (SQL Server + SSAS + MDX)

Ce dossier est l'archive à rendre. Un sous-dossier par livrable du sujet (partie 7).

| Dossier / fichier | Livrable du sujet | Contenu |
|---|---|---|
| `1_entrepot_sql/` | Scripts de l'entrepôt | base, schéma `dw`, dimension Temps, chargement (BULK INSERT) avec contrôle qualité, contrôles des totaux |
| `2_projet_ssas/` | Projet SSAS | projet Visual Studio « Projet multidimensionnel Analysis Services » du cube |
| `3_donnees/` | Données et génération | générateur Python, fichiers sources CSV (`csv/`), référentiels à relire (`referentiels/`), journal des prompts |
| `4_verite_terrain.md` | Fichier « vérité terrain » | phénomènes et anomalies injectés dans les données |
| `5_mdx/` | Requêtes MDX + rapport d'analyse | séquences S1, S2, S3, requêtes de recette a/b/c, un PDF par séquence |
| `choix_conception.md` | (support de soutenance) | chaque choix de conception, sa justification et l'écart avec le projet 1 |

## Reconstruire l'entrepôt

1. *(facultatif)* `python 3_donnees/gen_donnees_projet2.py` : régénère les CSV (mêmes données à chaque fois).
2. Dans SSMS, connecté au moteur de base de données :

| Ordre | Script | Résultat attendu |
|---|---|---|
| 0 | `1_entrepot_sql/00_creation_base.sql` | base `MobiPass` créée (sur votre PC seulement) |
| 1 | `1_entrepot_sql/01_creation_dw.sql` | 7 tables, 8 clés étrangères, 1 trigger |
| 2 | `1_entrepot_sql/02_dimension_temps.sql` | 1 461 jours (2023 à 2026) |
| 3 | `1_entrepot_sql/03_chargement_dw.sql` (sur votre PC) **ou** `03_chargement_dw_fac.sql` (à la fac) | bilans : 63 138 locations, 27 520 réservations, journal de qualité |
| 4 | `1_entrepot_sql/04_controles_entrepot.sql` | 13 règles à 0 anomalie, volumes OK, totaux de référence (global, année, pays, secteur) |
| 5 | `1_entrepot_sql/04_controles_cube.mdx` (SSMS, Analysis Services, après traitement du cube) | les mêmes totaux, calculés sur le cube : identiques à ceux de l'étape 4 |

Avant les scripts 1 à 3, choisir la base dans la liste déroulante de SSMS (`MobiPass` sur votre PC, votre numéro
étudiant à la fac). Dans `03_chargement_dw.sql`, adapter `@dossier` au chemin du dossier `3_donnees/csv` sur votre PC :
BULK INSERT lit les fichiers sur la machine du serveur, il ne fonctionne donc pas sur `etu-mssql3`.
À la fac, utiliser `03_chargement_dw_fac.sql` : même traitement, mais les données y sont écrites en INSERT
(fichier produit par le générateur, environ 40 secondes d'exécution).

## Projet du cube (Visual Studio) : réglages selon le serveur

Ouvrir `2_projet_ssas/MobiPass_NABHIS/MobiPass_NABHIS.sln`, puis régler la source de données (`MobiPass.ds`)
et le déploiement (clic droit sur le projet → Propriétés → Déploiement) :

| | Sur votre PC | À la fac |
|---|---|---|
| Serveur de la source de données | `(local)` (l'ancien fournisseur OLE DB ne trouve pas `localhost`) | `etu-mssql3` |
| Base de la source de données | `MobiPass` | votre numéro étudiant |
| Emprunt d'identité | compte de service (après avoir donné à `NT SERVICE\MSSQLServerOLAPService` le rôle `db_datareader` sur MobiPass) | `AD\numéro` + mot de passe, comme au TP |
| Serveur de déploiement | `localhost` | `etu-mssql3` |

## Environnement

SQL Server 2022 Developer (instance par défaut `localhost`), Analysis Services en mode multidimensionnel,
SSMS 22, Visual Studio 2022 avec l'extension « Microsoft Analysis Services Projects 2022+ », Python 3.

# Projet 2 : cube OLAP MobiPass « Locations » (SQL Server + SSAS + MDX)

Ce dossier est l'archive à rendre. Un sous-dossier par livrable du sujet (partie 7).

| Dossier / fichier | Livrable du sujet | Contenu |
|---|---|---|
| `1_entrepot_sql/` | Scripts de l'entrepôt | base, schéma `dw`, dimension Temps, chargement (BULK INSERT) avec contrôle qualité, contrôles des totaux |
| `2_projet_ssas/` | Projet SSAS | projet Visual Studio « Projet multidimensionnel Analysis Services » du cube |
| `3_donnees/` | Données et génération | générateur Python, fichiers sources CSV (`csv/`), référentiels à relire (`referentiels/`), journal des prompts |
| `4_verite_terrain.md` | Fichier « vérité terrain » | phénomènes et anomalies injectés dans les données |
| `5_mdx/` | Requêtes MDX + rapport d'analyse | séquences S1, S2, S3, requêtes de recette a/b/c, un PDF par séquence |

## Reconstruire l'entrepôt

1. *(facultatif)* `python 3_donnees/gen_donnees_projet2.py` : régénère les CSV (mêmes données à chaque fois).
2. Dans SSMS, connecté au moteur de base de données :

| Ordre | Script | Résultat attendu |
|---|---|---|
| 0 | `1_entrepot_sql/00_creation_base.sql` | base `MobiPass` créée (sur votre PC seulement) |
| 1 | `1_entrepot_sql/01_creation_dw.sql` | 7 tables, 8 clés étrangères, 1 trigger |
| 2 | `1_entrepot_sql/02_dimension_temps.sql` | 1 461 jours (2023 à 2026) |
| 3 | `1_entrepot_sql/03_chargement_dw.sql` | bilans : 63 138 locations, 27 520 réservations, journal de qualité |

Avant les scripts 1 à 3, choisir la base dans la liste déroulante de SSMS (`MobiPass` sur votre PC, votre numéro
étudiant à la fac). Dans le script 3, adapter `@dossier` au chemin du dossier `3_donnees/csv` sur votre PC.
BULK INSERT lit les fichiers sur la machine du serveur : il ne fonctionne pas sur `etu-mssql3` avec des fichiers de votre PC.

## Environnement

SQL Server 2022 Developer (instance par défaut `localhost`), Analysis Services en mode multidimensionnel,
SSMS 22, Visual Studio 2022 avec l'extension « Microsoft Analysis Services Projects 2022+ », Python 3.

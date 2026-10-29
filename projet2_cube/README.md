# Projet 2 : cube OLAP MobiPass « Locations » (SQL Server + SSAS + MDX)

Ce dossier est l'archive à rendre. Un sous-dossier par livrable du sujet (partie 7).

| Dossier / fichier | Livrable du sujet | Contenu |
|---|---|---|
| `1_entrepot_sql/` | Scripts de l'entrepôt | base, schéma `dw`, dimension Temps, chargement (BULK INSERT), contrôles des règles et des totaux |
| `2_projet_ssas/` | Projet SSAS | projet Visual Studio « Projet multidimensionnel Analysis Services » du cube |
| `3_donnees/` | Données et génération | générateur Python, fichiers sources CSV (`csv/`), référentiels à relire (`referentiels/`), journal des prompts |
| `4_verite_terrain.md` | Fichier « vérité terrain » | phénomènes injectés dans les données (et où les voir dans le cube) |
| `5_mdx/` | Requêtes MDX + rapport d'analyse | requêtes de Sami Carrere, testées sur le cube : `recette_abc.mdx` (recette a, b, c), `S1_saturation.mdx`, `S2_profils.mdx`, `S3_Allemagne.mdx` (lancement en Allemagne, phénomène P7) ; un PDF par séquence |
| `choix_conception.md` | (support de soutenance) | chaque choix de conception, sa justification et l'écart avec le projet 1 |

## Reconstruire l'entrepôt

1. *(facultatif)* `python 3_donnees/gen_donnees_projet2.py` : régénère les CSV (mêmes données à chaque fois).
2. Dans SSMS, connecté au moteur de base de données :

| Ordre | Script | Résultat attendu |
|---|---|---|
| 0 | `1_entrepot_sql/00_creation_base.sql` | base `MobiPass` créée (sur votre PC seulement) |
| 1 | `1_entrepot_sql/01_creation_dw.sql` | 5 tables, 5 clés étrangères, 1 trigger |
| 2 | `1_entrepot_sql/02_dimension_temps.sql` | 1 461 jours (2023 à 2026) |
| 3 | `1_entrepot_sql/03_chargement_dw.sql` (sur votre PC) **ou** `03_chargement_dw_fac.sql` (à la fac) | bilans : 67 595 locations (222 433 lignes, une par jour loué), écart 0 entre lignes lues et chargées |
| 4 | `1_entrepot_sql/04_controles_entrepot.sql` | 12 règles à 0 anomalie, volumes OK, totaux de référence (global, année, pays, secteur) |
| 5 | `1_entrepot_sql/04_controles_cube.mdx` (SSMS, Analysis Services, après traitement du cube) | les mêmes totaux, calculés sur le cube : identiques à ceux de l'étape 4 |

Avant les scripts 1 à 3, choisir la base dans la liste déroulante de SSMS (`MobiPass` sur votre PC, votre numéro
étudiant à la fac). Dans `03_chargement_dw.sql`, adapter `@dossier` au chemin du dossier `3_donnees/csv` sur votre PC :
BULK INSERT lit les fichiers sur la machine du serveur, il ne fonctionne donc pas sur `etu-mssql3`.
À la fac, utiliser `03_chargement_dw_fac.sql` : même traitement, mais les données y sont écrites en INSERT
(fichier produit par le générateur, environ 30 secondes d'exécution).

## Contenu du cube « Locations »

Un seul fait, **Location**, au grain du jour loué (une location de 5 jours = 5 lignes), et trois dimensions :
**Temps** (hiérarchies H_MOIS et H_SEM), **Employé** (géographies française et allemande, profil de trajet, type et
domaine de société) et **Exemplaire** (avec son produit : H_GAMME, H_MAR, H_GENERATION, et son agence : H_Agence).

| Mesure | Définition |
|---|---|
| Nombre de locations | somme de `DebutLocation` (1 le premier jour de chaque location) |
| Durée | nombre de jours loués |
| Montant public, Montant payé | euros TTC ; payé = public x (1 - taux de réduction) |
| Montant remise, Taux de remise effectif, Durée moyenne, Montant payé moyen | mesures calculées (séquence S2) |
| Exemplaires loués, Taux d'occupation | exemplaires loués dans la période ; jours loués / (exemplaires loués x jours) |
| Jours de rupture, Taux de rupture | séquence S1 : jours où tous les exemplaires d'un produit sont loués dans une agence (le produit n'est pas disponible) ; taux = jours de rupture / jours-produits proposés |

Formules : `2_projet_ssas/membres_calcules.mdx` (copiées dans l'onglet Calculs du cube). Après un traitement du cube,
la première requête qui utilise les jours de rupture prend environ une minute (le cache se remplit), les suivantes
sont immédiates.

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

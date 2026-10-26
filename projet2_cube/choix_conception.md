# Choix de conception du projet 2 (cube « Locations »)

Chaque décision, sa justification et ce qu'elle change par rapport à la conception du projet 1
(`docs/Location_MD.json`, schéma en étoile Location_MD).

| # | Décision | Justification | Écart avec le projet 1 |
|---|---|---|---|
| 1 | L'entrepôt SQL Server est un **schéma en étoile `dw`** (4 dimensions, 2 faits), pas une copie des 29 tables de l'entrepôt Oracle | Sujet, partie B, étape 1 : « tables de dimensions avec clés de substitution, table de faits des locations ». Le cube ne porte que sur les locations | Aucun : c'est le magasin Location_MD du projet 1, implanté sous SQL Server. 18 des 29 tables de l'entrepôt y sont regroupées ; les 11 autres (achats, RH, métiers, partenaires) ne concernent pas les locations |
| 2 | **Données du projet 1 gardées et complétées** jusqu'aux volumes du sujet | Sujet, partie C : 40 sociétés, 3 000 employés, 60 produits, 400 exemplaires, 60 000 locations sur 3 années complètes. Le projet 1 n'en avait que 5 100 sur 2 ans | Les 5 100 locations du projet 1 sont toutes présentes ; 2023 et le début de 2024 sont ajoutés |
| 3 | **Données manquantes et erronées** injectées dans les fichiers sources (≈ 2 % des lignes), traitées au chargement et notées dans `dw.JOURNAL_QUALITE` | Consigne orale du prof (« données manquantes et biaisées ») ; sujet, partie B : « chargement, contrôles » | Nouveau. Le journal retrouve exactement les 19 types d'anomalies injectées |
| 4 | **Fait Réservation** : une réservation non honorée est une demande sans exemplaire libre | Séquence S1 : « Quand et où les employés **ne trouvent-ils pas** de produit à louer ? » Les locations seules ne montrent pas les demandes refusées. Source : table RESERVER de l'entrepôt | Ajout au schéma en étoile |
| 5 | **Produit dans sa propre table**, reliée à l'exemplaire | Le produit est partagé par les deux faits (on réserve un produit, on loue un exemplaire) | Les hiérarchies du projet 1 sont conservées : H_GAMME (Exemplaire → Produit → Gamme → Secteur), H_MAR, H_GENERATION |
| 6 | **Agence** de l'exemplaire dans la dimension Exemplaire | S1 : savoir **où** le parc sature | Ajout |
| 7 | **Domaine NAF/WZ** de la société dans la dimension Employé (Société → Domaine → Division) | S2 : « roll-up par domaine de société » ; partie C : « sociétés françaises et allemandes avec leur domaine » | Ajout. Les sociétés allemandes reçoivent l'équivalent NACE de leur code WZ (WZ 2008 et NAF rév. 2 sont identiques jusqu'à la classe) : **à valider par le groupe** (réglage `DOMAINE_DE` du générateur) |
| 8 | **Géographies française et allemande séparées**, avec les noms de colonnes de la conception | Conception finale du projet 1 : H_France, H_Allemagne, H_District, H_Type_Kreis, H_Type_Land | Les niveaux de l'autre pays valent « Sans objet » (au lieu de NULL) et un Kreis sans district a le district « Sans district (Land) » : chaque hiérarchie reste stricte pour SSAS |
| 9 | **Dimension Temps** générée par script : hiérarchies H_MOIS et H_SEM, libellés français, saison, jour de la semaine, trimestre | Conception (H_MOIS, H_SEM, Annee_ISO) ; sujet, partie B, étape 3 (libellés des mois et des jours, numéro de semaine) ; S1 (« slice sur la saison ») | Ajouts : saison, jour de la semaine, trimestre |
| 10 | **Semaine ISO 8601** : une semaine à cheval sur deux années appartient à l'année de son jeudi | Sujet : « décider de la règle de rattachement des semaines à cheval » ; norme en France et en Allemagne | Aucun : c'était déjà Annee_ISO au projet 1 |
| 11 | Clés des mois et des semaines **année × 100 + numéro** (202504) | Distinguer avril 2024 et avril 2025 ; même astuce que le TP (D_YEARWEEKNUM) | — |
| 12 | **Clés de substitution** numérotées de 1 à n au chargement ; date AAAAMMJJ pour le temps | Sujet : « dimensions avec clés de substitution » | — |
| 13 | **Mesures** : DureeLocation, MontantPublic, MontantPaye (+ TauxReduction, non additif) | Conception : Duree_Location_MD, Montant_Location_MD, Montant_Location_ReelPaye_MD | Mêmes mesures ; montants en euros **TTC** (prix allemands HT + TVA), comme au projet 1 |
| 14 | **Contraintes** : CHECK (durée > 0, taux et TVA dans ]0 ; 1], payé < public) et trigger (dates cohérentes, pas de chevauchement d'un exemplaire) | Sujet, partie B, étape 1 et règles de la partie C | Reprend le dictionnaire de données et le trigger trg_louer_controle du projet 1 |
| 15 | **Deux scripts de chargement au traitement identique** : BULK INSERT sur un PC, INSERT à la fac | BULK INSERT lit les fichiers sur la machine du serveur : impossible sur `etu-mssql3` avec des fichiers du PC client | Résultats identiques vérifiés (63 138 locations, mêmes totaux) |

## À valider par le groupe

- Le domaine des sociétés allemandes (décision 7).
- Les lois de probabilité et les phénomènes : `4_verite_terrain.md`, § 2 et § 3.
- Les référentiels ajoutés : `3_donnees/referentiels/*.csv`, colonne `Origine`.

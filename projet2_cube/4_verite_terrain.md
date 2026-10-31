# Vérité terrain — données du cube « Locations »

Ce fichier décrit ce qui a été **volontairement injecté** dans les données par le générateur
`3_donnees/gen_donnees_projet2.py` (graine fixe : les mêmes données à chaque exécution).
Il sert à vérifier que l'analyse OLAP retrouve bien ces phénomènes.

## 1. Origine et volumes

- Les données du projet 1 (`projet1_oracle/sql/ed/03_insertion_ED.sql`) sont **gardées telles quelles** : 20 sociétés, 403 employés,
  40 produits, 256 exemplaires, 5 100 locations, 1 000 réservations (non chargées : pas de fait Réservation). Seule exception : les 8 sociétés allemandes
  reçoivent un domaine d'activité (voir § 5).
- Le générateur les **complète** jusqu'aux volumes minimaux du sujet.

| Élément | Après chargement dans l'entrepôt | Minimum du sujet |
|---|---|---|
| Sociétés | 51 (31 en France, 20 en Allemagne) | 40 |
| Régions (FR) et Länder (DE) | 21 | 5 |
| Employés | 3 528 | 3 000 |
| Produits | 77, dont 62 loués | 60 |
| Secteurs | 4 (3 parmi les produits loués) | 3 |
| Exemplaires | 968, dans 15 agences | 400 |
| Locations | 67 595 (222 433 jours loués) | 60 000 |
| Période | 01/01/2023 → 13/10/2026 (2023, 2024, 2025 complètes) | 3 années complètes |
| Demandes refusées (simulées, absentes des fichiers sources) | 7 789 | — |

Tendance générale : l'activité française croît chaque année (8 838 locations en 2023, 12 697 en 2024, 17 799 en 2025),
avec l'arrivée de nouvelles sociétés clientes et un usage plus intensif. L'Allemagne démarre en janvier 2026.

Les fichiers sources sont **complets et cohérents** : pas de données manquantes ni erronées (consigne du prof). Seuls
des **phénomènes** ont été injectés, pour être retrouvés par l'analyse OLAP.

## 2. Lois de probabilité (réglages en tête du générateur)

| Règle | Valeur |
|---|---|
| Saisonnalité par mois (poids) | janv. 0,5 · févr. 0,55 · mars 0,85 · avr. 1,25 · mai 1,6 · juin 1,7 · juil. 1,4 · août 0,9 · sept. 1,45 · oct. 1,0 · nov. 0,6 · déc. 0,45 |
| Jour de la semaine | lundi à vendredi 1 · samedi 0,55 · dimanche 0,3 |
| Semaine européenne de la mobilité (16-22 septembre) | demande × 1,7 |
| Vacances d'été en Allemagne (P6) | pas de creux national : juillet et août au poids 1,6 ; pendant les vacances de son Land (dates 2026 de la KMK, environ 6 semaines), la demande d'un employé est × 0,35 |
| Croissance de l'usage | 2023 × 1,0 · 2024 × 1,05 · 2025 × 1,1 · 2026 × 1,15 |
| Profil de trajet des employés | répartition du projet 1 ; plus de trajets courts et intermodaux en ville dense, plus de trajets moyens et longs en périurbain |
| Gros et petits loueurs | 25 % des employés louent 6 fois plus ; 30 % louent 3 fois moins |
| Durée d'une location | selon la classe de trajet (voir P3) ; × 1,5 en Allemagne |
| Choix de la gamme | popularité du projet 1, modifiée par la classe de trajet, la région (P2) et le pays (P5) |
| Exemplaire | le produit demandé dans l'agence de rattachement de l'employé, sinon un autre produit de la même gamme |
| Demande refusée | une demande sans exemplaire libre (ni du produit, ni de la gamme dans l'agence) est refusée : aucune location. Les refus ne sont pas dans les fichiers sources (pas de fait Réservation, consigne du prof) : le cube les déduit des jours où tous les exemplaires sont loués |
| Prix et remise | tarif en vigueur (FR TTC, DE HT converti en TTC) ; taux de réduction du profil, de la gamme et de l'année (règle du projet 1, 2023 ajoutée) |

## 3. Phénomènes injectés

### P1 — Saisonnalité et saturation du parc (séquence S1)
- **Règle** : la demande suit la saisonnalité ci-dessus. Le parc est volontairement **sous-dimensionné à Paris**
  (vélos électriques urbains, vélos cargo) et **à Lyon** (vélos électriques urbains).
- **Simulé** : environ **10 % des demandes sont refusées** faute d'exemplaire libre (7 789 refus pour 67 595
  locations). Ces refus se concentrent en **juin (1 638)**, en **septembre (1 754, pic la semaine de la mobilité,
  semaines ISO 38-39)**, en mai et en juillet. Il y en a presque aucun en décembre (74). Où : Paris (vélos
  électriques urbains, 349 refus), Lyon (vélos électriques urbains 231, trottinettes électriques 203).
- **À observer dans le cube** (locations seules) : le produit n'est pas disponible quand tous ses exemplaires sont
  loués. **Taux de rupture** 2026 : **juin 47 %**, **septembre 45 %**, creux en août (30 %) ; semaines 38-39 :
  **50 % et 51 %** ; vélos cargo et vélos électriques urbains en tête. Toutes gammes confondues, ce sont les
  agences allemandes (Hambourg, Cologne, Berlin, Leipzig) : petit parc pour une forte demande, et usage très intensif
  dans les villes-États (P7a). Pour les vélos électriques urbains (juin et septembre) : en France, Lille (74 %, petit
  parc), Lyon (56 %) et **Paris (50 %, le plus gros volume)**, au-dessus de la moyenne française (41 %).
  Vérifié contre un calcul SQL exact (mêmes chiffres au mois).

### P2 — Concentration d'une gamme dans une région
- **Règle** : les VTT électriques sont 4 fois plus demandés par les employés d'Auvergne-Rhône-Alpes.
- **À observer** : les VTT électriques représentent **19,3 % des locations en Auvergne-Rhône-Alpes**, contre
  **6,3 % ailleurs** (reste de la France et Allemagne) et 6,5 % dans le reste de la France seule.

### P3 — Comportement selon la classe de trajet (séquence S2)
- **Règle** : trajets longs = locations longues mais moins fréquentes ; intermodal = locations courtes, plus fréquentes,
  surtout des vélos pliants et des trottinettes. Les remises dépendent aussi de la classe (trajet court ≈ 5-10 %, trajet long ≈ 18-25 %).

| Classe de trajet | Durée moyenne | Locations par employé |
|---|---|---|
| Trajet court | 2,5 jours | 17,3 |
| Trajet moyen | 4,2 jours | 17,2 |
| Trajet long | 10,4 jours | 12,5 |
| Trajet intermodal | 1,9 jour | 27,5 |

### P4 — Évolution de sociétés clientes (piste pour la séquence S3)
- **Seine Digital Factory** (Issy-les-Moulineaux) arrive en mars 2024 et recrute jusqu'à fin 2025 :
  358 locations en 2024, **1 005 en 2025 (× 2,8)**, 1 130 de janvier à mi-octobre 2026.
- **Provence Banque Régionale** (Aix-en-Provence) met en place sa propre flotte de vélos en avril 2025 : ses locations
  chutent de 80 % à partir de cette date (560 en 2023, 681 en 2024, **283 en 2025**, 126 en 2026).

### P5 — Écart France / Allemagne (piste pour la séquence S3)
- **Règle** : l'Allemagne démarre en janvier 2026 ; locations 1,5 fois plus longues ; plus de vélos cargo et de trottinettes électriques.
- **À observer en 2026** : montée en charge mois par mois (44 locations en janvier, 1 967 en juin). Le profil
  allemand se lit sur les **Länder de territoire** (Type Land = Flächenland), car les villes-États louent comme la
  France (P7a) : durée moyenne **3,9 jours contre 3,3 en France** ; vélos cargo **11,3 % des locations contre 5,8 %**.
  Allemagne entière : 3,4 jours et 8,9 % de vélos cargo.

### P6 — Grandes vacances : creux d'été et pic de rentrée (S1 ou S3)
- **Règle** : en France, août est le mois le plus calme de l'été (poids 0,9) et septembre repart fort (1,45, plus la
  semaine de la mobilité). En Allemagne, il n'y a pas de creux national : chaque Land a ses propres vacances d'été,
  décalées (règle à long terme de la KMK, 2026), pendant lesquelles ses employés louent beaucoup moins (× 0,35).
- **À observer** : France 2026 : **2 602 locations en juin, 1 468 en août, 2 455 en septembre**. Allemagne, locations
  par semaine ISO de 2026 (croiser Land × semaine) :

| Land | Vacances d'été 2026 | Avant | Pendant les vacances | Après |
|---|---|---|---|---|
| Nordrhein-Westfalen | 20/07 → 01/09 (semaines 30 à 35) | ≈ 95 par semaine | ≈ 52 | ≈ 105 |
| Sachsen | 04/07 → 14/08 (semaines 28 à 33) | ≈ 92 | ≈ 41 | ≈ 95 |
| Bayern | 03/08 → 14/09 (semaines 32 à 37) | ≈ 52 | ≈ 16 | ≈ 58 (semaines 38-39) |

  Les autres Länder ont trop peu d'employés pour que le creux soit net.

### P7 — Lancement allemand : réussite des villes-États, décrochage de la Bavière (séquence S3)
Phénomène proposé par Sami (séquence S3 « Lancement en Allemagne »).
- **P7a, règle** : à Berlin, Hambourg et Brême (`Type Land` = Stadtstaat), les employés louent comme en France :
  pas de durée × 1,5 ni de surplus de vélos cargo et de trottinettes électriques (P5). Ils louent aussi 1,3 fois plus
  souvent. Deux sociétés ajoutées : Spree Digital Studios GmbH (Berlin, 120 employés) et Alster Medienhaus GmbH
  (Hambourg, 90).
- **P7b, règle** : les employés bavarois demandent 4 fois plus de VTT électriques (comme en Auvergne-Rhône-Alpes, P2),
  mais l'agence de Munich n'en a que 20 % du parc nécessaire. Chaque demande refusée décourage l'employé : sa
  demande est divisée par 2, jusqu'à un plancher de 10 %. Une société ajoutée : Isarwerk Technologie AG (Munich, 110).
- **Parc allemand** porté de 240 à 320 exemplaires visés, pour suivre la demande accrue.
- **À observer dans le cube** (janvier à septembre 2026 ; octobre est incomplet) :

| Groupe | Durée moyenne | Locations par employé actif | Intermodal | Vélos pliants | Vélos cargo | VTT électriques |
|---|---|---|---|---|---|---|
| Villes-États (Stadtstaat) | 2,7 j | 15,6 | 38,7 % | 15,8 % | 5,5 % | 5,3 % |
| Länder de territoire (Flächenland, Bavière comprise) | 3,9 j | 10,2 | 37,6 % | 12,1 % | 11,3 % | — |
| dont Bayern | 4,1 j | 7,7 | 32,1 % | 10,9 % | 10,5 % | 8,7 % |
| France | 3,3 j | 7,2 | 31,8 % | 12,6 % | 5,8 % | 9,2 % |
| Auvergne-Rhône-Alpes | 3,3 j | 7,9 | 37,4 % | 12,4 % | 5,3 % | 18,9 % |

  Employé actif = employé qui commence au moins une location dans la période.

  - **Montée en charge** : en Allemagne, 44 locations en janvier, 1 478 en avril, 1 847 en mai, 2 015 en septembre.
    Le rapport Allemagne / France passe de 6 % en janvier à 77 % en avril, puis reste stable.
  - **Décrochage bavarois** : le taux de rupture des VTT électriques à Munich est de **71 %**, le premier couple
    agence × gamme d'Allemagne (Lyon × VTT électriques : 15 %). Par mois : 27 % en février, 63 % en mars, 77 % en
    avril, 85 % en mai, 90 % en juin. L'usage par employé actif en Bavière plafonne à 2,9 en avril, puis tombe à
    2,5 en mai et 2,3 en juillet, alors que les Länder de territoire passent de 3,07 à 3,17. 225 demandes
    bavaroises refusées en 2026 ; 103 des 185 employés bavarois ont vu leur demande divisée par 2 ou plus.
  - Requêtes : `5_mdx/S3_Allemagne.mdx` (valeurs vérifiées sur le cube le 29/10).

## 4. Choix retenus

- **Domaine des sociétés allemandes** : réglage `DOMAINE_DE = True` du générateur. Le sujet du projet 2 demande des
  « sociétés françaises et allemandes avec leur domaine », alors que le projet 1 n'en donnait pas aux sociétés
  allemandes : elles reçoivent l'équivalent NACE de leur code WZ (avec `False`, elles seraient dans un domaine
  « Non renseigné »).
- Les **lois de probabilité** du § 2 et les **phénomènes** P1 à P7 du § 3 sont ceux du générateur final.
- Les **référentiels ajoutés** (sociétés, produits, agences, tarifs) sont dans `3_donnees/referentiels/*.csv` ; la
  colonne `Origine` distingue les données du projet 1 et les ajouts du projet 2.
- Le détail des demandes faites à l'assistant IA pour écrire le générateur est dans `3_donnees/journal_prompts.md`.

## 5. Vérification des valeurs

Les valeurs de ce fichier correspondent aux données finales : 67 595 locations et 222 433 jours loués, identiques
dans les CSV (`3_donnees/csv/`), dans l'entrepôt SQL Server (schéma `dw`) et dans le cube.

- **Recalculées en SQL sur l'entrepôt le 31/10** : volumes du § 1, tendance par année, P2, P3, P4, P5 (durées et
  vélos cargo par type de Land), P6 (France 2026 par mois) et la montée en charge allemande de P7.
- **Vérifiées sur le cube en MDX le 29/10** : taux de rupture de P1 et indicateurs détaillés de P7 (requêtes de
  `5_mdx/`). Les données n'ont pas changé depuis.
- **Recalculées par le générateur le 31/10** (relancé à l'identique : mêmes fichiers octet pour octet,
  « ERREURS : aucune ») : demandes refusées de P1 par mois et par semaine ISO, creux d'été des Länder (P6) et
  indicateurs de P7b (Munich, Bavière).
- **Simulées par le générateur, absentes des fichiers** : les 7 789 demandes refusées de P1 (elles n'existent que
  comme cause des ruptures visibles dans le cube).

# Vérité terrain — données du cube « Locations »

Ce fichier décrit ce qui a été **volontairement injecté** dans les données par le générateur
`3_donnees/gen_donnees_projet2.py` (graine fixe : les mêmes données à chaque exécution).
Il sert à vérifier que l'analyse OLAP retrouve bien ces phénomènes.

## 1. Origine et volumes

- Les données du projet 1 (`sql/ed/03_insertion_ED.sql`) sont **gardées telles quelles** : 20 sociétés, 403 employés,
  40 produits, 256 exemplaires, 5 100 locations, 1 000 réservations. Seule exception : les 8 sociétés allemandes
  reçoivent un domaine d'activité (voir § 5).
- Le générateur les **complète** jusqu'aux volumes minimaux du sujet.

| Élément | Après chargement dans l'entrepôt | Minimum du sujet |
|---|---|---|
| Sociétés | 48 (31 en France, 17 en Allemagne) | 40 |
| Régions (FR) et Länder (DE) | 21 | 5 |
| Employés | 3 208 | 3 000 |
| Produits | 77, dont 62 loués | 60 |
| Secteurs | 4 (3 parmi les produits loués) | 3 |
| Exemplaires | 903, dans 15 agences | 400 |
| Locations | 63 138 | 60 000 |
| Période | 01/01/2023 → 13/10/2026 (2023, 2024, 2025 complètes) | 3 années complètes |
| Réservations | 27 520, dont 7 286 non honorées | — |

Tendance générale : l'activité française croît chaque année (8 385 locations en 2023, 12 418 en 2024, 17 374 en 2025),
avec l'arrivée de nouvelles sociétés clientes et un usage plus intensif. L'Allemagne démarre en janvier 2026.

## 2. Lois de probabilité (réglages en tête du générateur, à valider par le groupe)

| Règle | Valeur |
|---|---|
| Saisonnalité par mois (poids) | janv. 0,5 · févr. 0,55 · mars 0,85 · avr. 1,25 · mai 1,6 · juin 1,7 · juil. 1,4 · août 0,9 · sept. 1,45 · oct. 1,0 · nov. 0,6 · déc. 0,45 |
| Jour de la semaine | lundi à vendredi 1 · samedi 0,55 · dimanche 0,3 |
| Semaine européenne de la mobilité (16-22 septembre) | demande × 1,7 |
| Croissance de l'usage | 2023 × 1,0 · 2024 × 1,05 · 2025 × 1,1 · 2026 × 1,15 |
| Profil de trajet des employés | répartition du projet 1 ; plus de trajets courts et intermodaux en ville dense, plus de trajets moyens et longs en périurbain |
| Gros et petits loueurs | 25 % des employés louent 6 fois plus ; 30 % louent 3 fois moins |
| Durée d'une location | selon la classe de trajet (voir P3) ; × 1,5 en Allemagne |
| Choix de la gamme | popularité du projet 1, modifiée par la classe de trajet, la région (P2) et le pays (P5) |
| Exemplaire | le produit demandé dans l'agence de rattachement de l'employé, sinon un autre produit de la même gamme |
| Réservation | 35 % des locations sont réservées à l'avance (0 à 21 jours) ; une demande sans exemplaire libre devient une réservation non honorée |
| Prix et remise | tarif en vigueur (FR TTC, DE HT converti en TTC) ; taux de réduction du profil, de la gamme et de l'année (règle du projet 1, 2023 ajoutée) |

## 3. Phénomènes injectés

### P1 — Saisonnalité et saturation du parc (séquence S1)
- **Règle** : la demande suit la saisonnalité ci-dessus. Le parc est volontairement **sous-dimensionné à Paris**
  (vélos électriques urbains, vélos cargo) et **à Lyon** (vélos électriques urbains).
- **À observer** : environ **10 % des demandes ne sont pas satisfaites** (7 286 réservations non honorées pour
  63 138 locations). Ces échecs se concentrent en **juin (1 428)**, en **septembre (1 655, pic la semaine de la
  mobilité, semaines ISO 38-39)**, en mai et en juillet. Il y en a presque aucun en décembre (69).
- **Où** : Île-de-France (AG-PAR, vélos électriques urbains : 360 demandes non satisfaites) et Auvergne-Rhône-Alpes
  (AG-LYO : 201), puis les trottinettes électriques en Allemagne (Cologne, Munich).

### P2 — Concentration d'une gamme dans une région
- **Règle** : les VTT électriques sont 4 fois plus demandés par les employés d'Auvergne-Rhône-Alpes.
- **À observer** : les VTT électriques représentent **19 % des locations en Auvergne-Rhône-Alpes**, contre **6 % ailleurs**.

### P3 — Comportement selon la classe de trajet (séquence S2)
- **Règle** : trajets longs = locations longues mais moins fréquentes ; intermodal = locations courtes, plus fréquentes,
  surtout des vélos pliants et des trottinettes. Les remises dépendent aussi de la classe (trajet court ≈ 5-10 %, trajet long ≈ 18-25 %).

| Classe de trajet | Durée moyenne | Locations par employé |
|---|---|---|
| Trajet court | 2,5 jours | 17,3 |
| Trajet moyen | 4,3 jours | 18,4 |
| Trajet long | 10,5 jours | 12,9 |
| Trajet intermodal | 1,9 jour | 28,2 |

### P4 — Évolution de sociétés clientes (piste pour la séquence S3)
- **Seine Digital Factory** (Issy-les-Moulineaux) arrive en mars 2024 et recrute jusqu'à fin 2025 :
  417 locations en 2024, **1 144 en 2025 (× 2,7)**, 1 386 de janvier à mi-octobre 2026.
- **Provence Banque Régionale** (Aix-en-Provence) met en place sa propre flotte de vélos en avril 2025 : ses locations
  chutent de 80 % à partir de cette date (553 en 2023, 645 en 2024, **260 en 2025**, 126 en 2026).

### P5 — Écart France / Allemagne (piste pour la séquence S3)
- **Règle** : l'Allemagne démarre en janvier 2026 ; locations 1,5 fois plus longues ; plus de vélos cargo et de trottinettes électriques.
- **À observer en 2026** : montée en charge mois par mois (46 locations en janvier, 1 373 en juin) ; durée moyenne
  **4,1 jours en Allemagne contre 3,2 en France** ; vélos cargo **12,5 % des locations allemandes contre 6,0 %**.

## 4. Données manquantes et erronées injectées dans les fichiers sources

Environ 2 % des lignes des fichiers `3_donnees/csv` sont volontairement abîmées, comme dans de vraies sources.
Le chargement (`1_entrepot_sql/03_chargement_dw.sql`) les traite et note chaque cas dans la table `dw.JOURNAL_QUALITE`.
Liste exacte : `3_donnees/referentiels/anomalies_injectees.csv`. Lors du test, **le journal a retrouvé les 19 types
d'anomalies, avec exactement les mêmes nombres**.

| Fichier | Anomalie | Lignes | Traitement |
|---|---|---|---|
| employe.csv | profil de trajet manquant | 40 | complétée (« Profil non renseigné ») |
| employe.csv | libellé de service mal écrit (casse, espaces) | 120 | corrigée (libellé le plus fréquent du service) |
| employe.csv | domaine de la société manquant (2 sociétés) | 120 | complétée (« Non renseigné ») |
| employe.csv | ligne en double | 15 | doublon supprimé |
| produit.csv | marque manquante | 2 | complétée (« Non renseignée ») |
| exemplaire.csv | date de réforme antérieure à la mise en service | 5 | corrigée (date supprimée) |
| location.csv | durée nulle ou négative | 60 | rejetée |
| location.csv | durée aberrante (999 jours) | 25 | rejetée |
| location.csv | date future (2027) | 20 | rejetée |
| location.csv | employé inconnu | 20 | rejetée |
| location.csv | prix journalier manquant | 300 | complétée (prix du même produit, même pays, mois le plus proche) |
| location.csv | taux de réduction manquant | 200 | complétée (taux du même employé ou du même profil, même gamme, même année) |
| location.csv | taux saisi en pourcentage (15 au lieu de 0,15) | 150 | corrigée (divisé par 100) |
| location.csv | exemplaire loué deux fois en même temps | 30 | rejetée (on garde la location commencée la première) |
| location.csv | ligne en double | 250 | doublon supprimé |
| reservation.csv | nombre d'exemplaires manquant | 80 | complétée (1 exemplaire) |
| reservation.csv | date de réservation après la location prévue | 40 | rejetée |
| reservation.csv | produit inconnu | 15 | rejetée |
| reservation.csv | ligne en double | 100 | doublon supprimé |

## 5. Points à valider par le groupe

- **Domaine des sociétés allemandes** (réglage `DOMAINE_DE` du générateur, actuellement `True`) : le sujet du projet 2
  demande des « sociétés françaises et allemandes avec leur domaine », alors que le projet 1 n'en donnait pas aux
  sociétés allemandes. Avec `False`, elles apparaissent dans un domaine « Non renseigné ».
- Les **lois de probabilité** du § 2 et les **phénomènes** du § 3.
- Les **référentiels ajoutés** (sociétés, produits, agences, tarifs) : `3_donnees/referentiels/*.csv`, colonne `Origine`.

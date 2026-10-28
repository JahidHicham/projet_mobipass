# Vérité terrain — données du cube « Locations »

Ce fichier décrit ce qui a été **volontairement injecté** dans les données par le générateur
`3_donnees/gen_donnees_projet2.py` (graine fixe : les mêmes données à chaque exécution).
Il sert à vérifier que l'analyse OLAP retrouve bien ces phénomènes.

## 1. Origine et volumes

- Les données du projet 1 (`sql/ed/03_insertion_ED.sql`) sont **gardées telles quelles** : 20 sociétés, 403 employés,
  40 produits, 256 exemplaires, 5 100 locations, 1 000 réservations (non chargées : pas de fait Réservation). Seule exception : les 8 sociétés allemandes
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
| Locations | 62 649 (214 035 jours loués) | 60 000 |
| Période | 01/01/2023 → 13/10/2026 (2023, 2024, 2025 complètes) | 3 années complètes |
| Demandes refusées (simulées, absentes des fichiers sources) | 7 127 | — |

Tendance générale : l'activité française croît chaque année (8 385 locations en 2023, 12 418 en 2024, 17 374 en 2025),
avec l'arrivée de nouvelles sociétés clientes et un usage plus intensif. L'Allemagne démarre en janvier 2026.

Les fichiers sources sont **complets et cohérents** : pas de données manquantes ni erronées (consigne du prof). Seuls
des **phénomènes** ont été injectés, pour être retrouvés par l'analyse OLAP.

## 2. Lois de probabilité (réglages en tête du générateur, à valider par le groupe)

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
- **Simulé** : environ **10 % des demandes sont refusées** faute d'exemplaire libre (7 127 refus pour 62 649
  locations). Ces refus se concentrent en **juin (1 418)**, en **septembre (1 637, pic la semaine de la mobilité,
  semaines ISO 38-39)**, en mai et en juillet. Il y en a presque aucun en décembre (69). Où : Paris (vélos
  électriques urbains, 346 refus), Lyon (203), puis les trottinettes électriques en Allemagne (Leipzig, Cologne).
- **À observer dans le cube** (locations seules) : le produit n'est pas disponible quand tous ses exemplaires sont
  loués. **Taux de rupture** 2026 : **juin 42 %**, **septembre 43 %**, creux en août (27 %) ; semaines 38-39 :
  **50 % et 47 %** ; vélos cargo, trottinettes électriques et vélos électriques urbains en tête ; agences de Cologne,
  Leipzig, Paris et Lyon. Vérifié contre un calcul SQL exact (mêmes chiffres au mois).

### P2 — Concentration d'une gamme dans une région
- **Règle** : les VTT électriques sont 4 fois plus demandés par les employés d'Auvergne-Rhône-Alpes.
- **À observer** : les VTT électriques représentent **19 % des locations en Auvergne-Rhône-Alpes**, contre **6 % ailleurs**.

### P3 — Comportement selon la classe de trajet (séquence S2)
- **Règle** : trajets longs = locations longues mais moins fréquentes ; intermodal = locations courtes, plus fréquentes,
  surtout des vélos pliants et des trottinettes. Les remises dépendent aussi de la classe (trajet court ≈ 5-10 %, trajet long ≈ 18-25 %).

| Classe de trajet | Durée moyenne | Locations par employé |
|---|---|---|
| Trajet court | 2,5 jours | 17,0 |
| Trajet moyen | 4,3 jours | 18,3 |
| Trajet long | 10,6 jours | 12,9 |
| Trajet intermodal | 1,9 jour | 27,9 |

### P4 — Évolution de sociétés clientes (piste pour la séquence S3)
- **Seine Digital Factory** (Issy-les-Moulineaux) arrive en mars 2024 et recrute jusqu'à fin 2025 :
  417 locations en 2024, **1 144 en 2025 (× 2,7)**, 1 338 de janvier à mi-octobre 2026.
- **Provence Banque Régionale** (Aix-en-Provence) met en place sa propre flotte de vélos en avril 2025 : ses locations
  chutent de 80 % à partir de cette date (553 en 2023, 645 en 2024, **260 en 2025**, 135 en 2026).

### P5 — Écart France / Allemagne (piste pour la séquence S3)
- **Règle** : l'Allemagne démarre en janvier 2026 ; locations 1,5 fois plus longues ; plus de vélos cargo et de trottinettes électriques.
- **À observer en 2026** : montée en charge mois par mois (46 locations en janvier, 1 370 en juin) ; durée moyenne
  **4,2 jours en Allemagne contre 3,3 en France** ; vélos cargo **12,2 % des locations allemandes contre 6,1 %**.

### P6 — Grandes vacances : creux d'été et pic de rentrée (S1 ou S3)
- **Règle** : en France, août est le mois le plus calme de l'été (poids 0,9) et septembre repart fort (1,45, plus la
  semaine de la mobilité). En Allemagne, il n'y a pas de creux national : chaque Land a ses propres vacances d'été,
  décalées (règle à long terme de la KMK, 2026), pendant lesquelles ses employés louent beaucoup moins (× 0,35).
- **À observer** : France 2026 : **2 524 locations en juin, 1 403 en août, 2 453 en septembre**. Allemagne, locations
  par semaine ISO de 2026 (croiser Land × semaine) :

| Land | Vacances d'été 2026 | Avant | Pendant les vacances | Après |
|---|---|---|---|---|
| Nordrhein-Westfalen | 20/07 → 01/09 (semaines 30 à 35) | ≈ 115 par semaine | ≈ 55 | ≈ 130 |
| Sachsen | 04/07 → 14/08 (semaines 28 à 33) | ≈ 95 | ≈ 45 | ≈ 100 |
| Bayern | 03/08 → 14/09 (semaines 32 à 37) | ≈ 40 | ≈ 19 | ≈ 50 (semaine 38) |

  Les autres Länder ont trop peu d'employés pour que le creux soit net.

## 4. Points à valider par le groupe

- **Domaine des sociétés allemandes** (réglage `DOMAINE_DE` du générateur, actuellement `True`) : le sujet du projet 2
  demande des « sociétés françaises et allemandes avec leur domaine », alors que le projet 1 n'en donnait pas aux
  sociétés allemandes. Avec `False`, elles apparaissent dans un domaine « Non renseigné ».
- Les **lois de probabilité** du § 2 et les **phénomènes** du § 3.
- Les **référentiels ajoutés** (sociétés, produits, agences, tarifs) : `3_donnees/referentiels/*.csv`, colonne `Origine`.

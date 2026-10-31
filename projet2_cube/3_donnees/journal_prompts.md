# Journal des prompts — génération des données du cube « Locations »

Ce journal retrace les demandes faites à un assistant IA pour écrire le générateur
`gen_donnees_projet2.py`, dans l'ordre où le travail a avancé. Les échanges ont été regroupés et
reformulés par étape pour être lisibles ; chaque prompt est suivi de ce que nous avons vérifié avant de
passer au suivant.

Le résultat attendu est décrit dans `../4_verite_terrain.md` (phénomènes injectés et valeurs à retrouver
dans le cube).

Les chemins cités dans les prompts sont ceux du dépôt au moment des échanges. Depuis, les fichiers du projet 1 ont
été rangés dans `projet1_oracle/` : `sql/ed/…` se trouve dans `projet1_oracle/sql/ed/…` et `docs/Location_MD.json`
dans `projet1_oracle/docs/Location_MD.json`.

---

## Prompt 1 — Cadrage : partir des données du projet 1

> Nous avons un générateur Python (`sql/ed/gen_donnees.py`) qui produit le jeu de données Oracle du
> projet 1 (`sql/ed/03_insertion_ED.sql`). Pour le projet 2, écris un nouveau script
> `gen_donnees_projet2.py` qui :
> - relit `03_insertion_ED.sql` et garde ces données **telles quelles** (aucune ligne modifiée ni supprimée) ;
> - les complète jusqu'aux minimums du sujet : 40 sociétés sur au moins 5 régions, 3 000 employés,
>   60 produits sur au moins 3 secteurs, 400 exemplaires, 60 000 locations sur au moins 3 années complètes ;
> - couvre la période du 01/01/2023 au 13/10/2026 (la date de génération du projet 1 est le 14/10/2026) ;
>   2023, 2024 et 2025 sont donc les trois années complètes ;
> - écrit des fichiers CSV (UTF-8 avec BOM pour qu'Excel affiche les accents, en-tête, séparateur virgule)
>   pour un chargement par `BULK INSERT` dans
>   notre entrepôt SQL Server ;
> - utilise une graine aléatoire fixe, pour que deux exécutions donnent exactement les mêmes fichiers.
>
> Les colonnes des CSV doivent suivre notre conception du cube (`docs/Location_MD.json`) :
> `employe.csv`, `produit.csv`, `exemplaire.csv` et `location.csv`.

**Vérifié** : les 5 100 locations du projet 1 sont présentes sans changement (contrôle intégré au script,
voir prompt 7).

---

## Prompt 2 — Référentiels ajoutés

> Pour atteindre les volumes, il faut de nouvelles sociétés, de nouveaux produits et des agences. Ajoute-les
> sous forme de référentiels lisibles, que le groupe pourra relire :
> - **Géographie** : uniquement des codes réels — codes INSEE (commune, département, région) pour la France,
>   codes AGS de Destatis (Gemeinde, Kreis, District, Land) pour l'Allemagne — en respectant la hiérarchie des
>   zones du projet 1.
> - **Domaines d'activité** : nomenclature NAF rév. 2 sur 4 niveaux. Pour les sociétés allemandes, prends
>   l'équivalent NACE de leur code WZ 2008 (identiques jusqu'à la classe) ; prévois un réglage `DOMAINE_DE`
>   pour pouvoir revenir au projet 1, où elles n'avaient pas de domaine.
> - **Sociétés** : noms fictifs, mais commune, catégorie juridique, domaine et nombre d'employés réalistes.
>   SIREN valide (clé de Luhn) pour la France, format `DE` + 9 chiffres pour l'Allemagne.
> - **Produits** : marques réelles du marché, générations, prix publics HT réalistes ; les produits doivent
>   couvrir au moins 3 secteurs parmi ceux qui sont réellement loués.
> - **Tarifs** : ajoute l'année 2023 (absente du projet 1) pour tous les produits, avec la même règle de prix :
>   TTC en France, HT en Allemagne, périodes de tarif sans chevauchement.
> - **Réductions** : ajoute 2023 avec la règle du projet 1 (selon la classe de trajet et le secteur, +1 point
>   par an), taux dans ]0 ; 1].
> - **Agences** : une agence de rattachement par région ou Land où se trouvent les sociétés.
>
> Écris ces référentiels dans un dossier `referentiels/` avec une colonne `Origine` (projet 1 ou ajout projet 2).

**Vérifié** : hiérarchie des zones cohérente (une commune dans un département, un département dans une
région, etc.) et référentiels relus dans `referentiels/`.

---

## Prompt 3 — Employés et profils de trajet

> Génère les employés des nouvelles sociétés :
> - prénoms et noms français ou allemands selon le pays, services traduits (Direction / Geschäftsführung…) ;
> - la répartition des catégories de trajet du projet 1 (TC, TM, TL, TI), mais modulée selon la commune :
>   en **ville dense**, plus de trajets courts et intermodaux ; en **périurbain**, plus de trajets moyens et longs ;
> - une date d'inscription au service, pour que les sociétés arrivent progressivement.
>
> Donne à chaque employé un comportement stable : une agence de rattachement (selon la région ou le Land de
> sa société) et un poids de location qui crée de gros et de petits loueurs (25 % louent 6 fois plus,
> 30 % louent 3 fois moins). C'est plus réaliste qu'une demande uniforme.

**Vérifié** : 3 528 employés au total ; répartition des classes de trajet proche du projet 1.

---

## Prompt 4 — Simulation de la demande, jour par jour

> Simule les locations jour par jour du 01/01/2023 au 13/10/2026 :
> - nombre de demandes par jour tiré selon une **loi de Poisson**, dont la moyenne dépend du pays, de l'année
>   (croissance de l'usage : × 1,0 / 1,05 / 1,1 / 1,15), du mois, du jour de la semaine (week-end faible) et
>   de la somme des poids des employés actifs ;
> - l'employé qui demande est tiré selon son poids ; la **gamme** selon la popularité observée au projet 1,
>   modifiée par sa classe de trajet ; puis un produit de cette gamme proposé par son agence ;
> - la **durée** dépend de la classe de trajet (trajet long : locations longues mais moins fréquentes ;
>   intermodal : locations courtes et plus fréquentes) ;
> - on cherche un **exemplaire libre** du produit dans l'agence, sinon un autre produit de la même gamme.
>   Si aucun n'est libre, la demande est **refusée** et aucune location n'est créée.
>
> Garantis les règles du dictionnaire : un exemplaire n'est jamais loué deux fois en même temps, pas de
> location avant sa mise en service ni après sa réforme, durée > 0, employé inscrit à la date de location,
> exemplaire du même pays que l'employé. Le montant payé est toujours inférieur au montant public
> (prix du tarif en vigueur × durée, moins la réduction du profil).
>
> Mets tous les réglages (poids, taux, durées) en constantes en tête du script, commentées, pour que le
> groupe puisse les discuter.

**Vérifié** : volume obtenu, et aucune erreur dans la partie contrôle (voir prompt 7).

---

## Prompt 5 — Dimensionnement du parc d'exemplaires

> Le parc doit être cohérent avec la demande, sinon les refus seront partout ou nulle part. Calcule la
> demande attendue (en jours de location) par agence et par gamme, et dimensionne le parc en proportion,
> avec une taille visée par pays (600 en France, 240 en Allemagne). Le parc du projet 1 est déjà là :
> compte-le au prorata de sa durée de service et n'ajoute que la différence.
>
> En France, le parc grandit par vagues, chaque hiver avant la saison (2022, début 2024, début 2025), avec
> quelques réformes. En Allemagne, mise en service entre décembre 2025 et mars 2026.
> Chaque agence a au moins 8 exemplaires et chaque produit louable au moins un exemplaire.

**Problèmes rencontrés et corrigés** : une agence sans exemplaire faisait planter le tirage (d'où le
minimum de 8) ; avec un parc fixe dès 2023, le volume restait sous les 60 000 locations, d'où la croissance
par vagues et la pondération par durée de service.

**Vérifié** : 968 exemplaires dans 15 agences ; plus de 60 000 locations.

---

## Prompt 6 — Phénomènes à injecter (P1 à P5)

> Injecte des phénomènes que l'analyse OLAP devra retrouver. Chacun doit être réglé par une constante et
> documenté :
> - **P1 – Saisonnalité et saturation (séquence S1)** : poids par mois (pic d'avril à juin et en septembre,
>   creux en hiver), demande × 1,7 pendant la semaine européenne de la mobilité (16-22 septembre). Parc
>   volontairement sous-dimensionné à Paris (vélos électriques urbains à 55 %, vélos cargo à 60 %) et à
>   Lyon (vélos électriques urbains à 60 %).
> - **P2 – Concentration régionale** : les VTT électriques sont 4 fois plus demandés en Auvergne-Rhône-Alpes.
> - **P3 – Profils de trajet (séquence S2)** : durées et fréquences différentes selon la classe ; les
>   intermodaux préfèrent les vélos pliants et les trottinettes, les trajets longs les vélos électriques et
>   les vélos de route.
> - **P4 – Évolution de sociétés clientes** : Seine Digital Factory arrive en mars 2024 et recrute jusqu'à
>   fin 2025 ; Provence Banque Régionale s'équipe d'une flotte interne en avril 2025 (demande × 0,2 ensuite).
> - **P5 – Écart France / Allemagne** : l'offre allemande démarre le 05/01/2026, avec des locations 1,5 fois
>   plus longues et davantage de vélos cargo et de trottinettes électriques.

**Vérifié** sur les fichiers puis dans le cube : pics de juin et septembre, VTT électriques à 19 % des
locations en Auvergne-Rhône-Alpes contre 6 % ailleurs, durée moyenne de 10,4 jours pour les trajets longs,
× 2,8 pour Seine Digital Factory entre 2024 et 2025, chute de Provence Banque Régionale.

---

## Prompt 7 — Contrôles intégrés au générateur

> Ajoute à la fin du script une partie « contrôles » qui vérifie, avant d'écrire les CSV, toutes les règles
> du sujet et du dictionnaire de données : clés uniques, pas de chevauchement sur un exemplaire, dates de
> location dans la période de service de l'exemplaire, tarif et réduction trouvés pour chaque location, taux
> dans ]0 ; 1], tarifs sans chevauchement, prix de location inférieur au prix de vente, hiérarchie des zones
> et format des codes (SIREN, NAF), et les volumes minimaux du sujet. Le script affiche la liste des
> erreurs, ou « aucune ».

**Vérifié** : « ERREURS : aucune ». Les mêmes règles sont recontrôlées après chargement par
`1_entrepot_sql/04_controles_entrepot.sql`.

---

## Prompt 8 — Correction après l'échange avec le professeur

Nous avions d'abord compris qu'il fallait des données manquantes ou erronées à nettoyer au chargement.
Après présentation du cube, le professeur a précisé qu'il attendait des données **propres** avec des
**phénomènes visibles**, et un seul fait (Location) : le manque de produit doit se lire dans le cube à partir
des locations seules.

> Retire toutes les anomalies injectées : les fichiers sources doivent être complets et cohérents. Ne garde
> que les phénomènes. Ne produis plus de fichier de réservations : le fait Réservation est abandonné.
> Les demandes refusées restent simulées (elles créent les ruptures) mais n'apparaissent dans aucun fichier.
>
> Ajoute un phénomène **P6 – Grandes vacances** : en France, août est le mois le plus calme de l'été, puis
> forte reprise en septembre. En Allemagne, il n'y a pas de creux national : chaque Land a ses propres
> vacances d'été (dates 2026 de la conférence des ministres de l'Éducation, KMK, environ 6 semaines),
> pendant lesquelles ses employés louent beaucoup moins (× 0,35).

**Vérifié** : France 2026 : 2 602 locations en juin, 1 468 en août, 2 455 en septembre. Creux visible par
semaine ISO en Rhénanie-du-Nord-Westphalie (semaines 30 à 35), en Saxe (28 à 33) et en Bavière (32 à 37).

---

## Prompt 9 — Phénomène P7 pour la séquence S3 (proposé par Sami Carrere)

> Pour la séquence S3 « Lancement en Allemagne », ajoute un phénomène P7 sans casser les phénomènes P1 à P6
> ni les résultats des requêtes déjà écrites :
> - **P7a – Villes-États** : à Berlin, Hambourg et Brême, les employés louent comme en France (pas de durée
>   × 1,5 ni de surplus de vélos cargo et de trottinettes), et 1,3 fois plus souvent. Ajoute une société à
>   Berlin et une à Hambourg.
> - **P7b – Décrochage de la Bavière** : les VTT électriques y sont 4 fois plus demandés (comme en
>   Auvergne-Rhône-Alpes), mais l'agence de Munich n'en a que 20 % du parc nécessaire. Chaque refus
>   décourage l'employé : sa demande est divisée par 2, avec un plancher à 10 %. Ajoute une société à Munich.
> - Porte le parc allemand visé de 240 à 320 exemplaires pour suivre la demande supplémentaire.

**Vérifié** : villes-États à 2,7 jours de durée moyenne contre 3,9 dans les autres Länder ; taux de rupture
des VTT électriques à Munich de 71 %, en hausse chaque mois de février à juin ; baisse de l'usage par
employé en Bavière à partir de mai. Les requêtes S1 et S2 donnent toujours les mêmes tendances.

---

## Prompt 10 — Indicateurs de contrôle et chargement à la faculté

> Ajoute à la fin du script le calcul des indicateurs de chaque phénomène, avec les mêmes définitions que les
> membres calculés du cube (taux de rupture, durée moyenne, locations par employé actif), pour pouvoir
> remplir le fichier « vérité terrain » et comparer avec les résultats MDX.
>
> Le serveur de la faculté (etu-mssql3) ne voit pas les fichiers de notre PC, donc `BULK INSERT` y est
> impossible. Génère aussi `03_chargement_dw_fac.sql`, qui fait le même chargement que
> `03_chargement_dw.sql` mais avec les données en `INSERT` (1 000 lignes par instruction).

**Vérifié** : 67 595 locations et 222 433 jours loués, identiques dans les CSV, dans l'entrepôt et dans le
cube ; les valeurs du fichier « vérité terrain » sont celles retrouvées par les requêtes MDX.

---

## Volumes finaux

| Élément | Obtenu | Minimum du sujet |
|---|---|---|
| Sociétés | 51 (31 FR, 20 DE) | 40 |
| Régions et Länder | 21 | 5 |
| Employés | 3 528 | 3 000 |
| Produits | 77, dont 62 loués | 60 |
| Secteurs des produits loués | 3 | 3 |
| Exemplaires | 968 | 400 |
| Locations | 67 595 | 60 000 |
| Années complètes | 2023, 2024, 2025 | 3 |

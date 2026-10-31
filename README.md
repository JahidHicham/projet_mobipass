# projet_mobipass

Projet MobiPass, M2 IDA, cours « Conception et développement de BD décisionnelles ». Soutenance le 30/10/2026.

Le dépôt contient les deux projets, chacun dans son dossier.

| Dossier | Projet | Contenu |
|---|---|---|
| `projet1_oracle/` | Projet 1 : entrepôt Oracle, magasins de données et Power BI | `sql/` scripts (`ed/` entrepôt, `md_locations/` et `md_ventes/` magasins) · `data/` fichiers sources (INSEE, Destatis…) · `docs/` schémas, dictionnaires et MCD Looping · `powerbi/` rapports · `soutenance/` dossier de conception et guide d'utilisation des outils d'analyse |
| `projet2_cube/` | Projet 2 : cube OLAP « Locations » sous SQL Server, SSAS et MDX | scripts de l'entrepôt `dw`, projet du cube, données et génération, vérité terrain, requêtes MDX : voir [projet2_cube/README.md](projet2_cube/README.md) |

Le générateur du projet 2 (`projet2_cube/3_donnees/gen_donnees_projet2.py`) reprend les données du projet 1 dans
`projet1_oracle/sql/ed/03_insertion_ED.sql`.

-- =====================================================================
-- MobiPass - Magasin MD2 « Achat_MD » (ventes) : R-OLAP dénormalisé sous Oracle 11g
-- Noms alignés sur le schéma multidimensionnel (MobiPass_MD2_Achat_MD.json) et sur Location_MD.
-- Tables ensuite importées dans Power BI ; filtre par pays = sécurité RLS sur DIM_EMPLOYE_MD2.CodePays.
-- À lancer APRÈS 01, 02 et 03 (l'entrepôt _DW doit être chargé).
-- Démarche du cours (F. Ravat, Modélisation physique, SGBD Oracle) :
--   1. dimension = CREATE MATERIALIZED VIEW + PRIMARY KEY + CREATE DIMENSION
--   2. fait      = CREATE MATERIALIZED VIEW + PRIMARY KEY + FOREIGN KEY
--   3. agrégats  = treillis partiel de vues matérialisées (rapports B4.1, B4.2, B4.3)
-- Jointures écrites dans le WHERE ; jointures externes avec (+).
-- Rafraîchissement après chaque alimentation de l'ED :
--   EXEC DBMS_MVIEW.REFRESH('DIM_TEMPS_MD2,DIM_PRODUIT_MD2,DIM_EMPLOYE_MD2,DIM_METIER_MD2,FAIT_ACHAT_MD2,MV_ACH_GAM_REG_MOIS,MV_ACH_PAYS_MOIS,MV_ACH_TYPE_CJ_TRIM');
-- Remarque : DATE est un mot réservé d'Oracle, le paramètre « Date » du schéma devient la colonne DateJour.
--
-- Modifications par rapport à la version précédente (repérées [MODIF] dans le code) :
--   M1. Nouvelle mesure Montant_Achat_ReelPaye_TTC_MD : montant réellement payé par l'employé, TTC
--       (même convention que Location_MD). Le bénéfice reste HT (la TVA n'est pas un gain pour MobiPass).
--   M2. Métier à la date d'achat : MAX ... KEEP (DENSE_RANK LAST) au lieu d'une sous-requête simple,
--       pour ne plus planter (ORA-01427) si deux périodes de métier se chevauchent (le plus récent l'emporte).
--   M3. Tranche d'âge calculée à la date du rafraîchissement (âge actuel) et non au début de l'affectation.
--   M4. Statut « Arrêtée » seulement si la date d'arrêt est passée (une date d'arrêt future = encore commercialisée).
--   M5. IdVersionEmploye = CodeE || '_' || date de début d'affectation : clé stable d'un rafraîchissement
--       à l'autre (ROW_NUMBER renumérotait toutes les versions dès qu'une affectation était ajoutée).
--   M6. Contrôles supplémentaires : chevauchements (affectations, métiers, tarifs) et achats non chargés.
-- =====================================================================

BEGIN
  FOR d IN (SELECT dimension_name FROM user_dimensions
            WHERE dimension_name IN ('TEMPS_MD2_DIM','PRODUIT_MD2_DIM','EMPLOYE_MD2_DIM','METIER_MD2_DIM')) LOOP
    EXECUTE IMMEDIATE 'DROP DIMENSION ' || d.dimension_name;
  END LOOP;
  FOR v IN (SELECT mview_name FROM user_mviews
            WHERE mview_name IN ('MV_ACH_PAYS_MOIS','MV_ACH_GAM_REG_MOIS','MV_ACH_TYPE_CJ_TRIM','FAIT_ACHAT_MD2',
                                 'DIM_TEMPS_MD2','DIM_PRODUIT_MD2','DIM_EMPLOYE_MD2','DIM_METIER_MD2')
            ORDER BY DECODE(mview_name,'MV_ACH_PAYS_MOIS',1,'MV_ACH_GAM_REG_MOIS',2,'MV_ACH_TYPE_CJ_TRIM',3,'FAIT_ACHAT_MD2',4,5)) LOOP
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || v.mview_name;
  END LOOP;
END;
/

-- =====================================================================
-- 1. DIMENSION Temps_MD : H_MOIS (jour -> mois -> trimestre -> année)
--    Mois = 'YYYY-MM' (et non le numéro du mois seul, sinon Mois -> Annee n'est pas une dépendance fonctionnelle)
-- =====================================================================
CREATE MATERIALIZED VIEW DIM_TEMPS_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT DISTINCT a.DateA                                                     AS DateJour,
                   TO_CHAR(a.DateA, 'YYYY-MM')                                  AS Mois,
                   TO_CHAR(a.DateA, 'FMMonth YYYY', 'NLS_DATE_LANGUAGE=FRENCH') AS LibMois,
                   TO_CHAR(a.DateA, 'YYYY-"T"Q')                                AS Trimestre,
                   TO_CHAR(a.DateA, 'YYYY')                                     AS Annee
   FROM ACHAT_DW a;

ALTER TABLE DIM_TEMPS_MD2 ADD CONSTRAINT pk_dim_temps_md2 PRIMARY KEY (DateJour);

CREATE DIMENSION TEMPS_MD2_DIM
   LEVEL N_Date      IS (DIM_TEMPS_MD2.DateJour)
   LEVEL N_Mois      IS (DIM_TEMPS_MD2.Mois)
   LEVEL N_Trimestre IS (DIM_TEMPS_MD2.Trimestre)
   LEVEL N_Annee     IS (DIM_TEMPS_MD2.Annee)
HIERARCHY H_MOIS (N_Date CHILD OF N_Mois CHILD OF N_Trimestre CHILD OF N_Annee)
ATTRIBUTE N_Mois DETERMINES DIM_TEMPS_MD2.LibMois;

-- =====================================================================
-- 2. DIMENSION Produit_MD
--    H_GAMME (produit -> gamme -> secteur), H_MAR (-> marque), H_AUTONOMIE (-> classe d'autonomie, électriques seulement : 0,1),
--    H_GENERATION (-> génération -> fabricant -> pays du fabricant), H_STATUT (-> génération -> commercialisée / arrêtée)
-- =====================================================================
CREATE MATERIALIZED VIEW DIM_PRODUIT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT p.CodeP        AS CodeProduit,
          p.NomP         AS NomProduit,
          p.DescriptifP  AS DescriptifProduit,
          p.PoidsKg      AS PoidsKgProduit,
          p.AutonomieKm  AS AutonomieKilometreProduit,
          p.MarqueP      AS MarqueProduit,
          CASE WHEN p.AutonomieKm IS NULL THEN NULL
               WHEN p.AutonomieKm <= 30   THEN 'Jusqu''à 30 km'
               WHEN p.AutonomieKm <= 70   THEN '31 à 70 km'
               ELSE 'Plus de 70 km' END                                         AS ClasseAutonomie,
          g.CodeG        AS CodeGamme,
          g.NomG         AS NomGamme,
          g.SecteurG     AS SecteurProduit,
          ge.CodeGEN     AS CodeGeneration,
          ge.NomGEN      AS NomGeneration,
          ge.DateSortieGEN AS DateSortieGeneration,
          ge.DateArretGEN  AS DateArretGeneration,
          -- [MODIF M4] une date d'arrêt future = génération encore commercialisée
          CASE WHEN ge.DateArretGEN IS NOT NULL AND ge.DateArretGEN <= SYSDATE
               THEN 'Arrêtée' ELSE 'Commercialisée' END                         AS StatutGeneration,
          f.CodeFAB      AS CodeFabricant,
          f.NomFAB       AS NomFabricant,
          f.PaysFAB      AS PaysFabricant
   FROM PRODUIT_DW p, GAMME_DW g, GENERATION_DW ge, FABRICANT_DW f
   WHERE p.CodeG = g.CodeG
     AND p.CodeGEN = ge.CodeGEN
     AND ge.CodeFAB = f.CodeFAB;

ALTER TABLE DIM_PRODUIT_MD2 ADD CONSTRAINT pk_dim_produit_md2 PRIMARY KEY (CodeProduit);

CREATE DIMENSION PRODUIT_MD2_DIM
   LEVEL N_CodeProduit      IS (DIM_PRODUIT_MD2.CodeProduit)
   LEVEL N_CodeGamme        IS (DIM_PRODUIT_MD2.CodeGamme)
   LEVEL N_SecteurProduit   IS (DIM_PRODUIT_MD2.SecteurProduit)
   LEVEL N_MarqueProduit    IS (DIM_PRODUIT_MD2.MarqueProduit)
   LEVEL N_ClasseAutonomie  IS (DIM_PRODUIT_MD2.ClasseAutonomie) SKIP WHEN NULL
   LEVEL N_CodeGeneration   IS (DIM_PRODUIT_MD2.CodeGeneration)
   LEVEL N_StatutGeneration IS (DIM_PRODUIT_MD2.StatutGeneration)
   LEVEL N_CodeFabricant    IS (DIM_PRODUIT_MD2.CodeFabricant)
   LEVEL N_PaysFabricant    IS (DIM_PRODUIT_MD2.PaysFabricant)
HIERARCHY H_GAMME      (N_CodeProduit CHILD OF N_CodeGamme CHILD OF N_SecteurProduit)
HIERARCHY H_MAR        (N_CodeProduit CHILD OF N_MarqueProduit)
HIERARCHY H_AUTONOMIE  (N_CodeProduit CHILD OF N_ClasseAutonomie)
HIERARCHY H_GENERATION (N_CodeProduit CHILD OF N_CodeGeneration CHILD OF N_CodeFabricant CHILD OF N_PaysFabricant)
HIERARCHY H_STATUT     (N_CodeProduit CHILD OF N_CodeGeneration CHILD OF N_StatutGeneration)
ATTRIBUTE N_CodeProduit    DETERMINES DIM_PRODUIT_MD2.NomProduit
ATTRIBUTE N_CodeProduit    DETERMINES DIM_PRODUIT_MD2.DescriptifProduit
ATTRIBUTE N_CodeProduit    DETERMINES DIM_PRODUIT_MD2.PoidsKgProduit
ATTRIBUTE N_CodeProduit    DETERMINES DIM_PRODUIT_MD2.AutonomieKilometreProduit
ATTRIBUTE N_CodeGamme      DETERMINES DIM_PRODUIT_MD2.NomGamme
ATTRIBUTE N_CodeGeneration DETERMINES DIM_PRODUIT_MD2.NomGeneration
ATTRIBUTE N_CodeGeneration DETERMINES DIM_PRODUIT_MD2.DateSortieGeneration
ATTRIBUTE N_CodeGeneration DETERMINES DIM_PRODUIT_MD2.DateArretGeneration
ATTRIBUTE N_CodeFabricant  DETERMINES DIM_PRODUIT_MD2.NomFabricant;

-- =====================================================================
-- 3. DIMENSION Metier_MD : H_ROME sur 4 niveaux (sujet p. 5, RG8)
--    + un membre « Non renseigné » (code NR) pour les salariés allemands et les employés sans fiche RH
-- =====================================================================
CREATE MATERIALIZED VIEW DIM_METIER_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT ap.CodeAPP      AS CodeAppellation,
          ap.LibelleAPP   AS LibelleAppellation,
          fm.CodeROME     AS CodeROME,
          fm.LibelleMetier AS LibelleMetier,
          dp.CodeDP       AS CodeDomainePro,
          dp.LibelleDP    AS LibelleDomainePro,
          gd.CodeGD       AS CodeGrandDomaine,
          gd.LibelleGD    AS LibelleGrandDomaine
   FROM APPELLATION_DW ap, FICHE_METIER_DW fm, DOMAINE_PRO_DW dp, GRAND_DOMAINE_DW gd
   WHERE ap.CodeROME = fm.CodeROME
     AND fm.CodeDP = dp.CodeDP
     AND dp.CodeGD = gd.CodeGD
   UNION ALL
   SELECT 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné', 'NR', 'Non renseigné'
   FROM dual;

ALTER TABLE DIM_METIER_MD2 ADD CONSTRAINT pk_dim_metier_md2 PRIMARY KEY (CodeAppellation);

CREATE DIMENSION METIER_MD2_DIM
   LEVEL N_CodeAppellation  IS (DIM_METIER_MD2.CodeAppellation)
   LEVEL N_CodeROME         IS (DIM_METIER_MD2.CodeROME)
   LEVEL N_CodeDomainePro   IS (DIM_METIER_MD2.CodeDomainePro)
   LEVEL N_CodeGrandDomaine IS (DIM_METIER_MD2.CodeGrandDomaine)
HIERARCHY H_ROME (N_CodeAppellation CHILD OF N_CodeROME CHILD OF N_CodeDomainePro CHILD OF N_CodeGrandDomaine)
ATTRIBUTE N_CodeAppellation  DETERMINES DIM_METIER_MD2.LibelleAppellation
ATTRIBUTE N_CodeROME         DETERMINES DIM_METIER_MD2.LibelleMetier
ATTRIBUTE N_CodeDomainePro   DETERMINES DIM_METIER_MD2.LibelleDomainePro
ATTRIBUTE N_CodeGrandDomaine DETERMINES DIM_METIER_MD2.LibelleGrandDomaine;

-- =====================================================================
-- 4. DIMENSION Employe_MD (société incluse) : à évolution lente de type 2 (une version par affectation, RG14)
--    H_Categorie    : version -> employé -> catégorie -> super-catégorie (classe de trajet)
--    H_Age          : version -> tranche d'âge (âge actuel, calculé depuis la fiche RH ; vide sans fiche, RG19)
--    H_Type_Societe : version -> service -> société -> type (micro, PME, ETI, GE : chaque société en a un)
--    H_CJ           : version -> service -> société -> catégorie juridique niveau 3 -> 2 -> 1
--    H_NAF          : version -> service -> société -> sous-classe -> classe -> groupe -> division (vide en DE)
--    H_France / H_Allemagne / H_District : géographie dépliée depuis ZONE_GEO_DW, convergente sur CodeRegion
--                   (région française ou Land allemand) puis CodePays
--    Jointures externes (+) : la fiche RH, le NAF et le Land au-dessus d'un district peuvent manquer.
--    Pas de ENABLE QUERY REWRITE sur cette vue : l'usage de SYSDATE y est donc autorisé.
-- =====================================================================
CREATE MATERIALIZED VIEW DIM_EMPLOYE_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT -- [MODIF M5] clé de version stable : employé + date de début d'affectation
          e.CodeE || '_' || TO_CHAR(a.DateDebutAffect, 'YYYYMMDD')            AS IdVersionEmploye,
          a.DateDebutAffect                                                    AS DateDebutVersion,
          a.DateFinAffect                                                      AS DateFinVersion,
          e.CodeE AS CodeEmploye, e.NomE AS NomEmploye, e.PrenomE AS PrenomEmploye,
          c.CodeCAT AS CodeCategorie, c.NomCAT AS NomCategorie, c.SuperCAT AS SuperCategorie,
          -- [MODIF M3] âge actuel (recalculé à chaque rafraîchissement)
          CASE WHEN rh.DateNaissSAL IS NULL THEN NULL
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 30 * 12 THEN 'Moins de 30 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 40 * 12 THEN '30 à 39 ans'
               WHEN MONTHS_BETWEEN(SYSDATE, rh.DateNaissSAL) < 50 * 12 THEN '40 à 49 ans'
               ELSE '50 ans et plus' END                                       AS TrancheAge,
          s.CodeSE AS CodeService, s.NomSE AS NomService,
          so.CodeSOC AS CodeSociete, so.NomSOC AS NomSociete,
          ty.CodeTy, ty.LibelleTypeSoc,
          c3.CodeCJ AS CodeCJ3, c3.LibelleCJ AS LibelleCJ3,
          c2.CodeCJ AS CodeCJ2, c2.LibelleCJ AS LibelleCJ2,
          c1.CodeCJ AS CodeCJ1, c1.LibelleCJ AS LibelleCJ1,
          d1.CodeDO AS SousClasseNAF, d1.NomDO AS LibelleNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 5 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 5 THEN d3.CodeDO END)         AS ClasseNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 4 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 4 THEN d3.CodeDO END,
                   CASE WHEN LENGTH(d4.CodeDO) = 4 THEN d4.CodeDO END)         AS GroupeNAF,
          COALESCE(CASE WHEN LENGTH(d2.CodeDO) = 2 THEN d2.CodeDO END,
                   CASE WHEN LENGTH(d3.CodeDO) = 2 THEN d3.CodeDO END,
                   CASE WHEN LENGTH(d4.CodeDO) = 2 THEN d4.CodeDO END)         AS DivisionNAF,
          CASE WHEN z1.NiveauZG = 'COMMUNE'  THEN z1.CodeZG END                AS CodeVille,
          CASE WHEN z1.NiveauZG = 'COMMUNE'  THEN z1.NomZG  END                AS NomVille,
          CASE WHEN z1.NiveauZG = 'COMMUNE'  THEN z2.CodeZG END                AS CodeDepartement,
          CASE WHEN z1.NiveauZG = 'COMMUNE'  THEN z2.NomZG  END                AS NomDepartement,
          CASE WHEN z1.NiveauZG = 'GEMEINDE' THEN z1.CodeZG END                AS CodeGemeinde,
          CASE WHEN z1.NiveauZG = 'GEMEINDE' THEN z1.NomZG  END                AS NomGemeinde,
          CASE WHEN z1.NiveauZG = 'GEMEINDE' THEN z2.CodeZG END                AS CodeKreis,
          CASE WHEN z1.NiveauZG = 'GEMEINDE' THEN z2.NomZG  END                AS NomKreis,
          CASE WHEN z3.NiveauZG = 'DISTRICT' THEN z3.CodeZG END                AS CodeDistrict,
          CASE WHEN z3.NiveauZG = 'DISTRICT' THEN z3.NomZG  END                AS NomDistrict,
          CASE WHEN z3.NiveauZG = 'DISTRICT' THEN z4.CodeZG ELSE z3.CodeZG END AS CodeRegion,
          CASE WHEN z3.NiveauZG = 'DISTRICT' THEN z4.NomZG  ELSE z3.NomZG  END AS NomRegion,
          pa.CodePays, pa.NomPays, pa.TauxTVA
   FROM EMPLOYE_DW e, CATEGORIE_DW c, SALARIE_RH_DW rh, ETRE_AFFECTE_DW a, SERVICE_DW s, SOCIETE_DW so,
        TYPE_SOCIETE_DW ty,
        CATEGORIE_JURIDIQUE_DW c3, CATEGORIE_JURIDIQUE_DW c2, CATEGORIE_JURIDIQUE_DW c1,
        DOMAINE_DW d1, DOMAINE_DW d2, DOMAINE_DW d3, DOMAINE_DW d4,
        ZONE_GEO_DW z1, ZONE_GEO_DW z2, ZONE_GEO_DW z3, ZONE_GEO_DW z4, PAYS_DW pa
   WHERE e.CodeCAT = c.CodeCAT
     AND e.CodeE = rh.CodeE(+)                                   -- fiche RH facultative (RG19)
     AND e.CodeE = a.CodeE
     AND a.CodeSE = s.CodeSE
     AND s.CodeSOC = so.CodeSOC
     AND so.CodeTy = ty.CodeTy                                   -- chaque société possède un type (sujet, INSEE)
     -- catégorie juridique : 3 niveaux (obligatoire, FR et DE)
     AND so.CodeCJ = c3.CodeCJ
     AND c3.CodeCJ_niveau_superieur = c2.CodeCJ
     AND c2.CodeCJ_niveau_superieur = c1.CodeCJ
     -- NAF : facultatif (pas de NAF en Allemagne) ; un super-domaine peut sauter des niveaux (49.39A -> 49)
     AND so.CodeDO = d1.CodeDO(+)
     AND d1.CodeDO_Sup = d2.CodeDO(+)
     AND d2.CodeDO_Sup = d3.CodeDO(+)
     AND d3.CodeDO_Sup = d4.CodeDO(+)
     -- géographie : z1 commune / Gemeinde, z2 département / Kreis, z3 région / district / Land, z4 Land si district
     AND so.CodeZG = z1.CodeZG
     AND z1.CodeZG_zone_englobante = z2.CodeZG
     AND z2.CodeZG_zone_englobante = z3.CodeZG
     AND z3.CodeZG_zone_englobante = z4.CodeZG(+)               -- pas de district : z3 est déjà le Land
     AND z1.CodePays = pa.CodePays;

ALTER TABLE DIM_EMPLOYE_MD2 ADD CONSTRAINT pk_dim_employe_md2 PRIMARY KEY (IdVersionEmploye);

CREATE DIMENSION EMPLOYE_MD2_DIM
   LEVEL N_IdVersionEmploye IS (DIM_EMPLOYE_MD2.IdVersionEmploye)
   LEVEL N_CodeEmploye      IS (DIM_EMPLOYE_MD2.CodeEmploye)
   LEVEL N_CodeCategorie    IS (DIM_EMPLOYE_MD2.CodeCategorie)
   LEVEL N_SuperCategorie   IS (DIM_EMPLOYE_MD2.SuperCategorie)
   LEVEL N_TrancheAge       IS (DIM_EMPLOYE_MD2.TrancheAge)      SKIP WHEN NULL
   LEVEL N_CodeService      IS (DIM_EMPLOYE_MD2.CodeService)
   LEVEL N_CodeSociete      IS (DIM_EMPLOYE_MD2.CodeSociete)
   LEVEL N_CodeTy           IS (DIM_EMPLOYE_MD2.CodeTy)
   LEVEL N_CodeCJ3          IS (DIM_EMPLOYE_MD2.CodeCJ3)
   LEVEL N_CodeCJ2          IS (DIM_EMPLOYE_MD2.CodeCJ2)
   LEVEL N_CodeCJ1          IS (DIM_EMPLOYE_MD2.CodeCJ1)
   LEVEL N_SousClasseNAF    IS (DIM_EMPLOYE_MD2.SousClasseNAF)   SKIP WHEN NULL
   LEVEL N_ClasseNAF        IS (DIM_EMPLOYE_MD2.ClasseNAF)       SKIP WHEN NULL
   LEVEL N_GroupeNAF        IS (DIM_EMPLOYE_MD2.GroupeNAF)       SKIP WHEN NULL
   LEVEL N_DivisionNAF      IS (DIM_EMPLOYE_MD2.DivisionNAF)     SKIP WHEN NULL
   LEVEL N_CodeVille        IS (DIM_EMPLOYE_MD2.CodeVille)       SKIP WHEN NULL
   LEVEL N_CodeDepartement  IS (DIM_EMPLOYE_MD2.CodeDepartement) SKIP WHEN NULL
   LEVEL N_CodeGemeinde     IS (DIM_EMPLOYE_MD2.CodeGemeinde)    SKIP WHEN NULL
   LEVEL N_CodeKreis        IS (DIM_EMPLOYE_MD2.CodeKreis)       SKIP WHEN NULL
   LEVEL N_CodeDistrict     IS (DIM_EMPLOYE_MD2.CodeDistrict)    SKIP WHEN NULL
   LEVEL N_CodeRegion       IS (DIM_EMPLOYE_MD2.CodeRegion)
   LEVEL N_CodePays         IS (DIM_EMPLOYE_MD2.CodePays)
HIERARCHY H_Categorie    (N_IdVersionEmploye CHILD OF N_CodeEmploye CHILD OF N_CodeCategorie CHILD OF N_SuperCategorie)
HIERARCHY H_Age          (N_IdVersionEmploye CHILD OF N_TrancheAge)
HIERARCHY H_Type_Societe (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete CHILD OF N_CodeTy)
HIERARCHY H_CJ           (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete
                          CHILD OF N_CodeCJ3 CHILD OF N_CodeCJ2 CHILD OF N_CodeCJ1)
HIERARCHY H_NAF          (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete CHILD OF N_SousClasseNAF
                          CHILD OF N_ClasseNAF CHILD OF N_GroupeNAF CHILD OF N_DivisionNAF)
HIERARCHY H_France       (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete CHILD OF N_CodeVille
                          CHILD OF N_CodeDepartement CHILD OF N_CodeRegion CHILD OF N_CodePays)
HIERARCHY H_Allemagne    (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete CHILD OF N_CodeGemeinde
                          CHILD OF N_CodeKreis CHILD OF N_CodeRegion CHILD OF N_CodePays)
HIERARCHY H_District     (N_IdVersionEmploye CHILD OF N_CodeService CHILD OF N_CodeSociete CHILD OF N_CodeGemeinde
                          CHILD OF N_CodeKreis CHILD OF N_CodeDistrict CHILD OF N_CodeRegion CHILD OF N_CodePays)
ATTRIBUTE N_IdVersionEmploye DETERMINES DIM_EMPLOYE_MD2.DateDebutVersion
ATTRIBUTE N_IdVersionEmploye DETERMINES DIM_EMPLOYE_MD2.DateFinVersion
ATTRIBUTE N_CodeEmploye      DETERMINES DIM_EMPLOYE_MD2.NomEmploye
ATTRIBUTE N_CodeEmploye      DETERMINES DIM_EMPLOYE_MD2.PrenomEmploye
ATTRIBUTE N_CodeCategorie    DETERMINES DIM_EMPLOYE_MD2.NomCategorie
ATTRIBUTE N_CodeService      DETERMINES DIM_EMPLOYE_MD2.NomService
ATTRIBUTE N_CodeSociete      DETERMINES DIM_EMPLOYE_MD2.NomSociete
ATTRIBUTE N_CodeTy           DETERMINES DIM_EMPLOYE_MD2.LibelleTypeSoc
ATTRIBUTE N_CodeCJ3          DETERMINES DIM_EMPLOYE_MD2.LibelleCJ3
ATTRIBUTE N_CodeCJ2          DETERMINES DIM_EMPLOYE_MD2.LibelleCJ2
ATTRIBUTE N_CodeCJ1          DETERMINES DIM_EMPLOYE_MD2.LibelleCJ1
ATTRIBUTE N_SousClasseNAF    DETERMINES DIM_EMPLOYE_MD2.LibelleNAF
ATTRIBUTE N_CodeVille        DETERMINES DIM_EMPLOYE_MD2.NomVille
ATTRIBUTE N_CodeDepartement  DETERMINES DIM_EMPLOYE_MD2.NomDepartement
ATTRIBUTE N_CodeGemeinde     DETERMINES DIM_EMPLOYE_MD2.NomGemeinde
ATTRIBUTE N_CodeKreis        DETERMINES DIM_EMPLOYE_MD2.NomKreis
ATTRIBUTE N_CodeDistrict     DETERMINES DIM_EMPLOYE_MD2.NomDistrict
ATTRIBUTE N_CodeRegion       DETERMINES DIM_EMPLOYE_MD2.NomRegion
ATTRIBUTE N_CodePays         DETERMINES DIM_EMPLOYE_MD2.NomPays
ATTRIBUTE N_CodePays         DETERMINES DIM_EMPLOYE_MD2.TauxTVA;

-- =====================================================================
-- 5. FAIT Achat_MD (données détaillées) : un produit, une version d'employé, un métier, un jour
--    Montant_Achat_MD              = quantité x prix public HT (tarif valable à la date, dans le pays de la société ;
--                                    tarifs FR en TTC ramenés en HT : RG5, contrainte C4)
--    Montant_Achat_ReelPaye_MD     = montant public HT x (1 - % de réduction achat de la gamme, du profil et de l'année)
--    Montant_Achat_ReelPaye_TTC_MD = montant réellement payé HT x (1 + TVA du pays) : dépense réelle de l'employé
--    Benefice_Achat_MD             = montant public HT - montant réellement payé HT (sujet p. 5 ; HT car la TVA
--                                    est reversée à l'État et ne constitue pas un gain pour MobiPass)
--    Métier                        = métier exercé à la date de l'achat (EXERCER_DW, RG9), « NR » s'il n'y en a pas
-- =====================================================================
CREATE MATERIALIZED VIEW FAIT_ACHAT_MD2
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT CodeProduit, IdVersionEmploye, CodeAppellation, DateJour,
          SUM(Qte)                                                AS Quantite_Achat_MD,
          SUM(Qte * PrixHT)                                       AS Montant_Achat_MD,
          SUM(Qte * PrixHT * (1 - PctReduc))                      AS Montant_Achat_ReelPaye_MD,
          -- [MODIF M1] montant réellement payé TTC (même convention que Location_MD)
          SUM(Qte * PrixHT * (1 - PctReduc) * (1 + TauxTVA))      AS Montant_Achat_ReelPaye_TTC_MD,
          SUM(Qte * PrixHT) - SUM(Qte * PrixHT * (1 - PctReduc))  AS Benefice_Achat_MD
   FROM (SELECT ac.CodeP AS CodeProduit, de.IdVersionEmploye, ac.DateA AS DateJour, ac.Qte,
                CASE WHEN t.ModePrix = 'TTC' THEN t.Prix_vente / (1 + de.TauxTVA) ELSE t.Prix_vente END AS PrixHT,
                de.TauxTVA,
                r.PctReduc_Achat AS PctReduc,
                -- [MODIF M2] une seule valeur même si deux périodes de métier se chevauchent (la plus récente)
                NVL((SELECT MAX(x.CodeAPP) KEEP (DENSE_RANK LAST ORDER BY x.DateDebutMetier)
                     FROM SALARIE_RH_DW sr, EXERCER_DW x
                     WHERE sr.CodeE = ac.CodeE
                       AND x.MatriculeSAL = sr.MatriculeSAL
                       AND x.NumEtab = sr.NumEtab
                       AND ac.DateA BETWEEN x.DateDebutMetier
                                        AND NVL(x.DateFinMetier, TO_DATE('31/12/9999', 'DD/MM/YYYY'))), 'NR') AS CodeAppellation
         FROM ACHAT_DW ac, PRODUIT_DW p, EMPLOYE_DW e, REDUCTION_DW r, TARIFER_DW t, DIM_EMPLOYE_MD2 de
         WHERE ac.CodeP = p.CodeP
           AND ac.CodeE = e.CodeE
           -- version de l'employé valable à la date de l'achat (type 2) : donne aussi le pays de sa société
           AND de.CodeEmploye = ac.CodeE
           AND ac.DateA BETWEEN de.DateDebutVersion AND NVL(de.DateFinVersion, TO_DATE('31/12/9999', 'DD/MM/YYYY'))
           -- tarif du produit, dans le pays de la société, valable à la date
           AND t.CodeP = ac.CodeP
           AND t.CodePays = de.CodePays
           AND ac.DateA BETWEEN t.DateDebutTarif AND NVL(t.DateFinTarif, TO_DATE('31/12/9999', 'DD/MM/YYYY'))
           -- réduction achat de la gamme, pour le profil de l'employé, l'année de l'achat
           AND r.CodeG = p.CodeG
           AND r.CodeCAT = e.CodeCAT
           AND r.Annee = EXTRACT(YEAR FROM ac.DateA))
   GROUP BY CodeProduit, IdVersionEmploye, CodeAppellation, DateJour;

ALTER TABLE FAIT_ACHAT_MD2 ADD CONSTRAINT pk_fait_achat_md2
      PRIMARY KEY (CodeProduit, IdVersionEmploye, CodeAppellation, DateJour);
ALTER TABLE FAIT_ACHAT_MD2 ADD CONSTRAINT fk_ach_md2_produit FOREIGN KEY (CodeProduit)
      REFERENCES DIM_PRODUIT_MD2 (CodeProduit) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE FAIT_ACHAT_MD2 ADD CONSTRAINT fk_ach_md2_employe FOREIGN KEY (IdVersionEmploye)
      REFERENCES DIM_EMPLOYE_MD2 (IdVersionEmploye) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE FAIT_ACHAT_MD2 ADD CONSTRAINT fk_ach_md2_metier FOREIGN KEY (CodeAppellation)
      REFERENCES DIM_METIER_MD2 (CodeAppellation) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE FAIT_ACHAT_MD2 ADD CONSTRAINT fk_ach_md2_temps FOREIGN KEY (DateJour)
      REFERENCES DIM_TEMPS_MD2 (DateJour) DEFERRABLE INITIALLY DEFERRED;

-- =====================================================================
-- 6. DONNÉES AGRÉGÉES : TREILLIS PARTIEL (rapports mensuels et trimestriels des responsables des ventes)
--    Nœuds notés (Produit, Employé, Métier, Temps) ; chaque agrégat garde CodePays pour la sécurité par pays.
--
--                            (All, All, All, All)
--                           /                    \
--        (All, CodePays, All, Mois)  B4.1         \
--                  |                               \
--        (CodeGamme, CodeRegion, All, Mois)  B4.2   (All, CodeTy x CodeCJ2, All, Trimestre)  B4.3
--                           \                    /
--      (CodeProduit, IdVersionEmploye, CodeAppellation, DateJour) = FAIT_ACHAT_MD2
--
--  Les analyses libres B3 (jour, produit, employé, métier, société) portent sur les données détaillées.
-- =====================================================================

-- B4.2 : classement des gammes par montant réellement payé pour chaque région (FR) / Land (DE), par mois
CREATE MATERIALIZED VIEW MV_ACH_GAM_REG_MOIS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
ENABLE QUERY REWRITE
AS SELECT p.CodeGamme, p.NomGamme, p.SecteurProduit,
          de.CodeRegion, de.NomRegion, de.CodePays, de.NomPays,
          t.Mois, t.LibMois, t.Annee,
          SUM(f.Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(f.Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(f.Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,   -- [MODIF M1]
          SUM(f.Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM FAIT_ACHAT_MD2 f, DIM_PRODUIT_MD2 p, DIM_EMPLOYE_MD2 de, DIM_TEMPS_MD2 t
   WHERE f.CodeProduit = p.CodeProduit
     AND f.IdVersionEmploye = de.IdVersionEmploye
     AND f.DateJour = t.DateJour
   GROUP BY p.CodeGamme, p.NomGamme, p.SecteurProduit, de.CodeRegion, de.NomRegion, de.CodePays, de.NomPays,
            t.Mois, t.LibMois, t.Annee;

-- B4.1 : tableau de bord mensuel par pays (quantités, montant payé, bénéfice, comparaison à l'année précédente)
--        source : MV_ACH_GAM_REG_MOIS (nœud plus détaillé du même chemin du treillis)
CREATE MATERIALIZED VIEW MV_ACH_PAYS_MOIS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS SELECT CodePays, NomPays, Mois, LibMois, Annee,
          SUM(Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,   -- [MODIF M1]
          SUM(Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM MV_ACH_GAM_REG_MOIS
   GROUP BY CodePays, NomPays, Mois, LibMois, Annee;

-- B4.3 : ventes par type de société et catégorie juridique (niveau 2), par trimestre
CREATE MATERIALIZED VIEW MV_ACH_TYPE_CJ_TRIM
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
ENABLE QUERY REWRITE
AS SELECT de.CodeTy, de.LibelleTypeSoc, de.CodeCJ2, de.LibelleCJ2, de.CodePays, de.NomPays, t.Trimestre, t.Annee,
          SUM(f.Quantite_Achat_MD)             AS Quantite_Achat_MD,
          SUM(f.Montant_Achat_ReelPaye_MD)     AS Montant_Achat_ReelPaye_MD,
          SUM(f.Montant_Achat_ReelPaye_TTC_MD) AS Montant_Achat_ReelPaye_TTC_MD,   -- [MODIF M1]
          SUM(f.Benefice_Achat_MD)             AS Benefice_Achat_MD
   FROM FAIT_ACHAT_MD2 f, DIM_EMPLOYE_MD2 de, DIM_TEMPS_MD2 t
   WHERE f.IdVersionEmploye = de.IdVersionEmploye
     AND f.DateJour = t.DateJour
   GROUP BY de.CodeTy, de.LibelleTypeSoc, de.CodeCJ2, de.LibelleCJ2, de.CodePays, de.NomPays, t.Trimestre, t.Annee;

-- =====================================================================
-- 7. VÉRIFICATIONS
-- =====================================================================
-- Chaque achat de l'ED doit se retrouver dans le fait (tarif, réduction et version trouvés) : 2730 = 2730
SELECT (SELECT SUM(Qte) FROM ACHAT_DW) AS qte_ED, (SELECT SUM(Quantite_Achat_MD) FROM FAIT_ACHAT_MD2) AS qte_MD2 FROM dual;

SELECT dimension_name, invalid FROM user_dimensions;

-- [MODIF M6] Achats de l'ED absents du fait (pas de version d'employé, de tarif ou de réduction à la date)
SELECT ac.CodeE, ac.CodeP, ac.DateA, ac.Qte
FROM   ACHAT_DW ac
WHERE  NOT EXISTS (SELECT 1
                   FROM   FAIT_ACHAT_MD2 f, DIM_EMPLOYE_MD2 de
                   WHERE  f.IdVersionEmploye = de.IdVersionEmploye
                     AND  de.CodeEmploye = ac.CodeE
                     AND  f.CodeProduit  = ac.CodeP
                     AND  f.DateJour     = ac.DateA);

-- [MODIF M6] Affectations qui se chevauchent (un achat serait compté deux fois : qte_MD2 > qte_ED)
SELECT a1.CodeE, a1.DateDebutAffect, a2.DateDebutAffect
FROM   ETRE_AFFECTE_DW a1, ETRE_AFFECTE_DW a2
WHERE  a1.CodeE = a2.CodeE
  AND  a1.DateDebutAffect < a2.DateDebutAffect
  AND  NVL(a1.DateFinAffect, TO_DATE('31/12/9999', 'DD/MM/YYYY')) >= a2.DateDebutAffect;

-- [MODIF M6] Périodes de métier qui se chevauchent (le métier le plus récent est alors retenu)
SELECT x1.MatriculeSAL, x1.NumEtab, x1.DateDebutMetier, x2.DateDebutMetier
FROM   EXERCER_DW x1, EXERCER_DW x2
WHERE  x1.MatriculeSAL = x2.MatriculeSAL
  AND  x1.NumEtab = x2.NumEtab
  AND  x1.DateDebutMetier < x2.DateDebutMetier
  AND  NVL(x1.DateFinMetier, TO_DATE('31/12/9999', 'DD/MM/YYYY')) >= x2.DateDebutMetier;

-- [MODIF M6] Tarifs qui se chevauchent pour un même produit et un même pays (achat compté deux fois)
SELECT t1.CodeP, t1.CodePays, t1.DateDebutTarif, t2.DateDebutTarif
FROM   TARIFER_DW t1, TARIFER_DW t2
WHERE  t1.CodeP = t2.CodeP
  AND  t1.CodePays = t2.CodePays
  AND  t1.DateDebutTarif < t2.DateDebutTarif
  AND  NVL(t1.DateFinTarif, TO_DATE('31/12/9999', 'DD/MM/YYYY')) >= t2.DateDebutTarif;

-- Exemple de rapport B4.2 : top des gammes par région / Land sur l'année 2026
SELECT NomPays, NomRegion, NomGamme, ROUND(SUM(Montant_Achat_ReelPaye_MD), 2) AS Montant_Achat_ReelPaye_MD
FROM MV_ACH_GAM_REG_MOIS
WHERE Annee = '2026'
GROUP BY NomPays, NomRegion, NomGamme
ORDER BY NomPays, NomRegion, Montant_Achat_ReelPaye_MD DESC;

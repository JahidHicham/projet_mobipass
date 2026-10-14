-- MobiPass - Entrepôt de données : création des tables (Oracle 11g, schéma ABEHS)
-- Traduction du MCD Looping. JOUR et ANNEE sont des entités fictives, comme dans
-- le schéma relationnel du sujet : les dates sont des colonnes DATE.
-- Les contraintes CHECK et les triggers sont dans 02_contraintes_ED.sql.
-- Toutes les tables de l'entrepôt sont suffixées _DW pour les distinguer de celles des magasins.

-- Supprime les tables _DW, puis les anciennes tables sans suffixe des versions précédentes
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('ACHETER_PARTENAIRE_DW','LOUER_DW','RESERVER_DW','ACHAT_DW','TARIFER_DW',
                                 'REDUCTION_DW','EXERCER_DW','SALARIE_RH_DW','EXEMPLAIRE_DW','PRODUIT_DW',
                                 'ETRE_AFFECTE_DW','EMPLOYE_DW','SERVICE_DW','SOCIETE_DW','PARTENAIRE_DW',
                                 'GAMME_DW','AGENCE_DW','GENERATION_DW','FABRICANT_DW','APPELLATION_DW',
                                 'FICHE_METIER_DW','DOMAINE_PRO_DW','GRAND_DOMAINE_DW','CATEGORIE_DW',
                                 'TYPE_SOCIETE_DW','CATEGORIE_JURIDIQUE_DW','DOMAINE_DW','ZONE_GEO_DW','PAYS_DW',
                                 'ACHETER_PARTENAIRE','LOUER','RESERVER','ACHAT','ACHETER','TARIFER',
                                 'REDUCTION','EXERCER','SALARIE_RH','EXEMPLAIRE','PRODUIT',
                                 'ETRE_AFFECTE','EMPLOYE','SERVICE','SOCIETE','PARTENAIRE',
                                 'GAMME','AGENCE','GENERATION','FABRICANT','APPELLATION',
                                 'FICHE_METIER','DOMAINE_PRO','GRAND_DOMAINE','CATEGORIE',
                                 'TYPE_SOCIETE','CATEGORIE_JURIDIQUE','DOMAINE','ZONE_GEO','PAYS',
                                 'TARIF','CATEGORISER','JOUR','ANNEE','ARTICLE_PARTENAIRE'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE PAYS_DW(
   CodePays  CHAR(2),
   NomPays   VARCHAR2(50) NOT NULL,
   TauxTVA   NUMBER(4,3)  NOT NULL,
   CONSTRAINT pk_pays PRIMARY KEY(CodePays)
);

CREATE TABLE ZONE_GEO_DW(
   CodeZG                  VARCHAR2(10),
   NomZG                   VARCHAR2(100) NOT NULL,
   NiveauZG                VARCHAR2(20)  NOT NULL,
   CodeZG_zone_englobante  VARCHAR2(10),
   CodePays                CHAR(2)       NOT NULL,
   CONSTRAINT pk_zone_geo PRIMARY KEY(CodeZG),
   CONSTRAINT fk_zg_englobante FOREIGN KEY(CodeZG_zone_englobante) REFERENCES ZONE_GEO_DW(CodeZG),
   CONSTRAINT fk_zg_pays FOREIGN KEY(CodePays) REFERENCES PAYS_DW(CodePays)
);

CREATE TABLE DOMAINE_DW(
   CodeDO                VARCHAR2(7),
   NomDO                 VARCHAR2(150) NOT NULL,
   CodeDO_Sup            VARCHAR2(7),
   CONSTRAINT pk_domaine PRIMARY KEY(CodeDO),
   CONSTRAINT fk_do_super FOREIGN KEY(CodeDO_Sup) REFERENCES DOMAINE_DW(CodeDO)
);

CREATE TABLE CATEGORIE_JURIDIQUE_DW(
   CodeCJ                   VARCHAR2(4),
   LibelleCJ                VARCHAR2(150) NOT NULL,
   NiveauCJ                 NUMBER(1)     NOT NULL,
   CodeCJ_niveau_superieur  VARCHAR2(4),
   CONSTRAINT pk_categorie_juridique PRIMARY KEY(CodeCJ),
   CONSTRAINT fk_cj_superieur FOREIGN KEY(CodeCJ_niveau_superieur) REFERENCES CATEGORIE_JURIDIQUE_DW(CodeCJ)
);

CREATE TABLE TYPE_SOCIETE_DW(
   CodeTy          VARCHAR2(5),
   LibelleTypeSoc  VARCHAR2(60) NOT NULL,
   CONSTRAINT pk_type_societe PRIMARY KEY(CodeTy)
);

CREATE TABLE CATEGORIE_DW(
   CodeCAT   CHAR(5),
   NomCAT    VARCHAR2(100) NOT NULL,
   SuperCAT  VARCHAR2(100) NOT NULL,
   CONSTRAINT pk_categorie PRIMARY KEY(CodeCAT)
);

CREATE TABLE GRAND_DOMAINE_DW(
   CodeGD     CHAR(1),
   LibelleGD  VARCHAR2(100) NOT NULL,
   CONSTRAINT pk_grand_domaine PRIMARY KEY(CodeGD)
);

CREATE TABLE DOMAINE_PRO_DW(
   CodeDP     CHAR(3),
   LibelleDP  VARCHAR2(150) NOT NULL,
   CodeGD     CHAR(1)       NOT NULL,
   CONSTRAINT pk_domaine_pro PRIMARY KEY(CodeDP),
   CONSTRAINT fk_dp_gd FOREIGN KEY(CodeGD) REFERENCES GRAND_DOMAINE_DW(CodeGD)
);

CREATE TABLE FICHE_METIER_DW(
   CodeROME       CHAR(5),
   LibelleMetier  VARCHAR2(150) NOT NULL,
   CodeDP         CHAR(3)       NOT NULL,
   CONSTRAINT pk_fiche_metier PRIMARY KEY(CodeROME),
   CONSTRAINT fk_fm_dp FOREIGN KEY(CodeDP) REFERENCES DOMAINE_PRO_DW(CodeDP)
);

CREATE TABLE APPELLATION_DW(
   CodeAPP     VARCHAR2(6),
   LibelleAPP  VARCHAR2(200) NOT NULL,
   CodeROME    CHAR(5)       NOT NULL,
   CONSTRAINT pk_appellation PRIMARY KEY(CodeAPP),
   CONSTRAINT fk_app_fm FOREIGN KEY(CodeROME) REFERENCES FICHE_METIER_DW(CodeROME)
);

CREATE TABLE FABRICANT_DW(
   CodeFAB  VARCHAR2(10),
   NomFAB   VARCHAR2(50) NOT NULL,
   PaysFAB  VARCHAR2(50),
   CONSTRAINT pk_fabricant PRIMARY KEY(CodeFAB)
);

CREATE TABLE GENERATION_DW(
   CodeGEN        VARCHAR2(10),
   NomGEN         VARCHAR2(50) NOT NULL,
   DateSortieGEN  DATE         NOT NULL,
   DateArretGEN   DATE,
   CodeFAB        VARCHAR2(10) NOT NULL,
   CONSTRAINT pk_generation PRIMARY KEY(CodeGEN),
   CONSTRAINT fk_gen_fab FOREIGN KEY(CodeFAB) REFERENCES FABRICANT_DW(CodeFAB)
);

CREATE TABLE AGENCE_DW(
   CodeAG    VARCHAR2(10),
   NomAG     VARCHAR2(50) NOT NULL,
   VilleAG   VARCHAR2(50) NOT NULL,
   CodePays  CHAR(2)      NOT NULL,
   CONSTRAINT pk_agence PRIMARY KEY(CodeAG),
   CONSTRAINT fk_ag_pays FOREIGN KEY(CodePays) REFERENCES PAYS_DW(CodePays)
);

CREATE TABLE GAMME_DW(
   CodeG     CHAR(5),
   NomG      VARCHAR2(50) NOT NULL,
   SecteurG  VARCHAR2(50) NOT NULL,
   CONSTRAINT pk_gamme PRIMARY KEY(CodeG)
);

CREATE TABLE PARTENAIRE_DW(
   CodePartenaire  VARCHAR2(10),
   NomPartenaire   VARCHAR2(50) NOT NULL,
   TauxRemise      NUMBER(4,3)  NOT NULL,
   CONSTRAINT pk_partenaire PRIMARY KEY(CodePartenaire)
);

CREATE TABLE SOCIETE_DW(
   CodeSOC  VARCHAR2(14),               -- SIREN (FR) ou USt-IdNr (DE)
   NomSOC   VARCHAR2(100) NOT NULL,
   CodeTy   VARCHAR2(5),
   CodeZG   VARCHAR2(10)  NOT NULL,
   CodeCJ   VARCHAR2(4)   NOT NULL,   -- Classer 1,1 : INSEE (FR) ou branche D (formes allemandes)
   CodeDO   VARCHAR2(7),               -- Caractériser 0,1 : pas de code NAF pour les sociétés allemandes
   CONSTRAINT pk_societe PRIMARY KEY(CodeSOC),
   CONSTRAINT fk_soc_type FOREIGN KEY(CodeTy) REFERENCES TYPE_SOCIETE_DW(CodeTy),
   CONSTRAINT fk_soc_zg FOREIGN KEY(CodeZG) REFERENCES ZONE_GEO_DW(CodeZG),
   CONSTRAINT fk_soc_cj FOREIGN KEY(CodeCJ) REFERENCES CATEGORIE_JURIDIQUE_DW(CodeCJ),
   CONSTRAINT fk_soc_domaine FOREIGN KEY(CodeDO) REFERENCES DOMAINE_DW(CodeDO)
);

CREATE TABLE SERVICE_DW(
   CodeSE   NUMBER(10),
   NomSE    VARCHAR2(50) NOT NULL,
   CodeSOC  VARCHAR2(14) NOT NULL,
   CONSTRAINT pk_service PRIMARY KEY(CodeSE),
   CONSTRAINT fk_se_societe FOREIGN KEY(CodeSOC) REFERENCES SOCIETE_DW(CodeSOC)
);

CREATE TABLE EMPLOYE_DW(
   CodeE    NUMBER(10),
   NomE     VARCHAR2(50) NOT NULL,
   PrenomE  VARCHAR2(50) NOT NULL,
   CodeSE   NUMBER(10)   NOT NULL,
   CodeCAT  CHAR(5)      NOT NULL,
   CONSTRAINT pk_employe PRIMARY KEY(CodeE),
   CONSTRAINT fk_emp_service FOREIGN KEY(CodeSE) REFERENCES SERVICE_DW(CodeSE),
   CONSTRAINT fk_emp_categorie FOREIGN KEY(CodeCAT) REFERENCES CATEGORIE_DW(CodeCAT)
);

CREATE TABLE ETRE_AFFECTE_DW(
   CodeE            NUMBER(10),
   DateDebutAffect  DATE,
   DateFinAffect    DATE,
   CodeSE           NUMBER(10) NOT NULL,
   CONSTRAINT pk_etre_affecte PRIMARY KEY(CodeE, DateDebutAffect),
   CONSTRAINT fk_aff_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE),
   CONSTRAINT fk_aff_service FOREIGN KEY(CodeSE) REFERENCES SERVICE_DW(CodeSE)
);

CREATE TABLE PRODUIT_DW(
   CodeP        NUMBER(10),
   NomP         VARCHAR2(50)  NOT NULL,
   MarqueP      VARCHAR2(50),
   DescriptifP  VARCHAR2(500),
   PoidsKg      NUMBER(6,2),
   AutonomieKm  NUMBER(5),
   CodeGEN      VARCHAR2(10)  NOT NULL,
   CodeG        CHAR(5)       NOT NULL,
   CONSTRAINT pk_produit PRIMARY KEY(CodeP),
   CONSTRAINT fk_pro_gen FOREIGN KEY(CodeGEN) REFERENCES GENERATION_DW(CodeGEN),
   CONSTRAINT fk_pro_gamme FOREIGN KEY(CodeG) REFERENCES GAMME_DW(CodeG)
);

CREATE TABLE EXEMPLAIRE_DW(
   CodeEX             NUMBER(10),
   NumSerieEX         VARCHAR2(30) NOT NULL,
   DateMiseServiceEX  DATE         NOT NULL,
   DateReformeEX      DATE,
   CodeAG             VARCHAR2(10) NOT NULL,
   CodeP              NUMBER(10)   NOT NULL,
   CONSTRAINT pk_exemplaire PRIMARY KEY(CodeEX),
   CONSTRAINT fk_ex_agence FOREIGN KEY(CodeAG) REFERENCES AGENCE_DW(CodeAG),
   CONSTRAINT fk_ex_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT_DW(CodeP)
);

CREATE TABLE SALARIE_RH_DW(
   MatriculeSAL       VARCHAR2(20),
   NumEtab            VARCHAR2(14),
   DateNaissSAL       DATE,
   DateEntreeSAL      DATE,
   CPResidenceSAL     VARCHAR2(5),
   LibelleServiceSAL  VARCHAR2(100),
   CodeE              NUMBER(10) NOT NULL,
   CONSTRAINT pk_salarie_rh PRIMARY KEY(MatriculeSAL, NumEtab),
   CONSTRAINT uq_sal_employe UNIQUE(CodeE),
   CONSTRAINT fk_sal_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE)
);

CREATE TABLE EXERCER_DW(
   MatriculeSAL     VARCHAR2(20),
   NumEtab          VARCHAR2(14),
   DateDebutMetier  DATE,
   DateFinMetier    DATE,
   TypeContrat      VARCHAR2(20) NOT NULL,
   CodeAPP          VARCHAR2(6)  NOT NULL,
   CONSTRAINT pk_exercer PRIMARY KEY(MatriculeSAL, NumEtab, DateDebutMetier),
   CONSTRAINT fk_exr_salarie FOREIGN KEY(MatriculeSAL, NumEtab) REFERENCES SALARIE_RH_DW(MatriculeSAL, NumEtab),
   CONSTRAINT fk_exr_appellation FOREIGN KEY(CodeAPP) REFERENCES APPELLATION_DW(CodeAPP)
);

CREATE TABLE REDUCTION_DW(
   CodeCAT         CHAR(5),
   CodeG           CHAR(5),
   Annee           NUMBER(4),
   PctReduc_Loc    NUMBER(4,3) NOT NULL,
   PctReduc_Achat  NUMBER(4,3) NOT NULL,
   CONSTRAINT pk_reduction PRIMARY KEY(CodeCAT, CodeG, Annee),
   CONSTRAINT fk_red_categorie FOREIGN KEY(CodeCAT) REFERENCES CATEGORIE_DW(CodeCAT),
   CONSTRAINT fk_red_gamme FOREIGN KEY(CodeG) REFERENCES GAMME_DW(CodeG)
);

CREATE TABLE TARIFER_DW(
   CodePays        CHAR(2),
   CodeP           NUMBER(10),
   DateDebutTarif  DATE,
   DateFinTarif    DATE,
   Prix_loc_jour   NUMBER(10,2),
   Prix_vente      NUMBER(10,2) NOT NULL,
   ModePrix        VARCHAR2(3)  NOT NULL,
   CONSTRAINT pk_tarifer PRIMARY KEY(CodePays, CodeP, DateDebutTarif),
   CONSTRAINT fk_tar_pays FOREIGN KEY(CodePays) REFERENCES PAYS_DW(CodePays),
   CONSTRAINT fk_tar_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT_DW(CodeP)
);

-- Noms de la V1 conservés (ACHAT, DOMAINE.CodeDO_Sup), avec le suffixe _DW commun à l'entrepôt
CREATE TABLE ACHAT_DW(
   CodeE  NUMBER(10),
   CodeP  NUMBER(10),
   DateA  DATE,
   Qte    NUMBER(5) NOT NULL,
   CONSTRAINT pk_achat PRIMARY KEY(CodeE, CodeP, DateA),
   CONSTRAINT fk_ach_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE),
   CONSTRAINT fk_ach_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT_DW(CodeP)
);

CREATE TABLE RESERVER_DW(
   CodeE       NUMBER(10),
   CodeP       NUMBER(10),
   DateLPrev   DATE,
   Nb_Ex_Prev  NUMBER(3) NOT NULL,
   DateResa    DATE      NOT NULL,
   Duree_Prev  NUMBER(4) NOT NULL,
   CONSTRAINT pk_reserver PRIMARY KEY(CodeE, CodeP, DateLPrev),
   CONSTRAINT fk_res_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE),
   CONSTRAINT fk_res_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT_DW(CodeP)
);

CREATE TABLE LOUER_DW(
   CodeE      NUMBER(10),
   CodeEX     NUMBER(10),
   DateL      DATE,
   Duree_Loc  NUMBER(4) NOT NULL,
   CONSTRAINT pk_louer PRIMARY KEY(CodeE, CodeEX, DateL),
   CONSTRAINT fk_lou_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE),
   CONSTRAINT fk_lou_exemplaire FOREIGN KEY(CodeEX) REFERENCES EXEMPLAIRE_DW(CodeEX)
);

-- Offre partenaire (Alltricks) : aucune information sur les articles ni sur les montants ;
-- on enregistre seulement qu'un employé a acheté chez un partenaire un jour donné (fait sans mesure)
CREATE TABLE ACHETER_PARTENAIRE_DW(
   CodeE           NUMBER(10),
   DateA           DATE,
   CodePartenaire  VARCHAR2(10),
   CONSTRAINT pk_acheter_partenaire PRIMARY KEY(CodeE, DateA, CodePartenaire),
   CONSTRAINT fk_achp_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE_DW(CodeE),
   CONSTRAINT fk_achp_partenaire FOREIGN KEY(CodePartenaire) REFERENCES PARTENAIRE_DW(CodePartenaire)
);
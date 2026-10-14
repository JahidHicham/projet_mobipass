-- MobiPass - Entrepôt de données : création des tables (Oracle 11g, schéma ABEHS)
-- Traduction du MCD Looping. JOUR et ANNEE sont des entités fictives, comme dans
-- le schéma relationnel du sujet : les dates sont des colonnes DATE.
-- Les contraintes CHECK et les triggers sont dans 02_contraintes_ED.sql.

BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('ACHETER_PARTENAIRE','LOUER','RESERVER','ACHETER','TARIFER',
                                 'REDUCTION','EXERCER','SALARIE_RH','EXEMPLAIRE','PRODUIT',
                                 'ETRE_AFFECTE','EMPLOYE','SERVICE','SOCIETE','PARTENAIRE',
                                 'GAMME','AGENCE','GENERATION','FABRICANT','APPELLATION',
                                 'FICHE_METIER','DOMAINE_PRO','GRAND_DOMAINE','CATEGORIE',
                                 'TYPE_SOCIETE','CATEGORIE_JURIDIQUE','DOMAINE','ZONE_GEO','PAYS',
                                 'ACHAT','TARIF','CATEGORISER','JOUR','ANNEE','ARTICLE_PARTENAIRE'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE PAYS(
   CodePays  CHAR(2),
   NomPays   VARCHAR2(50) NOT NULL,
   TauxTVA   NUMBER(4,3)  NOT NULL,
   CONSTRAINT pk_pays PRIMARY KEY(CodePays)
);

CREATE TABLE ZONE_GEO(
   CodeZG                  VARCHAR2(10),
   NomZG                   VARCHAR2(100) NOT NULL,
   NiveauZG                VARCHAR2(20)  NOT NULL,
   CodeZG_zone_englobante  VARCHAR2(10),
   CodePays                CHAR(2)       NOT NULL,
   CONSTRAINT pk_zone_geo PRIMARY KEY(CodeZG),
   CONSTRAINT fk_zg_englobante FOREIGN KEY(CodeZG_zone_englobante) REFERENCES ZONE_GEO(CodeZG),
   CONSTRAINT fk_zg_pays FOREIGN KEY(CodePays) REFERENCES PAYS(CodePays)
);

CREATE TABLE DOMAINE(
   CodeDO                VARCHAR2(7),
   NomDO                 VARCHAR2(100) NOT NULL,
   CodeDO_super_domaine  VARCHAR2(7),
   CONSTRAINT pk_domaine PRIMARY KEY(CodeDO),
   CONSTRAINT fk_do_super FOREIGN KEY(CodeDO_super_domaine) REFERENCES DOMAINE(CodeDO)
);

CREATE TABLE CATEGORIE_JURIDIQUE(
   CodeCJ                   VARCHAR2(4),
   LibelleCJ                VARCHAR2(150) NOT NULL,
   NiveauCJ                 NUMBER(1)     NOT NULL,
   CodeCJ_niveau_superieur  VARCHAR2(4),
   CONSTRAINT pk_categorie_juridique PRIMARY KEY(CodeCJ),
   CONSTRAINT fk_cj_superieur FOREIGN KEY(CodeCJ_niveau_superieur) REFERENCES CATEGORIE_JURIDIQUE(CodeCJ)
);

CREATE TABLE TYPE_SOCIETE(
   CodeTy          VARCHAR2(5),
   LibelleTypeSoc  VARCHAR2(60) NOT NULL,
   CONSTRAINT pk_type_societe PRIMARY KEY(CodeTy)
);

CREATE TABLE CATEGORIE(
   CodeCAT   CHAR(5),
   NomCAT    VARCHAR2(100) NOT NULL,
   SuperCAT  VARCHAR2(100) NOT NULL,
   CONSTRAINT pk_categorie PRIMARY KEY(CodeCAT)
);

CREATE TABLE GRAND_DOMAINE(
   CodeGD     CHAR(1),
   LibelleGD  VARCHAR2(100) NOT NULL,
   CONSTRAINT pk_grand_domaine PRIMARY KEY(CodeGD)
);

CREATE TABLE DOMAINE_PRO(
   CodeDP     CHAR(3),
   LibelleDP  VARCHAR2(150) NOT NULL,
   CodeGD     CHAR(1)       NOT NULL,
   CONSTRAINT pk_domaine_pro PRIMARY KEY(CodeDP),
   CONSTRAINT fk_dp_gd FOREIGN KEY(CodeGD) REFERENCES GRAND_DOMAINE(CodeGD)
);

CREATE TABLE FICHE_METIER(
   CodeROME       CHAR(5),
   LibelleMetier  VARCHAR2(150) NOT NULL,
   CodeDP         CHAR(3)       NOT NULL,
   CONSTRAINT pk_fiche_metier PRIMARY KEY(CodeROME),
   CONSTRAINT fk_fm_dp FOREIGN KEY(CodeDP) REFERENCES DOMAINE_PRO(CodeDP)
);

CREATE TABLE APPELLATION(
   CodeAPP     VARCHAR2(6),
   LibelleAPP  VARCHAR2(200) NOT NULL,
   CodeROME    CHAR(5)       NOT NULL,
   CONSTRAINT pk_appellation PRIMARY KEY(CodeAPP),
   CONSTRAINT fk_app_fm FOREIGN KEY(CodeROME) REFERENCES FICHE_METIER(CodeROME)
);

CREATE TABLE FABRICANT(
   CodeFAB  VARCHAR2(10),
   NomFAB   VARCHAR2(50) NOT NULL,
   PaysFAB  VARCHAR2(50),
   CONSTRAINT pk_fabricant PRIMARY KEY(CodeFAB)
);

CREATE TABLE GENERATION(
   CodeGEN        VARCHAR2(10),
   NomGEN         VARCHAR2(50) NOT NULL,
   DateSortieGEN  DATE         NOT NULL,
   DateArretGEN   DATE,
   CodeFAB        VARCHAR2(10) NOT NULL,
   CONSTRAINT pk_generation PRIMARY KEY(CodeGEN),
   CONSTRAINT fk_gen_fab FOREIGN KEY(CodeFAB) REFERENCES FABRICANT(CodeFAB)
);

CREATE TABLE AGENCE(
   CodeAG    VARCHAR2(10),
   NomAG     VARCHAR2(50) NOT NULL,
   VilleAG   VARCHAR2(50) NOT NULL,
   CodePays  CHAR(2)      NOT NULL,
   CONSTRAINT pk_agence PRIMARY KEY(CodeAG),
   CONSTRAINT fk_ag_pays FOREIGN KEY(CodePays) REFERENCES PAYS(CodePays)
);

CREATE TABLE GAMME(
   CodeG     CHAR(5),
   NomG      VARCHAR2(50) NOT NULL,
   SecteurG  VARCHAR2(50) NOT NULL,
   CONSTRAINT pk_gamme PRIMARY KEY(CodeG)
);

CREATE TABLE PARTENAIRE(
   CodePartenaire  VARCHAR2(10),
   NomPartenaire   VARCHAR2(50) NOT NULL,
   TauxRemise      NUMBER(4,3)  NOT NULL,
   CONSTRAINT pk_partenaire PRIMARY KEY(CodePartenaire)
);

CREATE TABLE SOCIETE(
   CodeSOC  VARCHAR2(14),
   NomSOC   VARCHAR2(100) NOT NULL,
   CodeTy   VARCHAR2(5),
   CodeZG   VARCHAR2(10)  NOT NULL,
   CodeCJ   VARCHAR2(4),
   CodeDO   VARCHAR2(7),
   CONSTRAINT pk_societe PRIMARY KEY(CodeSOC),
   CONSTRAINT fk_soc_type FOREIGN KEY(CodeTy) REFERENCES TYPE_SOCIETE(CodeTy),
   CONSTRAINT fk_soc_zg FOREIGN KEY(CodeZG) REFERENCES ZONE_GEO(CodeZG),
   CONSTRAINT fk_soc_cj FOREIGN KEY(CodeCJ) REFERENCES CATEGORIE_JURIDIQUE(CodeCJ),
   CONSTRAINT fk_soc_domaine FOREIGN KEY(CodeDO) REFERENCES DOMAINE(CodeDO)
);

CREATE TABLE SERVICE(
   CodeSE   NUMBER(10),
   NomSE    VARCHAR2(50) NOT NULL,
   CodeSOC  VARCHAR2(14) NOT NULL,
   CONSTRAINT pk_service PRIMARY KEY(CodeSE),
   CONSTRAINT fk_se_societe FOREIGN KEY(CodeSOC) REFERENCES SOCIETE(CodeSOC)
);

CREATE TABLE EMPLOYE(
   CodeE    NUMBER(10),
   NomE     VARCHAR2(50) NOT NULL,
   PrenomE  VARCHAR2(50) NOT NULL,
   CodeSE   NUMBER(10)   NOT NULL,
   CodeCAT  CHAR(5)      NOT NULL,
   CONSTRAINT pk_employe PRIMARY KEY(CodeE),
   CONSTRAINT fk_emp_service FOREIGN KEY(CodeSE) REFERENCES SERVICE(CodeSE),
   CONSTRAINT fk_emp_categorie FOREIGN KEY(CodeCAT) REFERENCES CATEGORIE(CodeCAT)
);

CREATE TABLE ETRE_AFFECTE(
   CodeE            NUMBER(10),
   DateDebutAffect  DATE,
   DateFinAffect    DATE,
   CodeSE           NUMBER(10) NOT NULL,
   CONSTRAINT pk_etre_affecte PRIMARY KEY(CodeE, DateDebutAffect),
   CONSTRAINT fk_aff_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE),
   CONSTRAINT fk_aff_service FOREIGN KEY(CodeSE) REFERENCES SERVICE(CodeSE)
);

CREATE TABLE PRODUIT(
   CodeP        NUMBER(10),
   NomP         VARCHAR2(50)  NOT NULL,
   MarqueP      VARCHAR2(50),
   DescriptifP  VARCHAR2(500),
   PoidsKg      NUMBER(6,2),
   AutonomieKm  NUMBER(5),
   CodeGEN      VARCHAR2(10)  NOT NULL,
   CodeG        CHAR(5)       NOT NULL,
   CONSTRAINT pk_produit PRIMARY KEY(CodeP),
   CONSTRAINT fk_pro_gen FOREIGN KEY(CodeGEN) REFERENCES GENERATION(CodeGEN),
   CONSTRAINT fk_pro_gamme FOREIGN KEY(CodeG) REFERENCES GAMME(CodeG)
);

CREATE TABLE EXEMPLAIRE(
   CodeEX             NUMBER(10),
   NumSerieEX         VARCHAR2(30) NOT NULL,
   DateMiseServiceEX  DATE         NOT NULL,
   DateReformeEX      DATE,
   CodeAG             VARCHAR2(10) NOT NULL,
   CodeP              NUMBER(10)   NOT NULL,
   CONSTRAINT pk_exemplaire PRIMARY KEY(CodeEX),
   CONSTRAINT fk_ex_agence FOREIGN KEY(CodeAG) REFERENCES AGENCE(CodeAG),
   CONSTRAINT fk_ex_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT(CodeP)
);

CREATE TABLE SALARIE_RH(
   MatriculeSAL       VARCHAR2(20),
   NumEtab            VARCHAR2(14),
   DateNaissSAL       DATE,
   DateEntreeSAL      DATE,
   CPResidenceSAL     VARCHAR2(5),
   LibelleServiceSAL  VARCHAR2(50),
   CodeE              NUMBER(10) NOT NULL,
   CONSTRAINT pk_salarie_rh PRIMARY KEY(MatriculeSAL, NumEtab),
   CONSTRAINT uq_sal_employe UNIQUE(CodeE),
   CONSTRAINT fk_sal_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE)
);

CREATE TABLE EXERCER(
   MatriculeSAL     VARCHAR2(20),
   NumEtab          VARCHAR2(14),
   DateDebutMetier  DATE,
   DateFinMetier    DATE,
   TypeContrat      VARCHAR2(20) NOT NULL,
   CodeAPP          VARCHAR2(6)  NOT NULL,
   CONSTRAINT pk_exercer PRIMARY KEY(MatriculeSAL, NumEtab, DateDebutMetier),
   CONSTRAINT fk_exr_salarie FOREIGN KEY(MatriculeSAL, NumEtab) REFERENCES SALARIE_RH(MatriculeSAL, NumEtab),
   CONSTRAINT fk_exr_appellation FOREIGN KEY(CodeAPP) REFERENCES APPELLATION(CodeAPP)
);

CREATE TABLE REDUCTION(
   CodeCAT         CHAR(5),
   CodeG           CHAR(5),
   Annee           NUMBER(4),
   PctReduc_Loc    NUMBER(4,3) NOT NULL,
   PctReduc_Achat  NUMBER(4,3) NOT NULL,
   CONSTRAINT pk_reduction PRIMARY KEY(CodeCAT, CodeG, Annee),
   CONSTRAINT fk_red_categorie FOREIGN KEY(CodeCAT) REFERENCES CATEGORIE(CodeCAT),
   CONSTRAINT fk_red_gamme FOREIGN KEY(CodeG) REFERENCES GAMME(CodeG)
);

CREATE TABLE TARIFER(
   CodePays        CHAR(2),
   CodeP           NUMBER(10),
   DateDebutTarif  DATE,
   DateFinTarif    DATE,
   Prix_loc_jour   NUMBER(10,2),
   Prix_vente      NUMBER(10,2) NOT NULL,
   ModePrix        VARCHAR2(3)  NOT NULL,
   CONSTRAINT pk_tarifer PRIMARY KEY(CodePays, CodeP, DateDebutTarif),
   CONSTRAINT fk_tar_pays FOREIGN KEY(CodePays) REFERENCES PAYS(CodePays),
   CONSTRAINT fk_tar_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT(CodeP)
);

CREATE TABLE ACHETER(
   CodeE  NUMBER(10),
   CodeP  NUMBER(10),
   DateA  DATE,
   Qte    NUMBER(5) NOT NULL,
   CONSTRAINT pk_acheter PRIMARY KEY(CodeE, CodeP, DateA),
   CONSTRAINT fk_ach_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE),
   CONSTRAINT fk_ach_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT(CodeP)
);

CREATE TABLE RESERVER(
   CodeE       NUMBER(10),
   CodeP       NUMBER(10),
   DateLPrev   DATE,
   Nb_Ex_Prev  NUMBER(3) NOT NULL,
   DateResa    DATE      NOT NULL,
   Duree_Prev  NUMBER(4) NOT NULL,
   CONSTRAINT pk_reserver PRIMARY KEY(CodeE, CodeP, DateLPrev),
   CONSTRAINT fk_res_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE),
   CONSTRAINT fk_res_produit FOREIGN KEY(CodeP) REFERENCES PRODUIT(CodeP)
);

CREATE TABLE LOUER(
   CodeE      NUMBER(10),
   CodeEX     NUMBER(10),
   DateL      DATE,
   Duree_Loc  NUMBER(4) NOT NULL,
   CONSTRAINT pk_louer PRIMARY KEY(CodeE, CodeEX, DateL),
   CONSTRAINT fk_lou_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE),
   CONSTRAINT fk_lou_exemplaire FOREIGN KEY(CodeEX) REFERENCES EXEMPLAIRE(CodeEX)
);

CREATE TABLE ACHETER_PARTENAIRE(
   CodeE           NUMBER(10),
   DateA           DATE,
   CodePartenaire  VARCHAR2(10),
   CONSTRAINT pk_acheter_partenaire PRIMARY KEY(CodeE, DateA, CodePartenaire),
   CONSTRAINT fk_achp_employe FOREIGN KEY(CodeE) REFERENCES EMPLOYE(CodeE),
   CONSTRAINT fk_achp_partenaire FOREIGN KEY(CodePartenaire) REFERENCES PARTENAIRE(CodePartenaire)
);

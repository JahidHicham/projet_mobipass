BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('LOUER','RESERVER','ACHAT','REDUCTION','EXEMPLAIRE',
                                 'AGENCE','TARIF','PRODUIT','GAMME','GENERATION',
                                 'FABRICANT','EXERCER','APPELLATION','FICHE_METIER',
                                 'DOMAINE_PRO','GRAND_DOMAINE','CATEGORISER','SALARIE_RH',
                                 'EMPLOYE','CATEGORIE','SERVICE','SOCIETE','TYPE_SOCIETE',
                                 'CATEGORIE_JURIDIQUE','DOMAINE','ZONE_GEO','PAYS'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE PAYS (
  CodePays  CHAR(2)       CONSTRAINT pk_pays PRIMARY KEY,
  NomPays   VARCHAR2(50)  NOT NULL,
  TauxTVA   NUMBER(4,3)   NOT NULL,
  CONSTRAINT ck_pays_code CHECK (CodePays IN ('FR','DE')),
  CONSTRAINT ck_pays_tva  CHECK (TauxTVA > 0 AND TauxTVA < 1)
);

CREATE TABLE ZONE_GEO (
  CodeZG      VARCHAR2(10)  CONSTRAINT pk_zone_geo PRIMARY KEY,
  NomZG       VARCHAR2(100) NOT NULL,
  NiveauZG    VARCHAR2(20)  NOT NULL,
  CodePays    CHAR(2)       NOT NULL CONSTRAINT fk_zg_pays REFERENCES PAYS(CodePays),
  CodeZG_Sup  VARCHAR2(10)  CONSTRAINT fk_zg_sup REFERENCES ZONE_GEO(CodeZG),
  CONSTRAINT ck_zg_niveau CHECK (NiveauZG IN ('COMMUNE','DEPARTEMENT','REGION',
                                              'GEMEINDE','BEZIRK','KREIS','DISTRICT','LAND')),

  CONSTRAINT ck_zg_sup CHECK ( (NiveauZG IN ('REGION','LAND') AND CodeZG_Sup IS NULL)
                            OR (NiveauZG NOT IN ('REGION','LAND') AND CodeZG_Sup IS NOT NULL) )
);

CREATE TABLE DOMAINE (
  CodeDO      VARCHAR2(7)   CONSTRAINT pk_domaine PRIMARY KEY,
  NomDO       VARCHAR2(100) NOT NULL,
  CodeDO_Sup  VARCHAR2(7)   CONSTRAINT fk_do_sup REFERENCES DOMAINE(CodeDO),
  CONSTRAINT ck_do_masque CHECK (REGEXP_LIKE(CodeDO, '^[0-9]{2,3}-[0-9]{3}$'))
);

CREATE TABLE CATEGORIE_JURIDIQUE (
  CodeCJ      VARCHAR2(4)   CONSTRAINT pk_cat_jur PRIMARY KEY,
  LibelleCJ   VARCHAR2(150) NOT NULL,
  NiveauCJ    NUMBER(1)     NOT NULL,
  CodeCJ_Sup  VARCHAR2(4)   CONSTRAINT fk_cj_sup REFERENCES CATEGORIE_JURIDIQUE(CodeCJ),
  CONSTRAINT ck_cj_niveau CHECK (NiveauCJ IN (1,2,3)),
  CONSTRAINT ck_cj_sup    CHECK ( (NiveauCJ = 1 AND CodeCJ_Sup IS NULL)
                               OR (NiveauCJ > 1 AND CodeCJ_Sup IS NOT NULL) )
);

CREATE TABLE TYPE_SOCIETE (
  CodeTy          VARCHAR2(5)   CONSTRAINT pk_type_societe PRIMARY KEY,
  LibelleTypeSoc  VARCHAR2(60)  NOT NULL,
  CONSTRAINT ck_ty_code CHECK (CodeTy IN ('MICRO','PME','ETI','GE'))
);

CREATE TABLE SOCIETE (
  CodeSOC  VARCHAR2(14)  CONSTRAINT pk_societe PRIMARY KEY,
  NomSOC   VARCHAR2(100) NOT NULL,
  CodeTy   VARCHAR2(5)   CONSTRAINT fk_soc_type REFERENCES TYPE_SOCIETE(CodeTy),
  CodeDO   VARCHAR2(7)   CONSTRAINT fk_soc_domaine REFERENCES DOMAINE(CodeDO),
  CodeCJ   VARCHAR2(4)   CONSTRAINT fk_soc_cj REFERENCES CATEGORIE_JURIDIQUE(CodeCJ),
  CodeZG   VARCHAR2(10)  NOT NULL CONSTRAINT fk_soc_zg REFERENCES ZONE_GEO(CodeZG)
);

CREATE TABLE SERVICE (
  CodeSE   NUMBER(10)    CONSTRAINT pk_service PRIMARY KEY,
  NomSE    VARCHAR2(50)  NOT NULL,
  CodeSOC  VARCHAR2(14)  NOT NULL CONSTRAINT fk_se_societe REFERENCES SOCIETE(CodeSOC),
  CONSTRAINT ck_se_code CHECK (CodeSE > 0)
);

CREATE TABLE CATEGORIE (
  CodeCAT   CHAR(5)       CONSTRAINT pk_categorie PRIMARY KEY,
  NomCAT    VARCHAR2(100) NOT NULL,
  SuperCAT  VARCHAR2(100) NOT NULL,
  CONSTRAINT ck_cat_masque CHECK (REGEXP_LIKE(CodeCAT, '^[A-Z]{2}-[0-9]{2}$'))
);

CREATE TABLE EMPLOYE (
  CodeE    NUMBER(10)    CONSTRAINT pk_employe PRIMARY KEY,
  NomE     VARCHAR2(50)  NOT NULL,
  PrenomE  VARCHAR2(50)  NOT NULL,
  CodeSE   NUMBER(10)    NOT NULL CONSTRAINT fk_emp_service REFERENCES SERVICE(CodeSE),
  CONSTRAINT ck_emp_code CHECK (CodeE > 0)
);

CREATE TABLE SALARIE_RH (
  CodeE           NUMBER(10),
  MatriculeSAL    VARCHAR2(20)  NOT NULL,
  SIRET           CHAR(14)      NOT NULL,
  DateNaissSAL    DATE,
  DateEntreeSAL   DATE,
  CPResidenceSAL  VARCHAR2(10),
  CONSTRAINT pk_salarie_rh  PRIMARY KEY (CodeE),
  CONSTRAINT fk_sal_employe FOREIGN KEY (CodeE) REFERENCES EMPLOYE(CodeE),
  CONSTRAINT uq_sal_rh      UNIQUE (MatriculeSAL, SIRET),
  CONSTRAINT ck_sal_siret   CHECK (REGEXP_LIKE(SIRET, '^[0-9]{14}$')),
  CONSTRAINT ck_sal_dates   CHECK (DateEntreeSAL IS NULL OR DateNaissSAL IS NULL
                                   OR DateEntreeSAL > DateNaissSAL)
);

CREATE TABLE CATEGORISER (
  CodeE    NUMBER(10)  CONSTRAINT fk_ctg_employe REFERENCES EMPLOYE(CodeE),
  Annee    NUMBER(4),
  CodeCAT  CHAR(5)     NOT NULL CONSTRAINT fk_ctg_categorie REFERENCES CATEGORIE(CodeCAT),
  CONSTRAINT pk_categoriser PRIMARY KEY (CodeE, Annee),
  CONSTRAINT ck_ctg_annee   CHECK (Annee BETWEEN 2000 AND 2100)
);

CREATE TABLE GRAND_DOMAINE (
  CodeGD     CHAR(1)       CONSTRAINT pk_grand_domaine PRIMARY KEY,
  LibelleGD  VARCHAR2(100) NOT NULL
);

CREATE TABLE DOMAINE_PRO (
  CodeDP     CHAR(3)       CONSTRAINT pk_domaine_pro PRIMARY KEY,
  LibelleDP  VARCHAR2(150) NOT NULL,
  CodeGD     CHAR(1)       NOT NULL CONSTRAINT fk_dp_gd REFERENCES GRAND_DOMAINE(CodeGD)
);

CREATE TABLE FICHE_METIER (
  CodeROME       CHAR(5)       CONSTRAINT pk_fiche_metier PRIMARY KEY,
  LibelleMetier  VARCHAR2(150) NOT NULL,
  CodeDP         CHAR(3)       NOT NULL CONSTRAINT fk_fm_dp REFERENCES DOMAINE_PRO(CodeDP)
);

CREATE TABLE APPELLATION (
  CodeAPP     VARCHAR2(6)   CONSTRAINT pk_appellation PRIMARY KEY,
  LibelleAPP  VARCHAR2(200) NOT NULL,
  CodeROME    CHAR(5)       NOT NULL CONSTRAINT fk_app_fm REFERENCES FICHE_METIER(CodeROME)
);

CREATE TABLE EXERCER (
  CodeE            NUMBER(10)   CONSTRAINT fk_exr_sal REFERENCES SALARIE_RH(CodeE),
  DateDebutMetier  DATE,
  CodeAPP          VARCHAR2(6)  NOT NULL CONSTRAINT fk_exr_app REFERENCES APPELLATION(CodeAPP),
  DateFinMetier    DATE,
  TypeContrat      VARCHAR2(20) NOT NULL,
  CONSTRAINT pk_exercer      PRIMARY KEY (CodeE, DateDebutMetier),
  CONSTRAINT ck_exr_dates    CHECK (DateFinMetier IS NULL OR DateFinMetier > DateDebutMetier),
  CONSTRAINT ck_exr_contrat  CHECK (TypeContrat IN ('CDI','CDD','ALTERNANCE','STAGE','INTERIM'))
);

CREATE TABLE FABRICANT (
  CodeFAB  VARCHAR2(10)  CONSTRAINT pk_fabricant PRIMARY KEY,
  NomFAB   VARCHAR2(50)  NOT NULL,
  PaysFAB  VARCHAR2(50)
);

CREATE TABLE GENERATION (
  CodeGEN        VARCHAR2(10)  CONSTRAINT pk_generation PRIMARY KEY,
  NomGEN         VARCHAR2(50)  NOT NULL,
  DateSortieGEN  DATE          NOT NULL,
  DateArretGEN   DATE,
  CodeFAB        VARCHAR2(10)  NOT NULL CONSTRAINT fk_gen_fab REFERENCES FABRICANT(CodeFAB),
  CONSTRAINT ck_gen_dates CHECK (DateArretGEN IS NULL OR DateArretGEN > DateSortieGEN)
);

CREATE TABLE GAMME (
  CodeG     CHAR(5)      CONSTRAINT pk_gamme PRIMARY KEY,
  NomG      VARCHAR2(50) NOT NULL,
  SecteurG  VARCHAR2(50) NOT NULL,
  CONSTRAINT ck_gam_secteur CHECK (SecteurG IN ('Vélos','Equipement du cycliste',
                                                'Micromobilité','Services et entretien'))
);

CREATE TABLE PRODUIT (
  CodeP        NUMBER(10)    CONSTRAINT pk_produit PRIMARY KEY,
  NomP         VARCHAR2(50)  NOT NULL,
  MarqueP      VARCHAR2(50),
  DescriptifP  VARCHAR2(500),
  PoidsKg      NUMBER(6,2),
  AutonomieKm  NUMBER(5),
  CodeG        CHAR(5)       NOT NULL CONSTRAINT fk_pro_gamme REFERENCES GAMME(CodeG),
  CodeGEN      VARCHAR2(10)  NOT NULL CONSTRAINT fk_pro_gen REFERENCES GENERATION(CodeGEN),
  CONSTRAINT ck_pro_poids CHECK (PoidsKg IS NULL OR PoidsKg > 0),
  CONSTRAINT ck_pro_auto  CHECK (AutonomieKm IS NULL OR AutonomieKm > 0)
);

CREATE TABLE TARIF (
  CodeP           NUMBER(10)   CONSTRAINT fk_tar_produit REFERENCES PRODUIT(CodeP),
  CodePays        CHAR(2)      CONSTRAINT fk_tar_pays REFERENCES PAYS(CodePays),
  DateDebutTarif  DATE,
  DateFinTarif    DATE,
  Prix_loc_jour   NUMBER(10,2),
  Prix_vente      NUMBER(10,2) NOT NULL,
  ModePrix        VARCHAR2(3)  NOT NULL,
  CONSTRAINT pk_tarif         PRIMARY KEY (CodeP, CodePays, DateDebutTarif),
  CONSTRAINT ck_tar_dates     CHECK (DateFinTarif IS NULL OR DateFinTarif > DateDebutTarif),
  CONSTRAINT ck_tar_loc       CHECK (Prix_loc_jour IS NULL OR Prix_loc_jour > 0),
  CONSTRAINT ck_tar_vente     CHECK (Prix_vente > 0 AND (Prix_loc_jour IS NULL OR Prix_vente > Prix_loc_jour)),
  CONSTRAINT ck_tar_mode      CHECK (ModePrix IN ('HT','TTC')),

  CONSTRAINT ck_tar_pays_mode CHECK ( (CodePays = 'FR' AND ModePrix = 'TTC')
                                   OR (CodePays = 'DE' AND ModePrix = 'HT') )
);

CREATE TABLE AGENCE (
  CodeAG    VARCHAR2(10)  CONSTRAINT pk_agence PRIMARY KEY,
  NomAG     VARCHAR2(50)  NOT NULL,
  VilleAG   VARCHAR2(50)  NOT NULL,
  CodePays  CHAR(2)       NOT NULL CONSTRAINT fk_ag_pays REFERENCES PAYS(CodePays)
);

CREATE TABLE EXEMPLAIRE (
  CodeEX             NUMBER(10)    CONSTRAINT pk_exemplaire PRIMARY KEY,
  NumSerieEX         VARCHAR2(30)  NOT NULL CONSTRAINT uq_ex_serie UNIQUE,
  DateMiseServiceEX  DATE          NOT NULL,
  DateReformeEX      DATE,
  CodeP              NUMBER(10)    NOT NULL CONSTRAINT fk_ex_produit REFERENCES PRODUIT(CodeP),
  CodeAG             VARCHAR2(10)  NOT NULL CONSTRAINT fk_ex_agence REFERENCES AGENCE(CodeAG),
  CONSTRAINT ck_ex_code  CHECK (CodeEX > 0),
  CONSTRAINT ck_ex_dates CHECK (DateReformeEX IS NULL OR DateReformeEX > DateMiseServiceEX)
);

CREATE TABLE REDUCTION (
  CodeG           CHAR(5)     CONSTRAINT fk_red_gamme REFERENCES GAMME(CodeG),
  CodeCAT         CHAR(5)     CONSTRAINT fk_red_cat REFERENCES CATEGORIE(CodeCAT),
  CodePays        CHAR(2)     CONSTRAINT fk_red_pays REFERENCES PAYS(CodePays),
  Annee           NUMBER(4),
  PctReduc_Loc    NUMBER(4,3) NOT NULL,
  PctReduc_Achat  NUMBER(4,3) NOT NULL,
  CONSTRAINT pk_reduction  PRIMARY KEY (CodeG, CodeCAT, CodePays, Annee),
  CONSTRAINT ck_red_loc    CHECK (PctReduc_Loc > 0 AND PctReduc_Loc <= 1),
  CONSTRAINT ck_red_achat  CHECK (PctReduc_Achat > 0 AND PctReduc_Achat <= 1)
);

CREATE TABLE ACHAT (
  CodeP  NUMBER(10) CONSTRAINT fk_ach_produit REFERENCES PRODUIT(CodeP),
  CodeE  NUMBER(10) CONSTRAINT fk_ach_employe REFERENCES EMPLOYE(CodeE),
  DateA  DATE,
  Qte    NUMBER(5)  NOT NULL,
  CONSTRAINT pk_achat    PRIMARY KEY (CodeP, CodeE, DateA),
  CONSTRAINT ck_ach_qte  CHECK (Qte > 0)
);

CREATE TABLE RESERVER (
  CodeP       NUMBER(10) CONSTRAINT fk_res_produit REFERENCES PRODUIT(CodeP),
  CodeE       NUMBER(10) CONSTRAINT fk_res_employe REFERENCES EMPLOYE(CodeE),
  DateLPrev   DATE,
  Nb_Ex_Prev  NUMBER(3)  NOT NULL,
  DateResa    DATE       NOT NULL,
  Duree_Prev  NUMBER(4)  NOT NULL,
  CONSTRAINT pk_reserver   PRIMARY KEY (CodeP, CodeE, DateLPrev),
  CONSTRAINT ck_res_nb     CHECK (Nb_Ex_Prev > 0),
  CONSTRAINT ck_res_duree  CHECK (Duree_Prev > 0),
  CONSTRAINT ck_res_dates  CHECK (DateResa <= DateLPrev)
);

CREATE TABLE LOUER (
  CodeEX     NUMBER(10) CONSTRAINT fk_lou_exemplaire REFERENCES EXEMPLAIRE(CodeEX),
  CodeE      NUMBER(10) CONSTRAINT fk_lou_employe REFERENCES EMPLOYE(CodeE),
  DateL      DATE,
  Duree_Loc  NUMBER(4)  NOT NULL,
  CONSTRAINT pk_louer      PRIMARY KEY (CodeEX, CodeE, DateL),
  CONSTRAINT ck_lou_duree  CHECK (Duree_Loc > 0)
);

CREATE OR REPLACE TRIGGER trg_achat_date
BEFORE INSERT OR UPDATE OF DateA ON ACHAT
FOR EACH ROW
BEGIN
  IF :NEW.DateA > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20001, 'DateA ne peut pas être dans le futur');
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_louer_date
BEFORE INSERT OR UPDATE OF DateL ON LOUER
FOR EACH ROW
BEGIN
  IF :NEW.DateL > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20002, 'DateL ne peut pas être dans le futur');
  END IF;
END;
/

CREATE INDEX idx_ach_employe    ON ACHAT(CodeE);
CREATE INDEX idx_lou_employe    ON LOUER(CodeE);
CREATE INDEX idx_res_employe    ON RESERVER(CodeE);
CREATE INDEX idx_emp_service    ON EMPLOYE(CodeSE);
CREATE INDEX idx_ctg_categorie  ON CATEGORISER(CodeCAT);
CREATE INDEX idx_ex_produit     ON EXEMPLAIRE(CodeP);
CREATE INDEX idx_pro_gamme      ON PRODUIT(CodeG);
CREATE INDEX idx_soc_zone       ON SOCIETE(CodeZG);
CREATE INDEX idx_se_societe     ON SERVICE(CodeSOC);

SELECT COUNT(*) AS nb_tables FROM user_tables;

SELECT table_name FROM user_tables ORDER BY table_name;

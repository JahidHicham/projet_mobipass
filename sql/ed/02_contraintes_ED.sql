-- MobiPass - Entrepôt de données : contraintes, triggers et index (Oracle 11g, schéma ABEHS)
-- À lancer après 01_creation_ED.sql. Les règles viennent des annexes 1, 2 et 3 du sujet
-- et de la figure 2 (découpage administratif de l'Allemagne).

ALTER TABLE PAYS ADD (
  CONSTRAINT ck_pays_code CHECK (CodePays IN ('FR','DE')),
  CONSTRAINT ck_pays_tva  CHECK (TauxTVA > 0 AND TauxTVA < 1)
);

-- Figure 2 : Land > District (4 Länder seulement) > Kreis (Landkreis ou kreisfreie Stadt) > Gemeinde ;
-- les villes-États (Berlin, Hambourg, Brême) sont découpées directement en Bezirke.
-- Codes allemands : 'DE' + préfixe du code AGS Destatis (Land 2 chiffres, district 3, Kreis 5, Gemeinde 8),
-- ex. DE09, DE091, DE09162, DE09162000 (München). Les Bezirke n'ont pas de code AGS officiel.
ALTER TABLE ZONE_GEO ADD (
  CONSTRAINT ck_zg_niveau CHECK ( (CodePays = 'FR' AND NiveauZG IN ('COMMUNE','DEPARTEMENT','REGION'))
                               OR (CodePays = 'DE' AND NiveauZG IN ('GEMEINDE','BEZIRK','KREIS','DISTRICT','LAND')) ),
  CONSTRAINT ck_zg_sommet CHECK ( (NiveauZG IN ('REGION','LAND') AND CodeZG_zone_englobante IS NULL)
                               OR (NiveauZG NOT IN ('REGION','LAND') AND CodeZG_zone_englobante IS NOT NULL) )
);

-- Sujet V3 + client (14/10) : NAF rév. 2, 4 niveaux retenus sur 5 (la section lettre est écartée)
-- division '62' -> groupe '62.0' -> classe '62.01' -> sous-classe '62.01Z' ; le code enfant commence par le code parent
ALTER TABLE DOMAINE ADD (
  CONSTRAINT ck_do_masque CHECK (REGEXP_LIKE(CodeDO, '^[0-9]{2}(\.[0-9]([0-9][A-Z]?)?)?$')),
  CONSTRAINT ck_do_super  CHECK ( (LENGTH(CodeDO) = 2 AND CodeDO_Sup IS NULL)
                               OR (LENGTH(CodeDO) > 2 AND CodeDO_Sup IS NOT NULL
                                   AND LENGTH(CodeDO_Sup) = DECODE(LENGTH(CodeDO), 4, 2, 5, 4, 6, 5)
                                   AND CodeDO LIKE CodeDO_Sup || '%') )
);

-- INSEE : niveau I = 1 caractère, niveau II = 2, niveau III = 4, et le code enfant commence par le code parent
-- Formes allemandes (RG15) : même hiérarchie avec des codes préfixés par D (D -> D1 -> D101 GmbH)
ALTER TABLE CATEGORIE_JURIDIQUE ADD (
  CONSTRAINT ck_cj_niveau   CHECK (NiveauCJ IN (1,2,3)),
  CONSTRAINT ck_cj_longueur CHECK (LENGTH(CodeCJ) = DECODE(NiveauCJ, 1, 1, 2, 2, 3, 4)),
  CONSTRAINT ck_cj_sup      CHECK ( (NiveauCJ = 1 AND CodeCJ_niveau_superieur IS NULL)
                                 OR (NiveauCJ > 1 AND CodeCJ_niveau_superieur IS NOT NULL
                                     AND CodeCJ LIKE CodeCJ_niveau_superieur || '%') )
);

ALTER TABLE TYPE_SOCIETE ADD CONSTRAINT ck_ty_code CHECK (CodeTy IN ('MICRO','PME','ETI','GE'));

-- RG16 : SIREN (9 chiffres) pour la France, USt-IdNr (DE + 9 chiffres) pour l'Allemagne
ALTER TABLE SOCIETE ADD CONSTRAINT ck_soc_code CHECK (REGEXP_LIKE(CodeSOC, '^([0-9]{9}|DE[0-9]{9})$'));

-- Annexe 2 : masque AA-99 ; les classes de trajet sont fixes
ALTER TABLE CATEGORIE ADD (
  CONSTRAINT ck_cat_masque CHECK (REGEXP_LIKE(CodeCAT, '^[A-Z]{2}-[0-9]{2}$')),
  CONSTRAINT ck_cat_classe CHECK ( (SUBSTR(CodeCAT, 1, 2) = 'TC' AND SuperCAT = 'Trajet court (moins de 5 km)')
                                OR (SUBSTR(CodeCAT, 1, 2) = 'TM' AND SuperCAT = 'Trajet moyen (5 à 15 km)')
                                OR (SUBSTR(CodeCAT, 1, 2) = 'TL' AND SuperCAT = 'Trajet long (plus de 15 km)')
                                OR (SUBSTR(CodeCAT, 1, 2) = 'TI' AND SuperCAT = 'Trajet intermodal') )
);

-- Annexe 3
ALTER TABLE GAMME ADD CONSTRAINT ck_gam_secteur CHECK (SecteurG IN ('Vélos','Equipement du cycliste',
                                                                    'Micromobilité','Services et entretien'));

ALTER TABLE GENERATION ADD CONSTRAINT ck_gen_dates CHECK (DateArretGEN IS NULL OR DateArretGEN > DateSortieGEN);

ALTER TABLE PRODUIT ADD (
  CONSTRAINT ck_pro_poids     CHECK (PoidsKg IS NULL OR PoidsKg > 0),
  CONSTRAINT ck_pro_autonomie CHECK (AutonomieKm IS NULL OR AutonomieKm > 0)
);

ALTER TABLE EXEMPLAIRE ADD (
  CONSTRAINT uq_ex_numserie UNIQUE (NumSerieEX),
  CONSTRAINT ck_ex_code     CHECK (CodeEX > 0),
  CONSTRAINT ck_ex_dates    CHECK (DateReformeEX IS NULL OR DateReformeEX > DateMiseServiceEX)
);

ALTER TABLE PARTENAIRE ADD CONSTRAINT ck_part_taux CHECK (TauxRemise > 0 AND TauxRemise <= 1);

ALTER TABLE SERVICE ADD CONSTRAINT ck_se_code CHECK (CodeSE > 0);
ALTER TABLE EMPLOYE ADD CONSTRAINT ck_emp_code CHECK (CodeE > 0);

ALTER TABLE ETRE_AFFECTE ADD CONSTRAINT ck_aff_dates CHECK (DateFinAffect IS NULL OR DateFinAffect > DateDebutAffect);

-- RG6 : NumEtab = SIRET pour la France (14 chiffres), Betriebsnummer pour l'Allemagne (8 chiffres).
-- (La USt-IdNr identifie la société : c'est le CodeSOC, pas le numéro d'établissement.)
-- Les codes postaux font 5 chiffres dans les deux pays.
ALTER TABLE SALARIE_RH ADD (
  CONSTRAINT ck_sal_numetab CHECK (REGEXP_LIKE(NumEtab, '^[0-9]{14}$') OR REGEXP_LIKE(NumEtab, '^[0-9]{8}$')),
  CONSTRAINT ck_sal_cp      CHECK (CPResidenceSAL IS NULL OR REGEXP_LIKE(CPResidenceSAL, '^[0-9]{5}$')),
  CONSTRAINT ck_sal_dates   CHECK (DateEntreeSAL IS NULL OR DateNaissSAL IS NULL OR DateEntreeSAL > DateNaissSAL)
);

ALTER TABLE EXERCER ADD (
  CONSTRAINT ck_exr_dates   CHECK (DateFinMetier IS NULL OR DateFinMetier > DateDebutMetier),
  CONSTRAINT ck_exr_contrat CHECK (TypeContrat IN ('CDI','CDD','ALTERNANCE','STAGE','INTERIM')),
  -- RG9 : le ROME est français, seuls les salariés d'un établissement français (SIRET) ont un métier
  CONSTRAINT ck_exr_france  CHECK (REGEXP_LIKE(NumEtab, '^[0-9]{14}$'))
);

-- Annexe 1 : réductions > 0 et <= 1
ALTER TABLE REDUCTION ADD (
  CONSTRAINT ck_red_loc   CHECK (PctReduc_Loc > 0 AND PctReduc_Loc <= 1),
  CONSTRAINT ck_red_achat CHECK (PctReduc_Achat > 0 AND PctReduc_Achat <= 1),
  CONSTRAINT ck_red_annee CHECK (Annee BETWEEN 2000 AND 2100)
);

-- Annexe 1 : Prix_loc_jour > 0 et Prix_vente > Prix_loc_jour ; tarifs FR en TTC, DE en HT
ALTER TABLE TARIFER ADD (
  CONSTRAINT ck_tar_dates     CHECK (DateFinTarif IS NULL OR DateFinTarif > DateDebutTarif),
  CONSTRAINT ck_tar_loc       CHECK (Prix_loc_jour IS NULL OR Prix_loc_jour > 0),
  CONSTRAINT ck_tar_vente     CHECK (Prix_vente > 0 AND (Prix_loc_jour IS NULL OR Prix_vente > Prix_loc_jour)),
  CONSTRAINT ck_tar_pays_mode CHECK ( (CodePays = 'FR' AND ModePrix = 'TTC')
                                   OR (CodePays = 'DE' AND ModePrix = 'HT') )
);

ALTER TABLE ACHAT ADD CONSTRAINT ck_ach_qte CHECK (Qte > 0);

ALTER TABLE RESERVER ADD (
  CONSTRAINT ck_res_nb    CHECK (Nb_Ex_Prev > 0),
  CONSTRAINT ck_res_duree CHECK (Duree_Prev > 0),
  CONSTRAINT ck_res_dates CHECK (DateResa <= DateLPrev)
);

ALTER TABLE LOUER ADD CONSTRAINT ck_lou_duree CHECK (Duree_Loc > 0);

-- Les règles qui comparent à la date du jour ne peuvent pas être des CHECK (SYSDATE interdit) : triggers.

CREATE OR REPLACE TRIGGER trg_acheter_date
BEFORE INSERT OR UPDATE OF DateA ON ACHAT
FOR EACH ROW
BEGIN
  IF :NEW.DateA > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20001, 'DateA ne peut pas être dans le futur');
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_acheter_part_date
BEFORE INSERT OR UPDATE OF DateA ON ACHETER_PARTENAIRE
FOR EACH ROW
BEGIN
  IF :NEW.DateA > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20005, 'DateA ne peut pas être dans le futur (achat partenaire)');
  END IF;
END;
/

-- Annexe 1 : DateLPrev < date()
CREATE OR REPLACE TRIGGER trg_reserver_date
BEFORE INSERT OR UPDATE OF DateLPrev ON RESERVER
FOR EACH ROW
BEGIN
  IF :NEW.DateLPrev >= TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20004, 'DateLPrev doit être antérieure à la date du jour');
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_louer_controle
BEFORE INSERT OR UPDATE OF DateL, Duree_Loc, CodeEX ON LOUER
FOR EACH ROW
DECLARE
  v_mise_service  DATE;
  v_reforme       DATE;
BEGIN
  IF :NEW.DateL > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20002, 'DateL ne peut pas être dans le futur');
  END IF;
  SELECT DateMiseServiceEX, DateReformeEX
    INTO v_mise_service, v_reforme
    FROM EXEMPLAIRE
   WHERE CodeEX = :NEW.CodeEX;
  IF :NEW.DateL < v_mise_service
     OR (v_reforme IS NOT NULL AND :NEW.DateL + :NEW.Duree_Loc > v_reforme) THEN
    RAISE_APPLICATION_ERROR(-20003, 'Location en dehors de la période de service de l''exemplaire');
  END IF;
END;
/

-- Trigger de niveau instruction : il relit toute la table à chaque INSERT.
-- Pour charger les communes (environ 46 000 lignes), le désactiver avant le chargement puis le réactiver :
--   ALTER TRIGGER trg_zg_coherence DISABLE;  ... chargement ...  ALTER TRIGGER trg_zg_coherence ENABLE;
-- et lancer une fois la requête de contrôle du trigger.
CREATE OR REPLACE TRIGGER trg_zg_coherence
AFTER INSERT OR UPDATE ON ZONE_GEO
DECLARE
  v_nb  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_nb
    FROM ZONE_GEO f
    JOIN ZONE_GEO p ON p.CodeZG = f.CodeZG_zone_englobante
   WHERE p.CodePays <> f.CodePays
      OR NOT ( (f.NiveauZG = 'COMMUNE'     AND p.NiveauZG = 'DEPARTEMENT')
            OR (f.NiveauZG = 'DEPARTEMENT' AND p.NiveauZG = 'REGION')
            OR (f.NiveauZG = 'GEMEINDE'    AND p.NiveauZG = 'KREIS')
            OR (f.NiveauZG = 'BEZIRK'      AND p.NiveauZG = 'LAND')
            OR (f.NiveauZG = 'KREIS'       AND p.NiveauZG IN ('DISTRICT','LAND'))
            OR (f.NiveauZG = 'DISTRICT'    AND p.NiveauZG = 'LAND') );
  IF v_nb > 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'Zone rattachée à un parent de mauvais niveau ou d''un autre pays');
  END IF;
END;
/

CREATE INDEX idx_zg_englobante  ON ZONE_GEO(CodeZG_zone_englobante);
CREATE INDEX idx_soc_zone       ON SOCIETE(CodeZG);
CREATE INDEX idx_se_societe     ON SERVICE(CodeSOC);
CREATE INDEX idx_emp_service    ON EMPLOYE(CodeSE);
CREATE INDEX idx_emp_categorie  ON EMPLOYE(CodeCAT);
CREATE INDEX idx_aff_service    ON ETRE_AFFECTE(CodeSE);
CREATE INDEX idx_pro_gamme      ON PRODUIT(CodeG);
CREATE INDEX idx_ex_produit     ON EXEMPLAIRE(CodeP);
CREATE INDEX idx_exr_appel      ON EXERCER(CodeAPP);
CREATE INDEX idx_ach_produit    ON ACHAT(CodeP);
CREATE INDEX idx_res_produit    ON RESERVER(CodeP);
CREATE INDEX idx_lou_exemplaire ON LOUER(CodeEX);
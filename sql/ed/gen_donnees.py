# -*- coding: utf-8 -*-
"""Génération des données de l'ED MobiPass V2 -> 03_insertion_ED.sql (Oracle 11g)
Graine fixe : le script produit toujours les mêmes données."""
import random, datetime as dt, re, collections, os
random.seed(2026)
D = dt.date
TODAY = D(2026, 10, 14)          # date de génération ; toutes les dates d'activité sont < TODAY
LAST = TODAY - dt.timedelta(1)
START = D(2024, 10, 14)          # début de l'historique (2 ans)
DE_START = D(2026, 1, 5)         # l'offre MobiPass est étendue à l'Allemagne « cette année »
PART_START = D(2026, 1, 5)       # partenariat Alltricks conclu « cette année »
def days(a, b): return (b - a).days
def addd(d, n): return d + dt.timedelta(n)

rows = collections.OrderedDict()   # table -> liste de dicts
def ins(t, **kv): rows.setdefault(t, []).append(kv)

# ------------------------------------------------------------------ saisonnalité
MONTH_W = {1:.55,2:.6,3:.9,4:1.2,5:1.45,6:1.55,7:1.4,8:.95,9:1.35,10:1.0,11:.65,12:.5}
DOW_W = [1,1,1,1,1,.55,.3]
def wdate(a, b, season=True):
    """date entre a et b (inclus), pondérée par la saison et le jour de semaine"""
    ds = [addd(a, i) for i in range(days(a, b) + 1)]
    if not season: return random.choice(ds)
    w = [MONTH_W[d.month] * DOW_W[d.weekday()] for d in ds]
    return random.choices(ds, w)[0]

# ------------------------------------------------------------------ PAYS
ins('PAYS', CodePays='FR', NomPays='France', TauxTVA=0.2)
ins('PAYS', CodePays='DE', NomPays='Allemagne', TauxTVA=0.19)

# ------------------------------------------------------------------ ZONE_GEO
# France : région 'R'+code INSEE, département 'D'+code, commune = code INSEE (5 car.)
REG = {'11':'Île-de-France','84':'Auvergne-Rhône-Alpes','76':'Occitanie','75':'Nouvelle-Aquitaine',
       '93':"Provence-Alpes-Côte d'Azur",'32':'Hauts-de-France','52':'Pays de la Loire','53':'Bretagne','44':'Grand Est'}
DEP = {'75':('Paris','11'),'92':('Hauts-de-Seine','11'),'69':('Rhône','84'),'31':('Haute-Garonne','76'),
       '33':('Gironde','75'),'13':('Bouches-du-Rhône','93'),'59':('Nord','32'),'44':('Loire-Atlantique','52'),
       '35':('Ille-et-Vilaine','53'),'67':('Bas-Rhin','44')}
COM = {'75056':('Paris','75'),'92012':('Boulogne-Billancourt','92'),'69123':('Lyon','69'),'69266':('Villeurbanne','69'),
       '31555':('Toulouse','31'),'31069':('Blagnac','31'),'33063':('Bordeaux','33'),'13055':('Marseille','13'),
       '59350':('Lille','59'),'44109':('Nantes','44'),'35238':('Rennes','35'),'67482':('Strasbourg','67')}
for c,n in REG.items(): ins('ZONE_GEO', CodeZG='R'+c, NomZG=n, NiveauZG='REGION', CodeZG_zone_englobante=None, CodePays='FR')
for c,(n,r) in DEP.items(): ins('ZONE_GEO', CodeZG='D'+c, NomZG=n, NiveauZG='DEPARTEMENT', CodeZG_zone_englobante='R'+r, CodePays='FR')
for c,(n,d) in COM.items(): ins('ZONE_GEO', CodeZG=c, NomZG=n, NiveauZG='COMMUNE', CodeZG_zone_englobante='D'+d, CodePays='FR')
# Allemagne : 'DE' + préfixe AGS Destatis
LAND = {'01':'Schleswig-Holstein','02':'Hamburg','03':'Niedersachsen','04':'Bremen','05':'Nordrhein-Westfalen',
        '06':'Hessen','07':'Rheinland-Pfalz','08':'Baden-Württemberg','09':'Bayern','10':'Saarland','11':'Berlin',
        '12':'Brandenburg','13':'Mecklenburg-Vorpommern','14':'Sachsen','15':'Sachsen-Anhalt','16':'Thüringen'}
RB = {'081':'Stuttgart','082':'Karlsruhe','083':'Freiburg','084':'Tübingen','091':'Oberbayern','092':'Niederbayern',
      '093':'Oberpfalz','094':'Oberfranken','095':'Mittelfranken','096':'Unterfranken','097':'Schwaben',
      '064':'Darmstadt','065':'Gießen','066':'Kassel','051':'Düsseldorf','053':'Köln','055':'Münster',
      '057':'Detmold','059':'Arnsberg'}
# Kreis (AGS 5 chiffres) : nom, district (None si le Land n'a pas de district)
KREIS = {'11000':('Berlin',None),'02000':('Hamburg',None),'09162':('München, Landeshauptstadt','091'),
         '09184':('München, Landkreis','091'),'05315':('Köln, Stadt','053'),'06412':('Frankfurt am Main, Stadt','064'),
         '08111':('Stuttgart, Landeshauptstadt','081'),'05111':('Düsseldorf, Stadt','051'),'09564':('Nürnberg','095')}
GEM = {'11000000':'Berlin','02000000':'Hamburg','09162000':'München','09184119':'Garching b.München',
       '05315000':'Köln','06412000':'Frankfurt am Main','08111000':'Stuttgart','05111000':'Düsseldorf','09564000':'Nürnberg'}
for c,n in LAND.items(): ins('ZONE_GEO', CodeZG='DE'+c, NomZG=n, NiveauZG='LAND', CodeZG_zone_englobante=None, CodePays='DE')
for c,n in RB.items(): ins('ZONE_GEO', CodeZG='DE'+c, NomZG=n, NiveauZG='DISTRICT', CodeZG_zone_englobante='DE'+c[:2], CodePays='DE')
for c,(n,rb) in KREIS.items(): ins('ZONE_GEO', CodeZG='DE'+c, NomZG=n, NiveauZG='KREIS', CodeZG_zone_englobante='DE'+(rb or c[:2]), CodePays='DE')
for c,n in GEM.items(): ins('ZONE_GEO', CodeZG='DE'+c, NomZG=n, NiveauZG='GEMEINDE', CodeZG_zone_englobante='DE'+c[:5], CodePays='DE')

# ------------------------------------------------------------------ DOMAINE (NAF rév. 2)
NAF = [('62',"Programmation, conseil et autres activités informatiques",None),
       ('62.0',"Programmation, conseil et autres activités informatiques",'62'),
       ('62.01',"Programmation informatique",'62.0'),('62.01Z',"Programmation informatique",'62.01'),
       ('62.02',"Conseil informatique",'62.0'),('62.02A',"Conseil en systèmes et logiciels informatiques",'62.02'),
       ('70',"Activités des sièges sociaux ; conseil de gestion",None),('70.2',"Conseil de gestion",'70'),
       ('70.22',"Conseil pour les affaires et autres conseils de gestion",'70.2'),
       ('70.22Z',"Conseil pour les affaires et autres conseils de gestion",'70.22'),
       ('47',"Commerce de détail, à l'exception des automobiles et des motocycles",None),
       ('47.1',"Commerce de détail en magasin non spécialisé",'47'),
       ('47.11',"Commerce de détail en magasin non spécialisé à prédominance alimentaire",'47.1'),
       ('47.11F',"Hypermarchés",'47.11'),
       ('30',"Fabrication d'autres matériels de transport",None),('30.3',"Construction aéronautique et spatiale",'30'),
       ('30.30',"Construction aéronautique et spatiale",'30.3'),('30.30Z',"Construction aéronautique et spatiale",'30.30'),
       ('64',"Activités des services financiers, hors assurance et caisses de retraite",None),
       ('64.1',"Intermédiation monétaire",'64'),('64.19',"Autres intermédiations monétaires",'64.1'),
       ('64.19Z',"Autres intermédiations monétaires",'64.19'),
       ('86',"Activités pour la santé humaine",None),('86.1',"Activités hospitalières",'86'),
       ('86.10',"Activités hospitalières",'86.1'),('86.10Z',"Activités hospitalières",'86.10'),
       ('85',"Enseignement",None),('85.4',"Enseignement supérieur et post-secondaire non supérieur",'85'),
       ('85.42',"Enseignement supérieur",'85.4'),('85.42Z',"Enseignement supérieur",'85.42'),
       ('49',"Transports terrestres et transport par conduites",None),
       ('49.39A',"Transports routiers réguliers de voyageurs",'49')]   # exemple de l'annexe 1 (49.39A -> 49)
for c,n,s in NAF: ins('DOMAINE', CodeDO=c, NomDO=n, CodeDO_Sup=s)

# ------------------------------------------------------------------ CATEGORIE_JURIDIQUE
CJ = [('1',"Entrepreneur individuel",1,None),('10',"Entrepreneur individuel",2,'1'),('1000',"Entrepreneur individuel",3,'10'),
      ('5',"Société commerciale",1,None),('54',"Société à responsabilité limitée (SARL)",2,'5'),
      ('5499',"Société à responsabilité limitée (sans autre indication)",3,'54'),
      ('55',"Société anonyme à conseil d'administration",2,'5'),
      ('5599',"SA à conseil d'administration (s.a.i.)",3,'55'),
      ('57',"Société par actions simplifiée",2,'5'),('5710',"SAS, société par actions simplifiée",3,'57'),
      ('7',"Personne morale et organisme soumis au droit administratif",1,None),
      ('73',"Établissement public administratif",2,'7'),
      ('7383',"Établissement public national à caractère scientifique culturel et professionnel",3,'73'),
      ('D',"Formes juridiques allemandes",1,None),
      ('D1',"Kapitalgesellschaften (sociétés de capitaux)",2,'D'),('D101',"GmbH",3,'D1'),
      ('D102',"UG (haftungsbeschränkt)",3,'D1'),('D103',"AG",3,'D1'),
      ('D2',"Personengesellschaften (sociétés de personnes)",2,'D'),('D201',"KG",3,'D2'),('D202',"OHG",3,'D2'),
      ('D203',"GmbH & Co. KG",3,'D2'),('D204',"GbR",3,'D2'),
      ('D3',"Einzelunternehmen (entreprise individuelle)",2,'D'),('D301',"e.K.",3,'D3')]
for c,l,n,s in CJ: ins('CATEGORIE_JURIDIQUE', CodeCJ=c, LibelleCJ=l, NiveauCJ=n, CodeCJ_niveau_superieur=s)

for c,l in [('MICRO','Microentreprise'),('PME','Petite ou moyenne entreprise'),('ETI',"Entreprise de taille intermédiaire"),('GE','Grande entreprise')]:
    ins('TYPE_SOCIETE', CodeTy=c, LibelleTypeSoc=l)

# ------------------------------------------------------------------ CATEGORIE (annexe 2)
SC = {'TC':'Trajet court (moins de 5 km)','TM':'Trajet moyen (5 à 15 km)','TL':'Trajet long (plus de 15 km)','TI':'Trajet intermodal'}
CATS = [('TC-01','Trajet de moins de 2 km en zone urbaine dense'),('TC-02','Trajet de 2 à 5 km en zone urbaine'),
        ('TC-03','Trajet de moins de 5 km en zone périurbaine ou rurale'),('TM-01','Trajet de 5 à 10 km avec faible dénivelé'),
        ('TM-02','Trajet de 5 à 10 km avec dénivelé important'),('TM-03','Trajet de 10 à 15 km avec faible dénivelé'),
        ('TM-04','Trajet de 10 à 15 km avec dénivelé important'),('TL-01','Trajet de 15 à 25 km'),('TL-02','Trajet de plus de 25 km'),
        ('TI-01','Trajet vélo + train (TER, Regionalbahn)'),('TI-02','Trajet vélo + transports urbains (métro, tramway, S-Bahn)'),
        ('TI-03','Trajet vélo + covoiturage')]
for c,n in CATS: ins('CATEGORIE', CodeCAT=c, NomCAT=n, SuperCAT=SC[c[:2]])
CAT_W = {'TC-01':10,'TC-02':14,'TC-03':5,'TM-01':12,'TM-02':5,'TM-03':8,'TM-04':3,'TL-01':6,'TL-02':3,'TI-01':7,'TI-02':9,'TI-03':2}

# ------------------------------------------------------------------ ROME (4 niveaux) ; appellations illustratives
GD = {'M':"Support à l'entreprise",'J':'Santé','H':'Industrie','D':'Commerce, vente et grande distribution',
      'K':'Services à la personne et à la collectivité','N':'Transport et logistique'}
DP = {'M18':("Systèmes d'information et de télécommunication",'M'),'M16':('Secrétariat et assistance','M'),
      'M12':('Comptabilité et gestion','M'),'M15':('Ressources humaines','M'),'M13':("Direction d'entreprise",'M'),
      'M17':('Marketing et stratégie commerciale','M'),'J15':('Soins paramédicaux','J'),
      'H12':('Conception, recherche, études et développement','H'),'D15':('Grande distribution','D'),
      'K21':('Formation initiale et continue','K'),'N11':('Magasinage, manutention des charges et déménagement','N')}
FM = {'M1805':('Études et développement informatique','M18'),'M1806':("Conseil et maîtrise d'ouvrage en systèmes d'information",'M18'),
      'M1607':('Secrétariat','M16'),'M1203':('Comptabilité','M12'),'M1503':('Management des ressources humaines','M15'),
      'M1302':('Direction de petite ou moyenne entreprise','M13'),'M1705':('Marketing','M17'),
      'J1506':('Soins infirmiers généralistes','J15'),'H1206':('Management et ingénierie études, recherche et développement industriel','H12'),
      'D1507':('Mise en rayon libre-service','D15'),'K2108':('Enseignement supérieur','K21'),
      'N1103':('Magasinage et préparation de commandes','N11')}
APP = {}
APPL = {'M1805':['Développeur / Développeuse informatique','Analyste programmeur / programmeuse'],
        'M1806':["Consultant / Consultante en systèmes d'information",'Chef de projet maîtrise d\'ouvrage'],
        'M1607':['Secrétaire','Assistant / Assistante de direction'],'M1203':['Comptable','Aide-comptable'],
        'M1503':['Responsable des ressources humaines','Chargé / Chargée de recrutement'],
        'M1302':["Directeur / Directrice d'entreprise"],'M1705':['Chef de produit marketing','Chargé / Chargée de communication'],
        'J1506':['Infirmier / Infirmière'],'H1206':['Ingénieur / Ingénieure études et développement'],
        'D1507':['Employé / Employée de libre-service'],'K2108':['Enseignant-chercheur / Enseignante-chercheuse'],
        'N1103':['Préparateur / Préparatrice de commandes']}
for c,l in GD.items(): ins('GRAND_DOMAINE', CodeGD=c, LibelleGD=l)
for c,(l,g) in DP.items(): ins('DOMAINE_PRO', CodeDP=c, LibelleDP=l, CodeGD=g)
for c,(l,d) in FM.items(): ins('FICHE_METIER', CodeROME=c, LibelleMetier=l, CodeDP=d)
n = 0
for rome, libs in APPL.items():
    for l in libs:
        n += 1; code = f"{900000+n}"            # codes d'appellation illustratifs (6 chiffres)
        APP.setdefault(rome, []).append(code)
        ins('APPELLATION', CodeAPP=code, LibelleAPP=l, CodeROME=rome)

# ------------------------------------------------------------------ GAMME (annexe 3)
GAM = {'Vélos':['Vélos électriques urbains','VTT électriques','Vélos cargo','Vélos pliants','Vélos de route & gravel','Vélos enfants'],
       'Equipement du cycliste':['Casques','Vêtements de pluie','Antivols','Eclairage & signalisation','Sacoches & bagagerie',
                                 'Sièges enfants & remorques','Gants & accessoires textiles','Compteurs & GPS','Pompes & outillage'],
       'Micromobilité':['Trottinettes électriques','Trottinettes mécaniques','Gyroroues','Hoverboards & gyropodes',
                        'Skateboards électriques','Scooters électriques','Rollers & patins','Batteries & chargeurs','Pièces détachées'],
       'Services et entretien':['Révision & réparation','Assurance vol & casse','Marquage antivol','Stage de remise en selle',
                                'Livraison & reprise à domicile']}
GCODE = {}; k = 0
for sec, gs in GAM.items():
    for g in gs:
        k += 1; GCODE[g] = f"G{k:04d}"; ins('GAMME', CodeG=GCODE[g], NomG=g, SecteurG=sec)

# ------------------------------------------------------------------ FABRICANT, GENERATION
FAB = [('FAB01','Moustache Bikes','France'),('FAB02','Riese & Müller','Allemagne'),('FAB03','Cube Bikes','Allemagne'),
       ('FAB04','Decathlon','France'),('FAB05','Brompton','Royaume-Uni'),('FAB06','Xiaomi','Chine'),('FAB07','Abus','Allemagne'),
       ('FAB08','Ortlieb','Allemagne'),('FAB09','Segway-Ninebot','Chine'),('FAB10','MobiPass Services','France'),
       ('FAB11','Thule','Suède'),('FAB12','Bosch eBike Systems','Allemagne')]
for c,nm,p in FAB: ins('FABRICANT', CodeFAB=c, NomFAB=nm, PaysFAB=p)
GEN = {}
def gen(code, nom, sortie, arret, fab):
    GEN[code] = sortie; ins('GENERATION', CodeGEN=code, NomGEN=nom, DateSortieGEN=sortie, DateArretGEN=arret, CodeFAB=fab)
gen('GEN01','Moustache 2022',D(2021,9,1),D(2024,12,31),'FAB01'); gen('GEN02','Moustache 2025',D(2024,9,1),None,'FAB01')
gen('GEN03','Riese & Müller Gen 4',D(2022,3,1),None,'FAB02'); gen('GEN04','Cube 2023',D(2022,8,1),None,'FAB03')
gen('GEN05','Decathlon Btwin 2022',D(2021,6,1),None,'FAB04'); gen('GEN06','Decathlon Elops 2024',D(2023,9,1),None,'FAB04')
gen('GEN07','Brompton P Line',D(2022,2,1),None,'FAB05'); gen('GEN08','Xiaomi Scooter 4',D(2023,3,1),None,'FAB06')
gen('GEN09','Abus Gen 2023',D(2022,10,1),None,'FAB07'); gen('GEN10','Ortlieb Classic',D(2020,1,1),None,'FAB08')
gen('GEN11','Ninebot Gen 3',D(2022,5,1),None,'FAB09'); gen('GEN12','Services MobiPass',D(2020,1,1),None,'FAB10')
gen('GEN13','Thule 2023',D(2022,9,1),None,'FAB11'); gen('GEN14','Bosch Smart System',D(2022,6,1),None,'FAB12')

# ------------------------------------------------------------------ PRODUIT (prix de base HT : loc/jour, vente)
P = [  # nom, marque, gamme, gen, poids, autonomie, loc_HT, vente_HT, louable
 ('Moustache Lundi 27','Moustache','Vélos électriques urbains','GEN01',24.5,90,14.0,2900,1),
 ('Moustache Lundi 27.3','Moustache','Vélos électriques urbains','GEN02',23.9,110,15.0,3150,1),
 ('Elops 920 E','Btwin','Vélos électriques urbains','GEN06',25.0,80,9.0,1250,1),
 ('Cube Kathmandu Hybrid','Cube','VTT électriques','GEN04',26.8,120,18.0,3300,1),
 ('Moustache Samedi 29','Moustache','VTT électriques','GEN02',23.5,100,20.0,4200,1),
 ('Load 75','Riese & Müller','Vélos cargo','GEN03',38.0,100,25.0,6800,1),
 ('Packster 70','Riese & Müller','Vélos cargo','GEN03',36.0,90,23.0,6100,1),
 ('Brompton P Line','Brompton','Vélos pliants','GEN07',10.0,None,8.0,2900,1),
 ('Tilt 500','Btwin','Vélos pliants','GEN05',13.5,None,4.0,330,1),
 ('Triban RC 520','Btwin','Vélos de route & gravel','GEN05',9.8,None,7.0,950,1),
 ('Cube Nuroad','Cube','Vélos de route & gravel','GEN04',10.2,None,9.0,1300,1),
 ('Btwin Riverside 20','Btwin','Vélos enfants','GEN05',11.0,None,3.0,250,1),
 ('Casque urbain 500','Btwin','Casques','GEN05',0.4,None,1.0,35,1),
 ('Abus Hyban 2.0','Abus','Casques','GEN09',0.45,None,1.5,90,1),
 ('Poncho de pluie 900','Btwin','Vêtements de pluie','GEN05',0.3,None,None,40,0),
 ('Abus Granit X-Plus 540','Abus','Antivols','GEN09',1.5,None,None,110,0),
 ('Abus Bordo 6000','Abus','Antivols','GEN09',1.2,None,None,95,0),
 ('Kit éclairage USB','Btwin','Eclairage & signalisation','GEN05',0.2,None,None,25,0),
 ('Ortlieb Back-Roller Classic','Ortlieb','Sacoches & bagagerie','GEN10',1.9,None,2.0,140,1),
 ('Thule Chariot Cross','Thule','Sièges enfants & remorques','GEN13',13.0,None,6.0,1050,1),
 ('Siège enfant Yepp Maxi','Thule','Sièges enfants & remorques','GEN13',4.2,None,2.0,120,1),
 ('Gants vélo hiver','Btwin','Gants & accessoires textiles','GEN05',0.1,None,None,25,0),
 ('Bosch Kiox 300','Bosch','Compteurs & GPS','GEN14',0.1,None,None,190,0),
 ('Pompe à pied 500','Btwin','Pompes & outillage','GEN05',1.1,None,None,30,0),
 ('Xiaomi Electric Scooter 4 Pro','Xiaomi','Trottinettes électriques','GEN08',17.0,55,6.0,700,1),
 ('Ninebot Max G2','Segway-Ninebot','Trottinettes électriques','GEN11',24.0,70,7.0,850,1),
 ('Oxelo Town 9','Oxelo','Trottinettes mécaniques','GEN06',5.8,None,2.0,150,1),
 ('Ninebot One S2','Segway-Ninebot','Gyroroues','GEN11',11.5,30,6.0,600,1),
 ('Ninebot S Hoverboard','Segway-Ninebot','Hoverboards & gyropodes','GEN11',12.8,22,5.0,450,1),
 ('Skate électrique Urban','Oxelo','Skateboards électriques','GEN06',7.5,20,5.0,500,1),
 ('Ninebot E-Scooter E110','Segway-Ninebot','Scooters électriques','GEN11',80.0,100,15.0,3200,1),
 ('Rollers Fit 500','Oxelo','Rollers & patins','GEN06',2.8,None,None,90,0),
 ('Batterie PowerTube 625','Bosch','Batteries & chargeurs','GEN14',3.5,None,None,700,0),
 ('Pneu urbain 700x40','Btwin','Pièces détachées','GEN05',0.6,None,None,30,0),
 ('Révision complète vélo','MobiPass','Révision & réparation','GEN12',None,None,None,90,0),
 ('Assurance vol & casse 1 an','MobiPass','Assurance vol & casse','GEN12',None,None,None,120,0),
 ('Marquage Bicycode','MobiPass','Marquage antivol','GEN12',None,None,None,15,0),
 ('Stage remise en selle 2 h','MobiPass','Stage de remise en selle','GEN12',None,None,None,45,0),
 ('Livraison et reprise à domicile','MobiPass','Livraison & reprise à domicile','GEN12',None,None,None,25,0),
 ('Vélo cargo Btwin R500E','Btwin','Vélos cargo','GEN06',33.0,60,12.0,2700,1)]
PROD = {}
for i,(nm,mq,g,gn,pk,au,loc,ven,lou) in enumerate(P, 1):
    PROD[i] = dict(nom=nm, gamme=g, gen=gn, loc=loc, vente=ven, louable=bool(lou), sec=[s for s,gs in GAM.items() if g in gs][0])
    ins('PRODUIT', CodeP=i, NomP=nm, MarqueP=mq, DescriptifP=f"{nm} ({g})", PoidsKg=pk, AutonomieKm=au, CodeGEN=gn, CodeG=GCODE[g])

# ------------------------------------------------------------------ TARIFER (FR en TTC, DE en HT)
TARIF = collections.defaultdict(list)   # (pays, codeP) -> [(debut, fin, loc, vente)]
def tarif(pays, p, deb, fin, f):
    pr = PROD[p]; tva = 1.2 if pays == 'FR' else 1.0
    loc = round(pr['loc'] * f * tva, 2) if pr['loc'] else None
    ven = round(pr['vente'] * f * tva, 2)
    TARIF[(pays, p)].append((deb, fin, loc, ven))
    ins('TARIFER', CodePays=pays, CodeP=p, DateDebutTarif=deb, DateFinTarif=fin, Prix_loc_jour=loc, Prix_vente=ven,
        ModePrix='TTC' if pays == 'FR' else 'HT')
for p in PROD:
    tarif('FR', p, D(2024,1,1), D(2024,12,31), 0.95)
    tarif('FR', p, D(2025,1,1), D(2025,12,31), 0.98)
    tarif('FR', p, D(2026,1,1), None, 1.0)
    if PROD[p]['sec'] == 'Vélos':      # en Allemagne, hausse des vélos au 1er juillet 2026
        tarif('DE', p, D(2026,1,1), D(2026,6,30), 0.97); tarif('DE', p, D(2026,7,1), None, 1.02)
    else:
        tarif('DE', p, D(2026,1,1), None, 0.97)

# ------------------------------------------------------------------ AGENCE, EXEMPLAIRE
AG = [('AG-LYO','MobiPass Lyon Part-Dieu','Lyon','FR'),('AG-TLS','MobiPass Toulouse Matabiau','Toulouse','FR'),
      ('AG-PAR','MobiPass Paris La Défense','Paris','FR'),('AG-BOR','MobiPass Bordeaux Saint-Jean','Bordeaux','FR'),
      ('AG-BER','MobiPass Berlin Hauptbahnhof','Berlin','DE'),('AG-MUC','MobiPass München Ost','München','DE'),
      ('AG-KOE','MobiPass Köln Deutz','Köln','DE'),('AG-HAM','MobiPass Hamburg Altona','Hamburg','DE')]
AGP = {}
for c,nm,v,p in AG: AGP[c] = p; ins('AGENCE', CodeAG=c, NomAG=nm, VilleAG=v, CodePays=p)
EX = {}   # code -> dict
LOUABLES = [p for p in PROD if PROD[p]['louable']]
POP = {'Vélos électriques urbains':10,'VTT électriques':4,'Vélos cargo':4,'Vélos pliants':4,'Vélos de route & gravel':3,
       'Vélos enfants':2,'Casques':3,'Sacoches & bagagerie':2,'Sièges enfants & remorques':2,'Trottinettes électriques':7,
       'Trottinettes mécaniques':2,'Gyroroues':1,'Hoverboards & gyropodes':1,'Skateboards électriques':1,'Scooters électriques':2}
ce = 0
for ag,_,_,pays in AG:
    nb = 46 if pays == 'FR' else 18
    for _ in range(nb):
        p = random.choices(LOUABLES, [POP[PROD[x]['gamme']] for x in LOUABLES])[0]
        lo = max(GEN[PROD[p]['gen']], D(2022,9,1)) if pays == 'FR' else D(2025,12,1)
        hi = D(2025,6,30) if pays == 'FR' else D(2026,3,31)
        ms = wdate(lo, hi, False)
        ref = None
        if pays == 'FR' and random.random() < 0.10:
            ref = wdate(max(addd(ms, 200), D(2025,3,1)), D(2026,9,30), False)
        ce += 1
        EX[ce] = dict(p=p, ag=ag, pays=pays, ms=ms, ref=ref, busy=[])
        ins('EXEMPLAIRE', CodeEX=ce, NumSerieEX=f"MP-{pays}-{ms.year}-{ce:05d}", DateMiseServiceEX=ms, DateReformeEX=ref, CodeAG=ag, CodeP=p)

# ------------------------------------------------------------------ REDUCTION (gamme x profil x année)
for g, cg in GCODE.items():
    sec = [s for s,gs in GAM.items() if g in gs][0]
    for c,_ in CATS:
        base = {'TC':0.05,'TM':0.10,'TL':0.18,'TI':0.15}[c[:2]] + (0.05 if sec in ('Vélos','Micromobilité') else 0)
        for an in (2024, 2025, 2026):
            loc = round(min(0.6, base + random.choice([0, 0.01, 0.02]) + (an - 2024) * 0.01), 3)
            ach = round(min(0.5, base * 0.8 + random.choice([0, 0.01])), 3)
            ins('REDUCTION', CodeCAT=c, CodeG=cg, Annee=an, PctReduc_Loc=loc, PctReduc_Achat=ach)

ins('PARTENAIRE', CodePartenaire='ALLTRICKS', NomPartenaire='Alltricks', TauxRemise=0.2)

# ------------------------------------------------------------------ SOCIETE, SERVICE
def luhn_ok(s):
    t = 0
    for i, ch in enumerate(reversed(s)):
        d = int(ch) * (2 if i % 2 else 1); t += d - 9 if d > 9 else d
    return t % 10 == 0
def luhn_complete(prefix):
    for c in '0123456789':
        if luhn_ok(prefix + c): return prefix + c
SOC = [  # nom, pays, commune, CJ, type, NAF, nb employés
 ('Occitech Solutions','FR','31555','5710','PME','62.01Z',28),('AéroSud Ingénierie','FR','31069','5599','GE','30.30Z',45),
 ('Lumière Conseil','FR','69123','5710','PME','70.22Z',22),('Rhône Hyper','FR','69266','5599','GE','47.11F',38),
 ('Banque Seine Patrimoine','FR','75056','5599','GE','64.19Z',40),('DataCap Paris','FR','92012','5710','ETI','62.02A',30),
 ('Clinique des Chartrons','FR','33063','5499','ETI','86.10Z',26),('Université Atlantique','FR','44109','7383','GE','85.42Z',24),
 ('Phocée Mobilités','FR','13055','5710','ETI','49.39A',20),('Nordlog Conseil','FR','59350','5499','PME','70.22Z',14),
 ('Breizh Numérique','FR','35238','5710','PME','62.01Z',12),('Alsace Santé Services','FR','67482','5499','MICRO','86.10Z',6),
 ('Spreeware GmbH','DE','11000000','D101',  'PME',None,18),('Isar Logistik GmbH & Co. KG','DE','09162000','D203','ETI',None,16),
 ('Garchinger Forschungs AG','DE','09184119','D103','GE',None,14),('Domstadt Consulting UG','DE','05315000','D102','MICRO',None,6),
 ('Mainfinanz AG','DE','06412000','D103','GE',None,14),('Neckar Engineering GmbH','DE','08111000','D101','PME',None,12),
 ('Rheinmedia OHG','DE','05111000','D202','PME',None,8),('Elbe Hafen Service KG','DE','02000000','D201','PME',None,10)]
SERV_FR = ['Direction','Ressources humaines','Informatique','Comptabilité','Commercial','Production','Logistique']
SERV_DE = ['Geschäftsführung','Personal','IT','Buchhaltung','Vertrieb','Produktion','Logistik']
TYPE_SERV = ['DIR','RH','INFO','COMPTA','COM','PROD','LOG']
SOCS = []; cse = 0; SERV = {}
for nm,pays,zg,cj,ty,naf,ne in SOC:
    if pays == 'FR':
        siren = luhn_complete(f"{random.randint(30000000, 99999999)}")
        code = siren; zgc = zg
    else:
        code = 'DE' + f"{random.randint(100000000, 999999999)}"; zgc = 'DE' + zg
    soc = dict(code=code, nom=nm, pays=pays, ne=ne, zg=zg, services=[])
    if pays == 'FR': soc['siret'] = luhn_complete(code + f"{random.randint(1, 99):04d}")
    else: soc['siret'] = f"{random.randint(10000000, 99999999)}"     # Betriebsnummer (8 chiffres)
    SOCS.append(soc)
    ins('SOCIETE', CodeSOC=code, NomSOC=nm, CodeTy=ty, CodeZG=zgc, CodeCJ=cj, CodeDO=naf)
    nbs = 3 if ne < 10 else (4 if ne < 20 else 6)
    idx = [0, 1, 2] + random.sample(range(3, 7), nbs - 3)
    for j in sorted(idx):
        cse += 1
        nom = (SERV_FR if pays == 'FR' else SERV_DE)[j]
        SERV[cse] = dict(soc=soc, nom=nom, type=TYPE_SERV[j])
        soc['services'].append(cse)
        ins('SERVICE', CodeSE=cse, NomSE=nom, CodeSOC=code)

# ------------------------------------------------------------------ EMPLOYE, ETRE_AFFECTE, SALARIE_RH, EXERCER
PRE_FR = ['Marie','Lucas','Léa','Hugo','Chloé','Louis','Emma','Gabriel','Camille','Arthur','Manon','Jules','Sarah','Nathan',
          'Inès','Thomas','Julie','Paul','Clara','Adam','Zoé','Mathis','Lina','Théo','Alice','Raphaël','Nora','Yanis','Anaïs','Karim']
NOM_FR = ['Martin','Bernard','Dubois','Thomas','Robert','Richard','Petit','Durand','Leroy','Moreau','Simon','Laurent','Lefebvre',
          'Michel','Garcia','David','Bertrand','Roux','Vincent','Fournier','Morel','Girard','André','Mercier','Dupont','Lambert',
          'Bonnet','François','Martinez','Benali','Nguyen','Diallo','Rousseau','Blanc','Guerin']
PRE_DE = ['Lukas','Anna','Leon','Mia','Finn','Emilia','Paul','Hannah','Jonas','Lea','Felix','Sophie','Elias','Marie','Noah',
          'Lena','Ben','Laura','Maximilian','Johanna','Tim','Katharina','Jan','Clara']
NOM_DE = ['Müller','Schmidt','Schneider','Fischer','Weber','Meyer','Wagner','Becker','Schulz','Hoffmann','Koch','Richter',
          'Klein','Wolf','Schröder','Neumann','Schwarz','Zimmermann','Braun','Krüger','Hartmann','Lange','Yilmaz','Kaya']
PLZ = {'31555':'31','31069':'31','69123':'69','69266':'69','75056':'75','92012':'92','33063':'33','13055':'13','59350':'59',
       '44109':'44','35238':'35','67482':'67','11000000':'10','09162000':'80','09184119':'85','05315000':'50','06412000':'60',
       '08111000':'70','05111000':'40','02000000':'20'}
LIB_VAR = {'INFO':['Informatique','DSI','Service informatique','INFORMATIQUE','Info'],'RH':['Ressources humaines','RH','DRH','Service RH'],
           'DIR':['Direction','Direction générale','DG'],'COMPTA':['Comptabilité','Compta','Service comptable'],
           'COM':['Commercial','Service commercial','Ventes'],'PROD':['Production','Atelier','Prod.'],'LOG':['Logistique','Entrepôt','Log.']}
LIB_VAR_DE = {'INFO':['IT','EDV','IT-Abteilung'],'RH':['Personal','HR','Personalabteilung'],'DIR':['Geschäftsführung','GF'],
              'COMPTA':['Buchhaltung','Rechnungswesen'],'COM':['Vertrieb','Verkauf'],'PROD':['Produktion','Fertigung'],'LOG':['Logistik','Lager']}
METIER = {'INFO':['M1805','M1806'],'RH':['M1503'],'DIR':['M1302','M1607'],'COMPTA':['M1203'],'COM':['M1705'],
          'PROD':['H1206','D1507','J1506','K2108'],'LOG':['N1103']}
EMP = {}; ce = 0; matr = collections.Counter()
for soc in SOCS:
    for _ in range(soc['ne']):
        ce += 1
        fr = soc['pays'] == 'FR'
        nom = random.choice(NOM_FR if fr else NOM_DE); pre = random.choice(PRE_FR if fr else PRE_DE)
        cat = random.choices(list(CAT_W), list(CAT_W.values()))[0]
        if fr: insc = wdate(D(2022,1,10), D(2024,10,1), False) if random.random() < 0.75 else wdate(START, D(2026,8,31), False)
        else:  insc = wdate(DE_START, D(2026,8,31), False)
        svs = soc['services']
        se1 = random.choice(svs)
        aff = [(insc, se1)]
        if random.random() < 0.12 and len(svs) > 1 and days(addd(insc, 120), D(2026,9,15)) > 0:
            ch = wdate(max(addd(insc, 120), START), D(2026,9,15), False)
            aff.append((ch, random.choice([s for s in svs if s != se1])))
        cur = aff[-1][1]
        heavy = random.random() < 0.25
        EMP[ce] = dict(soc=soc, pays=soc['pays'], insc=insc, cat=cat, aff=aff, w=(6 if heavy else 1) * (0.3 if random.random() < 0.3 else 1))
        ins('EMPLOYE', CodeE=ce, NomE=nom, PrenomE=pre, CodeSE=cur, CodeCAT=cat)
        for i,(deb, se) in enumerate(aff):
            fin = addd(aff[i+1][0], -1) if i + 1 < len(aff) else None
            ins('ETRE_AFFECTE', CodeE=ce, DateDebutAffect=deb, DateFinAffect=fin, CodeSE=se)
        # fiche RH (RG19 : environ 12 % des employés n'ont pas encore de fiche rapprochée)
        if random.random() < 0.88:
            nai = wdate(D(1964,1,1), min(D(2003,12,31), addd(insc, -365*20 - 5)), False)
            ent = wdate(max(addd(nai, 365*20), D(2008,1,1)), min(insc, LAST), False)
            mat = None
            while mat is None or (soc['siret'], mat) in matr:
                mat = ('M' if fr else 'P') + f"{random.randint(1, 99999):05d}"
            matr[(soc['siret'], mat)] += 1
            typ = SERV[aff[0][1]]['type']
            lib = random.choice((LIB_VAR if fr else LIB_VAR_DE)[typ])
            cp = PLZ[soc['zg']] + f"{random.randint(0, 999):03d}" if PLZ[soc['zg']] not in ('85',) else '85748'
            ins('SALARIE_RH', MatriculeSAL=mat, NumEtab=soc['siret'], DateNaissSAL=nai, DateEntreeSAL=ent,
                CPResidenceSAL=cp, LibelleServiceSAL=lib, CodeE=ce)
            if fr:   # métiers ROME : seulement en France (RG9)
                mets = [(ent, random.choice(APP[random.choice(METIER[typ])]))]
                if random.random() < 0.25 and days(addd(ent, 365), D(2026,9,1)) > 0:
                    d2 = wdate(addd(ent, 365), D(2026,9,1), False)
                    typ2 = SERV[aff[-1][1]]['type']
                    mets.append((d2, random.choice(APP[random.choice(METIER[typ2])])))
                for i,(deb, app) in enumerate(mets):
                    fin = addd(mets[i+1][0], -1) if i + 1 < len(mets) else None
                    ins('EXERCER', MatriculeSAL=mat, NumEtab=soc['siret'], DateDebutMetier=deb, DateFinMetier=fin,
                        TypeContrat=random.choices(['CDI','CDD','ALTERNANCE','STAGE','INTERIM'],[80,10,5,2,3])[0], CodeAPP=app)

def emp_actif(pays, d):
    l = [e for e,v in EMP.items() if v['pays'] == pays and v['insc'] <= d]
    return random.choices(l, [EMP[e]['w'] for e in l])[0] if l else None

# ------------------------------------------------------------------ LOUER (sans chevauchement d'un même exemplaire)
DUREES = [1]*30 + [2]*20 + [3]*12 + list(range(4, 8))*5 + list(range(8, 15))*1 + [21, 30]*2
pk = set(); nloc = 0; tries = 0
by_pays = {'FR': [x for x in EX if EX[x]['pays'] == 'FR'], 'DE': [x for x in EX if EX[x]['pays'] == 'DE']}
TARGET = {'FR': 4400, 'DE': 700}
for pays, tgt in TARGET.items():
    lo = START if pays == 'FR' else DE_START
    got = 0
    while got < tgt and tries < 400000:
        tries += 1
        d = wdate(lo, LAST)
        e = emp_actif(pays, d)
        if e is None: continue
        x = random.choices(by_pays[pays], [POP[PROD[EX[i]['p']]['gamme']] for i in by_pays[pays]])[0]
        ex = EX[x]; du = random.choice(DUREES)
        fin = addd(d, du)
        if d < ex['ms'] or fin > LAST or (ex['ref'] and fin > ex['ref']): continue
        if any(not (fin <= a or d >= b) for a, b in ex['busy']): continue
        if (e, x, d) in pk: continue
        pk.add((e, x, d)); ex['busy'].append((d, fin)); got += 1
        ins('LOUER', CodeE=e, CodeEX=x, DateL=d, Duree_Loc=du)

# ------------------------------------------------------------------ ACHAT
ACH_W = {'Vélos':1,'Equipement du cycliste':9,'Micromobilité':3,'Services et entretien':5}
pk = set(); got = 0
while got < 2200:
    pays = 'FR' if random.random() < 0.85 else 'DE'
    d = wdate(START if pays == 'FR' else DE_START, LAST)
    e = emp_actif(pays, d)
    if e is None: continue
    p = random.choices(list(PROD), [ACH_W[PROD[i]['sec']] for i in PROD])[0]
    if GEN[PROD[p]['gen']] > d or (e, p, d) in pk: continue
    pk.add((e, p, d)); got += 1
    q = 1 if PROD[p]['sec'] in ('Vélos', 'Services et entretien') else random.choices([1, 2, 3], [75, 20, 5])[0]
    ins('ACHAT', CodeE=e, CodeP=p, DateA=d, Qte=q)

# ------------------------------------------------------------------ RESERVER (DateLPrev < date du jour)
pk = set(); got = 0
while got < 1000:
    pays = 'FR' if random.random() < 0.85 else 'DE'
    dr = wdate(START if pays == 'FR' else DE_START, addd(LAST, -1))
    e = emp_actif(pays, dr)
    if e is None: continue
    dl = addd(dr, random.choice([0, 1, 2, 3, 5, 7, 7, 10, 14, 21, 30]))
    if dl > LAST: continue
    p = random.choices(LOUABLES, [POP[PROD[x]['gamme']] for x in LOUABLES])[0]
    if (e, p, dl) in pk: continue
    pk.add((e, p, dl)); got += 1
    ins('RESERVER', CodeE=e, CodeP=p, DateLPrev=dl, Nb_Ex_Prev=random.choices([1, 2, 3], [85, 12, 3])[0], DateResa=dr,
        Duree_Prev=random.choice([1, 1, 2, 2, 3, 5, 7, 14]))

# ------------------------------------------------------------------ ACHETER_PARTENAIRE (fait sans mesure)
pk = set(); got = 0
while got < 320:
    pays = 'FR' if random.random() < 0.8 else 'DE'
    d = wdate(PART_START, LAST)
    e = emp_actif(pays, d)
    if e is None or (e, d) in pk: continue
    pk.add((e, d)); got += 1
    ins('ACHETER_PARTENAIRE', CodeE=e, DateA=d, CodePartenaire='ALLTRICKS')

# ================================================================== CONTRÔLES (règles des scripts 01 et 02)
R = rows; err = []
def chk(c, m):
    if not c: err.append(m)
PKS = {'PAYS':['CodePays'],'ZONE_GEO':['CodeZG'],'DOMAINE':['CodeDO'],'CATEGORIE_JURIDIQUE':['CodeCJ'],'TYPE_SOCIETE':['CodeTy'],
       'CATEGORIE':['CodeCAT'],'GRAND_DOMAINE':['CodeGD'],'DOMAINE_PRO':['CodeDP'],'FICHE_METIER':['CodeROME'],'APPELLATION':['CodeAPP'],
       'GAMME':['CodeG'],'FABRICANT':['CodeFAB'],'GENERATION':['CodeGEN'],'PRODUIT':['CodeP'],'TARIFER':['CodePays','CodeP','DateDebutTarif'],
       'AGENCE':['CodeAG'],'EXEMPLAIRE':['CodeEX'],'REDUCTION':['CodeCAT','CodeG','Annee'],'PARTENAIRE':['CodePartenaire'],
       'SOCIETE':['CodeSOC'],'SERVICE':['CodeSE'],'EMPLOYE':['CodeE'],'ETRE_AFFECTE':['CodeE','DateDebutAffect'],
       'SALARIE_RH':['MatriculeSAL','NumEtab'],'EXERCER':['MatriculeSAL','NumEtab','DateDebutMetier'],
       'ACHAT':['CodeE','CodeP','DateA'],'RESERVER':['CodeE','CodeP','DateLPrev'],'LOUER':['CodeE','CodeEX','DateL'],
       'ACHETER_PARTENAIRE':['CodeE','DateA','CodePartenaire']}
for t, k in PKS.items():
    keys = [tuple(r[c] for c in k) for r in R[t]]
    chk(len(keys) == len(set(keys)), f"PK en double dans {t}")
    chk(all(all(v is not None for v in kk) for kk in keys), f"PK nulle dans {t}")
FKS = [('ZONE_GEO','CodeZG_zone_englobante','ZONE_GEO','CodeZG'),('ZONE_GEO','CodePays','PAYS','CodePays'),
       ('DOMAINE','CodeDO_Sup','DOMAINE','CodeDO'),('CATEGORIE_JURIDIQUE','CodeCJ_niveau_superieur','CATEGORIE_JURIDIQUE','CodeCJ'),
       ('DOMAINE_PRO','CodeGD','GRAND_DOMAINE','CodeGD'),('FICHE_METIER','CodeDP','DOMAINE_PRO','CodeDP'),
       ('APPELLATION','CodeROME','FICHE_METIER','CodeROME'),('GENERATION','CodeFAB','FABRICANT','CodeFAB'),
       ('AGENCE','CodePays','PAYS','CodePays'),('SOCIETE','CodeTy','TYPE_SOCIETE','CodeTy'),('SOCIETE','CodeZG','ZONE_GEO','CodeZG'),
       ('SOCIETE','CodeCJ','CATEGORIE_JURIDIQUE','CodeCJ'),('SOCIETE','CodeDO','DOMAINE','CodeDO'),('SERVICE','CodeSOC','SOCIETE','CodeSOC'),
       ('EMPLOYE','CodeSE','SERVICE','CodeSE'),('EMPLOYE','CodeCAT','CATEGORIE','CodeCAT'),('ETRE_AFFECTE','CodeE','EMPLOYE','CodeE'),
       ('ETRE_AFFECTE','CodeSE','SERVICE','CodeSE'),('PRODUIT','CodeGEN','GENERATION','CodeGEN'),('PRODUIT','CodeG','GAMME','CodeG'),
       ('EXEMPLAIRE','CodeAG','AGENCE','CodeAG'),('EXEMPLAIRE','CodeP','PRODUIT','CodeP'),('SALARIE_RH','CodeE','EMPLOYE','CodeE'),
       ('EXERCER','CodeAPP','APPELLATION','CodeAPP'),('REDUCTION','CodeCAT','CATEGORIE','CodeCAT'),('REDUCTION','CodeG','GAMME','CodeG'),
       ('TARIFER','CodePays','PAYS','CodePays'),('TARIFER','CodeP','PRODUIT','CodeP'),('ACHAT','CodeE','EMPLOYE','CodeE'),
       ('ACHAT','CodeP','PRODUIT','CodeP'),('RESERVER','CodeE','EMPLOYE','CodeE'),('RESERVER','CodeP','PRODUIT','CodeP'),
       ('LOUER','CodeE','EMPLOYE','CodeE'),('LOUER','CodeEX','EXEMPLAIRE','CodeEX'),('ACHETER_PARTENAIRE','CodeE','EMPLOYE','CodeE'),
       ('ACHETER_PARTENAIRE','CodePartenaire','PARTENAIRE','CodePartenaire')]
for t, c, rt, rc in FKS:
    ref = {r[rc] for r in R[rt]}
    chk(all(r[c] is None or r[c] in ref for r in R[t]), f"FK {t}.{c}")
sal = {(r['MatriculeSAL'], r['NumEtab']) for r in R['SALARIE_RH']}
chk(all((r['MatriculeSAL'], r['NumEtab']) in sal for r in R['EXERCER']), "FK EXERCER -> SALARIE_RH")
chk(len({r['CodeE'] for r in R['SALARIE_RH']}) == len(R['SALARIE_RH']), "UNIQUE SALARIE_RH.CodeE")
chk(len({r['NumSerieEX'] for r in R['EXEMPLAIRE']}) == len(R['EXEMPLAIRE']), "UNIQUE NumSerieEX")
# CHECK
zg = {r['CodeZG']: r for r in R['ZONE_GEO']}
OK_PAR = {('COMMUNE','DEPARTEMENT'),('DEPARTEMENT','REGION'),('GEMEINDE','KREIS'),('BEZIRK','LAND'),('KREIS','DISTRICT'),('KREIS','LAND'),('DISTRICT','LAND')}
for r in R['ZONE_GEO']:
    chk(len(r['CodeZG']) <= 10, f"CodeZG trop long {r['CodeZG']}")
    chk((r['NiveauZG'] in ('REGION','LAND')) == (r['CodeZG_zone_englobante'] is None), f"ck_zg_sommet {r['CodeZG']}")
    if r['CodeZG_zone_englobante']:
        p = zg[r['CodeZG_zone_englobante']]
        chk((r['NiveauZG'], p['NiveauZG']) in OK_PAR and p['CodePays'] == r['CodePays'], f"trg_zg_coherence {r['CodeZG']}")
for r in R['DOMAINE']:
    c, s = r['CodeDO'], r['CodeDO_Sup']
    chk(re.fullmatch(r'[0-9]{2}(\.[0-9]([0-9][A-Z]?)?)?', c), f"ck_do_masque {c}")
    chk((len(c) == 2 and s is None) or (len(c) > 2 and s and len(s) < len(c) and c.startswith(s)), f"ck_do_super {c}")
for r in R['CATEGORIE_JURIDIQUE']:
    c, s, n = r['CodeCJ'], r['CodeCJ_niveau_superieur'], r['NiveauCJ']
    chk(len(c) == {1:1, 2:2, 3:4}[n], f"ck_cj_longueur {c}")
    chk((n == 1 and s is None) or (n > 1 and s and c.startswith(s)), f"ck_cj_sup {c}")
for r in R['CATEGORIE']:
    chk(re.fullmatch(r'[A-Z]{2}-[0-9]{2}', r['CodeCAT']) and SC[r['CodeCAT'][:2]] == r['SuperCAT'], "ck_cat")
for r in R['SOCIETE']: chk(re.fullmatch(r'[0-9]{9}|DE[0-9]{9}', r['CodeSOC']), f"ck_soc_code {r['CodeSOC']}")
for r in R['SALARIE_RH']:
    chk(re.fullmatch(r'[0-9]{14}|[0-9]{8}', r['NumEtab']), "ck_sal_numetab")
    chk(re.fullmatch(r'[0-9]{5}', r['CPResidenceSAL']), "ck_sal_cp")
    chk(r['DateEntreeSAL'] > r['DateNaissSAL'], "ck_sal_dates")
for r in R['EXERCER']:
    chk(r['DateFinMetier'] is None or r['DateFinMetier'] > r['DateDebutMetier'], "ck_exr_dates")
    chk(re.fullmatch(r'[0-9]{14}', r['NumEtab']), "ck_exr_france")
for r in R['ETRE_AFFECTE']: chk(r['DateFinAffect'] is None or r['DateFinAffect'] > r['DateDebutAffect'], "ck_aff_dates")
for r in R['GENERATION']: chk(r['DateArretGEN'] is None or r['DateArretGEN'] > r['DateSortieGEN'], "ck_gen_dates")
for r in R['EXEMPLAIRE']: chk(r['DateReformeEX'] is None or r['DateReformeEX'] > r['DateMiseServiceEX'], "ck_ex_dates")
for r in R['REDUCTION']: chk(0 < r['PctReduc_Loc'] <= 1 and 0 < r['PctReduc_Achat'] <= 1, "ck_red")
for r in R['TARIFER']:
    chk(r['DateFinTarif'] is None or r['DateFinTarif'] > r['DateDebutTarif'], "ck_tar_dates")
    chk(r['Prix_vente'] > 0 and (r['Prix_loc_jour'] is None or (r['Prix_loc_jour'] > 0 and r['Prix_vente'] > r['Prix_loc_jour'])), "ck_tar_vente")
    chk((r['CodePays'], r['ModePrix']) in (('FR','TTC'), ('DE','HT')), "ck_tar_pays_mode")
for r in R['ACHAT']: chk(r['Qte'] > 0 and r['DateA'] < TODAY, "achat")
for r in R['RESERVER']: chk(r['DateLPrev'] < TODAY and r['DateResa'] <= r['DateLPrev'] and r['Nb_Ex_Prev'] > 0 and r['Duree_Prev'] > 0, "reserver")
exd = {r['CodeEX']: r for r in R['EXEMPLAIRE']}
for r in R['LOUER']:
    x = exd[r['CodeEX']]
    chk(r['DateL'] < TODAY and r['Duree_Loc'] > 0 and r['DateL'] >= x['DateMiseServiceEX'] and
        (x['DateReformeEX'] is None or addd(r['DateL'], r['Duree_Loc']) <= x['DateReformeEX']), "trg_louer_controle")
for r in R['ACHETER_PARTENAIRE']: chk(r['DateA'] < TODAY, "achat partenaire")
# cohérences métier
cur = {}
for r in R['ETRE_AFFECTE']:
    if r['DateFinAffect'] is None: cur[r['CodeE']] = r['CodeSE']
chk(all(cur[r['CodeE']] == r['CodeSE'] for r in R['EMPLOYE']), "EMPLOYE.CodeSE = affectation en cours")
socserv = {r['CodeSE']: r['CodeSOC'] for r in R['SERVICE']}
empsoc = {r['CodeE']: socserv[r['CodeSE']] for r in R['EMPLOYE']}
chk(all(r['NumEtab'][:9] == empsoc[r['CodeE']] for r in R['SALARIE_RH'] if len(r['NumEtab']) == 14), "SIRET = SIREN de la société")
for (pays, p), lst in TARIF.items():
    s = sorted(lst)
    for a, b in zip(s, s[1:]): chk(a[1] is not None and a[1] < b[0], f"tarifs qui se chevauchent {pays} {p}")
print("ERREURS :", err[:10] if err else "aucune")

# ================================================================== ÉCRITURE DU SCRIPT SQL
def lit(v):
    if v is None: return 'NULL'
    if isinstance(v, D): return f"TO_DATE('{v.isoformat()}','YYYY-MM-DD')"
    if isinstance(v, (int, float)): return repr(v)
    return "'" + str(v).replace("'", "''") + "'"
ORDER = ['PAYS','ZONE_GEO','DOMAINE','CATEGORIE_JURIDIQUE','TYPE_SOCIETE','CATEGORIE','GRAND_DOMAINE','DOMAINE_PRO','FICHE_METIER',
         'APPELLATION','FABRICANT','GENERATION','AGENCE','GAMME','PARTENAIRE','SOCIETE','SERVICE','EMPLOYE','ETRE_AFFECTE','PRODUIT',
         'EXEMPLAIRE','SALARIE_RH','EXERCER','REDUCTION','TARIFER','ACHAT','RESERVER','LOUER','ACHETER_PARTENAIRE']
out = ["-- MobiPass - Entrepôt de données : insertion des données (Oracle 11g)",
       "-- Tables de l'entrepôt (noms de la V1 conservés). Généré par gen_donnees.py (graine fixe) le " + TODAY.isoformat() + ". À lancer APRÈS 01_creation_ED.sql et 02_contraintes_ED.sql.",
       "-- Historique du " + START.isoformat() + " au " + LAST.isoformat() + " ; activité allemande et partenariat Alltricks à partir de janvier 2026.",
       "-- Codes d'appellation ROME illustratifs (6 chiffres) ; codes INSEE, NAF, ROME (fiches), AGS réels.",
       "SET DEFINE OFF", ""]
for t in ORDER:
    out.append(f"-- {t} : {len(R[t])} lignes")
    cols = list(R[t][0].keys())
    for i, r in enumerate(R[t], 1):
        out.append(f"INSERT INTO {t}({', '.join(cols)}) VALUES ({', '.join(lit(r[c]) for c in cols)});")
        if i % 500 == 0: out.append("COMMIT;")
    out.append("COMMIT;"); out.append("")
out.append("-- Vérification : nombre de lignes par table")
out.append("\nUNION ALL\n".join(f"SELECT '{t}' AS table_name, COUNT(*) AS nb FROM {t}" for t in ORDER) + ";")
CIBLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "03_insertion_ED.sql")   # à côté de ce script
open(CIBLE, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("écrit :", CIBLE)
for t in ORDER: print(f"{t:22s}{len(R[t]):6d}")
print("total", sum(len(R[t]) for t in ORDER))

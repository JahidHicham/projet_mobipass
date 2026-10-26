# -*- coding: utf-8 -*-
"""MobiPass - Projet 2 : génération des données du cube « Locations » (CSV pour BULK INSERT)

Reprend telles quelles les données du projet 1 (sql/ed/03_insertion_ED.sql) et les complète jusqu'aux
volumes minimaux du sujet du projet 2 : au moins 40 sociétés sur 5 régions, 3 000 employés, 60 produits
sur 3 secteurs, 400 exemplaires et 60 000 locations sur 3 années complètes (2023 à 2025 ; 2026 s'arrête
au 13/10/2026 comme au projet 1). Graine fixe : le script produit toujours les mêmes fichiers.

Sorties :
  csv/          les 5 fichiers sources chargés par 1_entrepot_sql/03_chargement_dw.sql (employe, produit,
                exemplaire, location, reservation). Comme de vraies sources, ils contiennent environ 2 % de
                données manquantes ou erronées, que le chargement doit traiter : liste et nombre exact dans
                referentiels/anomalies_injectees.csv ;
  referentiels/ les référentiels à relire par le groupe (sociétés, produits, agences, tarifs, réductions,
                profils de trajet), avec leur origine (projet 1 ou ajout du projet 2).

Lois de probabilité (réglages ci-dessous, à valider par le groupe) et phénomènes injectés :
  P1 saisonnalité et saturation : demande pondérée par mois (pic d'avril à juin et en septembre, creux en
     hiver), par jour (week-end faible) et x1,7 pendant la semaine européenne de la mobilité (16-22 sept.) ;
     parc volontairement sous-dimensionné à Paris (vélos électriques urbains, vélos cargo) et à Lyon
     (vélos électriques urbains) : une demande sans exemplaire libre devient une réservation non honorée ;
  P2 concentration : les VTT électriques sont 4 fois plus demandés en Auvergne-Rhône-Alpes ;
  P3 profil de trajet : trajet long = locations longues (environ 11 jours) mais moins fréquentes ;
     intermodal = locations courtes (environ 2 jours), 1,5 fois plus fréquentes, surtout des vélos pliants
     et des trottinettes ;
  P4 évolution de sociétés clientes : Seine Digital Factory (arrivée en mars 2024, recrutements jusqu'à
     fin 2025) progresse fortement ; Provence Banque Régionale chute de 80 % à partir d'avril 2025
     (flotte interne de vélos de fonction) ;
  P5 France / Allemagne : l'Allemagne démarre en janvier 2026 avec une montée en charge mois par mois,
     des locations 1,5 fois plus longues et davantage de vélos cargo et de trottinettes électriques.
"""
import bisect, collections, csv, datetime as dt, itertools, math, random, re
from pathlib import Path

random.seed(2027)
D = dt.date
ICI = Path(__file__).resolve().parent
SQL_P1 = ICI.parents[1] / 'sql' / 'ed' / '03_insertion_ED.sql'

TODAY = D(2026, 10, 14)          # date de génération du projet 1 : toutes les dates d'activité sont avant
LAST = TODAY - dt.timedelta(1)
START = D(2023, 1, 1)            # début de l'historique : 3 années complètes (2023, 2024, 2025)
DE_START = D(2026, 1, 5)         # l'offre est étendue à l'Allemagne en 2026 (sujet initial)
DOMAINE_DE = True                # True : les sociétés allemandes ont un domaine (équivalent NACE de leur code WZ)

# ================================================================== lois de probabilité (réglages)
RATE = {'FR': 0.0105, 'DE': 0.030}     # demandes par jour et par unité de poids d'employé (calibre les volumes)
YEAR_F = {2023: 1.0, 2024: 1.05, 2025: 1.1, 2026: 1.15}                   # croissance de l'usage
MONTH_W = {1: .5, 2: .55, 3: .85, 4: 1.25, 5: 1.6, 6: 1.7, 7: 1.4, 8: .9, 9: 1.45, 10: 1.0, 11: .6, 12: .45}
DOW_W = [1, 1, 1, 1, 1, .55, .3]                                          # lundi ... dimanche
MOBILITE = 1.7                                                            # semaine européenne de la mobilité
CAT_W = {'TC-01': 10, 'TC-02': 14, 'TC-03': 5, 'TM-01': 12, 'TM-02': 5, 'TM-03': 8, 'TM-04': 3, 'TL-01': 6,
         'TL-02': 3, 'TI-01': 7, 'TI-02': 9, 'TI-03': 2}                  # répartition des profils (projet 1)
CLS_ZONE = {'dense': {'TC': 1.4, 'TM': 1.0, 'TL': 0.5, 'TI': 1.4},       # ville dense : trajets courts, intermodal
            'peri': {'TC': 0.5, 'TM': 1.3, 'TL': 1.8, 'TI': 0.8}}        # périurbain : trajets moyens et longs
FREQ = {'TC': 1.0, 'TM': 1.0, 'TL': 0.7, 'TI': 1.5}                       # P3 : fréquence de location
DUR = {'TC': [1] * 40 + [2] * 28 + [3] * 16 + [4] * 8 + [5] * 5 + [7] * 3,   # P3 : durées en jours
       'TM': [1] * 30 + [2] * 20 + [3] * 12 + list(range(4, 8)) * 5 + list(range(8, 15)) + [21, 30] * 2,
       'TL': [3] * 8 + [5] * 14 + [7] * 24 + [10] * 16 + [14] * 20 + [21] * 12 + [30] * 6,
       'TI': [1] * 55 + [2] * 28 + [3] * 12 + [5] * 5}
DMOY = {c: sum(l) / len(l) for c, l in DUR.items()}
DUREE_DE = 1.5                                                            # P5
POP = {'Vélos électriques urbains': 10, 'VTT électriques': 4, 'Vélos cargo': 4, 'Vélos pliants': 4,
       'Vélos de route & gravel': 3, 'Vélos enfants': 2, 'Casques': 3, 'Sacoches & bagagerie': 2,
       'Sièges enfants & remorques': 2, 'Trottinettes électriques': 7, 'Trottinettes mécaniques': 2, 'Gyroroues': 1,
       'Hoverboards & gyropodes': 1, 'Skateboards électriques': 1, 'Scooters électriques': 2}   # popularité (projet 1)
GAMME_CLS = {'TC': {'Trottinettes électriques': 1.5, 'Trottinettes mécaniques': 1.5, 'Casques': 1.5,
                    'Scooters électriques': .5, 'Vélos de route & gravel': .4},
             'TM': {},
             'TL': {'Vélos électriques urbains': 1.3, 'VTT électriques': 1.5, 'Vélos de route & gravel': 2.5,
                    'Scooters électriques': 1.8, 'Vélos cargo': .5, 'Trottinettes électriques': .3,
                    'Trottinettes mécaniques': .2, 'Gyroroues': .3, 'Hoverboards & gyropodes': .2,
                    'Skateboards électriques': .3},
             'TI': {'Vélos pliants': 4, 'Trottinettes électriques': 2, 'Trottinettes mécaniques': 2, 'Vélos cargo': .3,
                    'VTT électriques': .3, 'Vélos de route & gravel': .5}}
GAMME_ARA = {'VTT électriques': 4.0}                                      # P2
GAMME_DE = {'Vélos cargo': 2.5, 'Trottinettes électriques': 1.8}          # P5
PARC = {'FR': 600, 'DE': 240}                                             # taille visée du parc par pays
CAP = {('AG-PAR', 'Vélos électriques urbains'): .55, ('AG-PAR', 'Vélos cargo'): .6,
       ('AG-LYO', 'Vélos électriques urbains'): .6}                       # P1 : parc sous-dimensionné
P_RESA = 0.35                                                             # part des locations réservées à l'avance
DELAIS = [0, 1, 1, 2, 3, 3, 5, 7, 7, 10, 14, 21]                          # jours entre réservation et location


def addd(d, n): return d + dt.timedelta(n)
def days(a, b): return (b - a).days
def rdate(a, b): return addd(a, random.randint(0, days(a, b)))


# ================================================================== 1. données du projet 1, gardées telles quelles
TOK = re.compile(r"TO_DATE\('(\d{4}-\d{2}-\d{2})','YYYY-MM-DD'\)|'((?:[^']|'')*)'|(NULL)|(-?\d+(?:\.\d+)?)")
R = collections.defaultdict(list)          # table -> liste de lignes (dict)
for ligne in SQL_P1.read_text(encoding='utf-8').splitlines():
    m = re.match(r"INSERT INTO (\w+)\(([^)]*)\) VALUES \((.*)\);$", ligne)
    if not m: continue
    cols, vals = [c.strip() for c in m.group(2).split(',')], []
    for t in TOK.finditer(m.group(3)):
        dte, s, nul, num = t.groups()
        if dte: vals.append(D.fromisoformat(dte))
        elif s is not None: vals.append(s.replace("''", "'"))
        elif nul: vals.append(None)
        else: vals.append(float(num) if '.' in num else int(num))
    assert len(vals) == len(cols), ligne
    R[m.group(1)].append(dict(zip(cols, vals)))
P1_LOUER = {(r['CodeE'], r['CodeEX'], r['DateL'], r['Duree_Loc']) for r in R['LOUER']}
P1_NB = {t: len(R[t]) for t in ('SOCIETE', 'EMPLOYE', 'PRODUIT', 'EXEMPLAIRE', 'LOUER', 'RESERVER')}


def ins(t, **kv):
    R[t].append(kv)
    return kv


ZG = {r['CodeZG']: r for r in R['ZONE_GEO']}
def zone(code, nom, niveau, parent, pays):
    if code not in ZG:
        ZG[code] = ins('ZONE_GEO', CodeZG=code, NomZG=nom, NiveauZG=niveau, CodeZG_zone_englobante=parent, CodePays=pays)
def sommet(code):                          # région (FR) ou Land (DE)
    while ZG[code]['CodeZG_zone_englobante']: code = ZG[code]['CodeZG_zone_englobante']
    return code
DOM = {r['CodeDO']: r for r in R['DOMAINE']}
def domaine(code, nom, sup):
    if code not in DOM: DOM[code] = ins('DOMAINE', CodeDO=code, NomDO=nom, CodeDO_Sup=sup)


# ================================================================== 2. référentiels ajoutés (à relire par le groupe)
# Géographie des nouvelles sociétés : codes INSEE (communes, départements, régions) et AGS Destatis réels
for c, n in {'28': 'Normandie', '27': 'Bourgogne-Franche-Comté', '24': 'Centre-Val de Loire'}.items():
    zone('R' + c, n, 'REGION', None, 'FR')
for c, (n, r) in {'38': ('Isère', '84'), '34': ('Hérault', '76'), '06': ('Alpes-Maritimes', '93'),
                  '76': ('Seine-Maritime', '28'), '21': ("Côte-d'Or", '27'), '45': ('Loiret', '24'),
                  '63': ('Puy-de-Dôme', '84'), '93': ('Seine-Saint-Denis', '11'), '91': ('Essonne', '11'),
                  '29': ('Finistère', '53'), '57': ('Moselle', '44')}.items():
    zone('D' + c, n, 'DEPARTEMENT', 'R' + r, 'FR')
for c, (n, d) in {'38185': ('Grenoble', '38'), '34172': ('Montpellier', '34'), '06088': ('Nice', '06'),
                  '76540': ('Rouen', '76'), '21231': ('Dijon', '21'), '45234': ('Orléans', '45'),
                  '63113': ('Clermont-Ferrand', '63'), '92040': ('Issy-les-Moulineaux', '92'),
                  '92050': ('Nanterre', '92'), '93066': ('Saint-Denis', '93'), '91377': ('Massy', '91'),
                  '44162': ('Saint-Herblain', '44'), '33281': ('Mérignac', '33'), '31254': ('Labège', '31'),
                  '69081': ('Écully', '69'), '13001': ('Aix-en-Provence', '13'), '59009': ("Villeneuve-d'Ascq", '59'),
                  '29019': ('Brest', '29'), '57463': ('Metz', '57')}.items():
    zone(c, n, 'COMMUNE', 'D' + d, 'FR')
for c, (n, rb, ty) in {'14713': ('Leipzig, Stadt', None, 'Kreisfreie Stadt'), '14612': ('Dresden, Stadt', None, 'Kreisfreie Stadt'),
                       '05113': ('Essen, Stadt', '051', 'Kreisfreie Stadt'), '05913': ('Dortmund, Stadt', '059', 'Kreisfreie Stadt'),
                       '05314': ('Bonn, Stadt', '053', 'Kreisfreie Stadt'), '08222': ('Mannheim, Universitätsstadt', '082', 'Kreisfreie Stadt'),
                       '09761': ('Augsburg', '097', 'Kreisfreie Stadt'), '04011': ('Bremen, Stadt', None, 'Kreisfreie Stadt'),
                       '03241': ('Region Hannover', None, 'Landkreis')}.items():
    zone('DE' + c, n, ty.upper(), 'DE' + (rb or c[:2]), 'DE')
for c, n in {'14713000': 'Leipzig', '14612000': 'Dresden', '05113000': 'Essen', '05913000': 'Dortmund', '05314000': 'Bonn',
             '08222000': 'Mannheim', '09761000': 'Augsburg', '04011000': 'Bremen', '03241001': 'Hannover'}.items():
    zone('DE' + c, n, 'GEMEINDE', 'DE' + c[:5], 'DE')

# Domaines NAF rév. 2 ajoutés (4 niveaux) ; WZ 2008 et NAF rév. 2 sont identiques jusqu'à la classe (NACE rév. 2)
for c, n, s in [
        ('26', "Fabrication de produits informatiques, électroniques et optiques", None),
        ('26.1', "Fabrication de composants et cartes électroniques", '26'), ('26.11', "Fabrication de composants électroniques", '26.1'),
        ('26.11Z', "Fabrication de composants électroniques", '26.11'),
        ('35', "Production et distribution d'électricité, de gaz, de vapeur et d'air conditionné", None),
        ('35.1', "Production, transport et distribution d'électricité", '35'), ('35.11', "Production d'électricité", '35.1'),
        ('35.11Z', "Production d'électricité", '35.11'),
        ('65', "Assurance", None), ('65.1', "Assurance", '65'), ('65.12', "Autres assurances", '65.1'), ('65.12Z', "Autres assurances", '65.12'),
        ('10', "Industries alimentaires", None), ('10.5', "Fabrication de produits laitiers", '10'),
        ('10.51', "Exploitation de laiteries et fabrication de fromage", '10.5'), ('10.51C', "Fabrication de fromage", '10.51'),
        ('72', "Recherche-développement scientifique", None), ('72.1', "Recherche-développement en sciences physiques et naturelles", '72'),
        ('72.19', "Recherche-développement en autres sciences physiques et naturelles", '72.1'),
        ('72.19Z', "Recherche-développement en autres sciences physiques et naturelles", '72.19'),
        ('52', "Entreposage et services auxiliaires des transports", None), ('52.1', "Entreposage et stockage", '52'),
        ('52.10', "Entreposage et stockage", '52.1'), ('52.10B', "Entreposage et stockage non frigorifique", '52.10'),
        ('52.2', "Services auxiliaires des transports", '52'), ('52.24', "Manutention", '52.2'), ('52.24A', "Manutention portuaire", '52.24'),
        ('71', "Activités d'architecture et d'ingénierie ; activités de contrôle et analyses techniques", None),
        ('71.1', "Activités d'architecture et d'ingénierie", '71'), ('71.12', "Activités d'ingénierie", '71.1'),
        ('71.12B', "Ingénierie, études techniques", '71.12'),
        ('58', "Édition", None), ('58.2', "Édition de logiciels", '58'), ('58.29', "Édition d'autres logiciels", '58.2'),
        ('58.29C', "Édition de logiciels applicatifs", '58.29'),
        ('73', "Publicité et études de marché", None), ('73.1', "Publicité", '73'), ('73.11', "Activités des agences de publicité", '73.1'),
        ('73.11Z', "Activités des agences de publicité", '73.11'),
        ('46', "Commerce de gros, à l'exception des automobiles et des motocycles", None), ('46.9', "Commerce de gros non spécialisé", '46'),
        ('46.90', "Commerce de gros non spécialisé", '46.9'), ('46.90Z', "Commerce de gros non spécialisé", '46.90')]:
    domaine(c, n, s)

# Fabricants, générations et produits ajoutés (marques réelles, prix publics HT réalistes)
FAB = {r['CodeFAB']: r for r in R['FABRICANT']}
for c, n, p in [('FAB13', 'Gazelle', 'Pays-Bas'), ('FAB14', 'VanMoof', 'Pays-Bas'), ('FAB15', 'Peugeot Cycles', 'France'),
                ('FAB16', 'Kalkhoff', 'Allemagne'), ('FAB17', 'O2feel', 'France'), ('FAB18', 'Specialized', 'États-Unis'),
                ('FAB19', 'Haibike', 'Allemagne'), ('FAB20', 'Trek', 'États-Unis'), ('FAB21', 'Orbea', 'Espagne'),
                ('FAB22', 'Urban Arrow', 'Pays-Bas'), ('FAB23', 'Tern', 'Taïwan'), ('FAB24', 'Arcade Cycles', 'France'),
                ('FAB25', 'Canyon', 'Allemagne'), ('FAB26', 'Lapierre', 'France'), ('FAB27', 'Woom', 'Autriche'),
                ('FAB28', 'Lazer', 'Belgique'), ('FAB29', 'Uvex', 'Allemagne'), ('FAB30', 'Vaude', 'Allemagne'),
                ('FAB31', 'Croozer', 'Allemagne'), ('FAB32', 'Burley', 'États-Unis'), ('FAB33', 'Pure Electric', 'Royaume-Uni'),
                ('FAB34', 'Inokim', 'Israël'), ('FAB35', 'InMotion', 'Chine'), ('FAB36', 'Evolve Skateboards', 'Australie'),
                ('FAB37', 'NIU', 'Chine'), ('FAB38', 'Silence', 'Espagne')]:
    FAB[c] = ins('FABRICANT', CodeFAB=c, NomFAB=n, PaysFAB=p)
GENS = {r['CodeGEN']: r for r in R['GENERATION']}
for c, n, s, f in [('GEN15', 'Gazelle 2023', D(2022, 9, 1), 'FAB13'), ('GEN16', 'VanMoof S5', D(2023, 4, 1), 'FAB14'),
                   ('GEN17', 'Peugeot eLC 2022', D(2022, 3, 1), 'FAB15'), ('GEN18', 'Kalkhoff 2023', D(2022, 8, 1), 'FAB16'),
                   ('GEN19', 'O2feel 2022', D(2022, 2, 1), 'FAB17'), ('GEN20', 'Specialized 2023', D(2022, 7, 1), 'FAB18'),
                   ('GEN21', 'Haibike 2023', D(2022, 9, 1), 'FAB19'), ('GEN22', 'Trek 2023', D(2022, 8, 1), 'FAB20'),
                   ('GEN23', 'Orbea Wild', D(2022, 6, 1), 'FAB21'), ('GEN24', 'Urban Arrow Family', D(2021, 9, 1), 'FAB22'),
                   ('GEN25', 'Tern 2022', D(2022, 1, 1), 'FAB23'), ('GEN26', 'Arcade eCargo', D(2022, 4, 1), 'FAB24'),
                   ('GEN27', 'Canyon Grail 2023', D(2022, 10, 1), 'FAB25'), ('GEN28', 'Lapierre 2023', D(2022, 7, 1), 'FAB26'),
                   ('GEN29', 'Woom Original', D(2021, 1, 1), 'FAB27'), ('GEN30', 'Lazer KinetiCore', D(2022, 3, 1), 'FAB28'),
                   ('GEN31', 'Uvex City', D(2021, 5, 1), 'FAB29'), ('GEN32', 'Vaude Aqua', D(2020, 3, 1), 'FAB30'),
                   ('GEN33', 'Croozer Kid', D(2021, 4, 1), 'FAB31'), ('GEN34', 'Burley 2022', D(2022, 2, 1), 'FAB32'),
                   ('GEN35', 'Pure Advance', D(2023, 2, 1), 'FAB33'), ('GEN36', 'Inokim OXO', D(2021, 6, 1), 'FAB34'),
                   ('GEN37', 'InMotion V12', D(2021, 10, 1), 'FAB35'), ('GEN38', 'Evolve Stoke', D(2022, 5, 1), 'FAB36'),
                   ('GEN39', 'NIU MQi', D(2022, 3, 1), 'FAB37'), ('GEN40', 'Silence S01', D(2021, 3, 1), 'FAB38'),
                   ('GEN41', 'Decathlon 2023', D(2022, 9, 1), 'FAB04'), ('GEN42', 'Brompton Electric', D(2021, 3, 1), 'FAB05'),
                   ('GEN43', 'Riese & Müller Gen 5', D(2023, 3, 1), 'FAB02')]:
    GENS[c] = ins('GENERATION', CodeGEN=c, NomGEN=n, DateSortieGEN=s, DateArretGEN=None, CodeFAB=f)

GNOM = {r['CodeG']: r['NomG'] for r in R['GAMME']}
GCODE = {n: c for c, n in GNOM.items()}
SECT = {r['NomG']: r['SecteurG'] for r in R['GAMME']}
FR26 = {r['CodeP']: r for r in R['TARIFER'] if r['CodePays'] == 'FR' and r['DateFinTarif'] is None}
PROD = {}                                  # prix de base HT (loc/jour, vente) : ceux du projet 1 se déduisent du tarif FR 2026
for r in R['PRODUIT']:
    t = FR26[r['CodeP']]
    PROD[r['CodeP']] = dict(gamme=GNOM[r['CodeG']], gen=r['CodeGEN'], p1=True,
                            loc=t['Prix_loc_jour'] / 1.2 if t['Prix_loc_jour'] else None, vente=t['Prix_vente'] / 1.2)
cp = max(PROD)
for nm, mq, g, gn, pk, au, loc, ven in [  # nom, marque, gamme, génération, poids, autonomie, loc/jour HT, vente HT
        ('Gazelle Ultimate C380', 'Gazelle', 'Vélos électriques urbains', 'GEN15', 24.0, 120, 15.0, 3300),
        ('VanMoof S5', 'VanMoof', 'Vélos électriques urbains', 'GEN16', 23.0, 150, 13.0, 2900),
        ('Peugeot eLC01', 'Peugeot', 'Vélos électriques urbains', 'GEN17', 23.5, 90, 10.0, 1900),
        ('Kalkhoff Image 5.B', 'Kalkhoff', 'Vélos électriques urbains', 'GEN18', 26.0, 140, 13.0, 3000),
        ('O2feel Vog D8', 'O2feel', 'Vélos électriques urbains', 'GEN19', 24.5, 100, 9.0, 1650),
        ('Elops LD 500 E', 'Btwin', 'Vélos électriques urbains', 'GEN41', 25.5, 70, 5.0, 830),
        ('Specialized Turbo Vado 4.0', 'Specialized', 'Vélos électriques urbains', 'GEN20', 23.4, 130, 17.0, 3900),
        ('Haibike AllMtn 3', 'Haibike', 'VTT électriques', 'GEN21', 25.6, 110, 19.0, 4000),
        ('Rockrider E-ST 900', 'Rockrider', 'VTT électriques', 'GEN41', 22.0, 100, 12.0, 2100),
        ('Trek Powerfly 5', 'Trek', 'VTT électriques', 'GEN22', 24.0, 110, 20.0, 4300),
        ('Orbea Wild H30', 'Orbea', 'VTT électriques', 'GEN23', 24.3, 120, 21.0, 4600),
        ('Urban Arrow Family', 'Urban Arrow', 'Vélos cargo', 'GEN24', 50.0, 80, 26.0, 6200),
        ('Tern GSD S10', 'Tern', 'Vélos cargo', 'GEN25', 33.0, 110, 24.0, 5400),
        ('Arcade eCargo', 'Arcade', 'Vélos cargo', 'GEN26', 38.0, 80, 18.0, 4500),
        ('Riese & Müller Multicharger', 'Riese & Müller', 'Vélos cargo', 'GEN43', 30.0, 100, 22.0, 5600),
        ('Tern Vektron Q9', 'Tern', 'Vélos pliants', 'GEN25', 21.9, 80, 12.0, 3100),
        ('Brompton Electric C Line', 'Brompton', 'Vélos pliants', 'GEN42', 16.6, 70, 11.0, 3000),
        ('Tilt 900', 'Btwin', 'Vélos pliants', 'GEN41', 11.6, None, 5.0, 550),
        ('Canyon Grail 6', 'Canyon', 'Vélos de route & gravel', 'GEN27', 8.9, None, 11.0, 1800),
        ('Specialized Diverge E5', 'Specialized', 'Vélos de route & gravel', 'GEN20', 10.4, None, 8.0, 1250),
        ('Lapierre Crosshill 3.0', 'Lapierre', 'Vélos de route & gravel', 'GEN28', 10.2, None, 8.0, 1200),
        ('Riverside 500 24 pouces', 'Btwin', 'Vélos enfants', 'GEN41', 13.0, None, 3.0, 330),
        ('Woom 4', 'Woom', 'Vélos enfants', 'GEN29', 7.7, None, 4.0, 480),
        ('Lazer Codax KinetiCore', 'Lazer', 'Casques', 'GEN30', 0.33, None, 1.0, 40),
        ('Uvex City 4', 'Uvex', 'Casques', 'GEN31', 0.4, None, 1.5, 85),
        ('Vaude Aqua Back Plus', 'Vaude', 'Sacoches & bagagerie', 'GEN32', 1.6, None, 2.0, 110),
        ('Croozer Kid Plus for 2', 'Croozer', 'Sièges enfants & remorques', 'GEN33', 15.0, None, 6.5, 900),
        ("Burley D'Lite X", 'Burley', 'Sièges enfants & remorques', 'GEN34', 13.0, None, 6.5, 950),
        ('Ninebot Max G30', 'Segway-Ninebot', 'Trottinettes électriques', 'GEN11', 19.0, 65, 6.0, 650),
        ('Pure Advance+', 'Pure Electric', 'Trottinettes électriques', 'GEN35', 17.5, 50, 6.0, 700),
        ('Inokim OXO', 'Inokim', 'Trottinettes électriques', 'GEN36', 28.0, 100, 9.0, 1900),
        ('Xiaomi Electric Scooter 4 Ultra', 'Xiaomi', 'Trottinettes électriques', 'GEN08', 24.5, 70, 7.0, 830),
        ('Oxelo Town 7 XL', 'Oxelo', 'Trottinettes mécaniques', 'GEN41', 4.5, None, 1.5, 110),
        ('InMotion V12', 'InMotion', 'Gyroroues', 'GEN37', 25.0, 100, 9.0, 1650),
        ('Evolve Stoke', 'Evolve', 'Skateboards électriques', 'GEN38', 8.0, 30, 7.0, 1100),
        ('NIU MQi GT', 'NIU', 'Scooters électriques', 'GEN39', 80.0, 70, 14.0, 2500),
        ('Silence S01', 'Silence', 'Scooters électriques', 'GEN40', 113.0, 133, 20.0, 5800)]:
    cp += 1
    PROD[cp] = dict(gamme=g, gen=gn, p1=False, loc=loc, vente=ven)
    ins('PRODUIT', CodeP=cp, NomP=nm, MarqueP=mq, DescriptifP=f"{nm} ({g})", PoidsKg=pk, AutonomieKm=au, CodeGEN=gn, CodeG=GCODE[g])

# Tarifs (FR en TTC, DE en HT) : 2023 ajouté pour tous les produits, toutes les années pour les nouveaux
def tarif(pays, p, deb, fin, f):
    pr, tva = PROD[p], (1.2 if pays == 'FR' else 1.0)
    ins('TARIFER', CodePays=pays, CodeP=p, DateDebutTarif=deb, DateFinTarif=fin,
        Prix_loc_jour=round(pr['loc'] * f * tva, 2) if pr['loc'] else None, Prix_vente=round(pr['vente'] * f * tva, 2),
        ModePrix='TTC' if pays == 'FR' else 'HT')
for p, pr in PROD.items():
    tarif('FR', p, D(2023, 1, 1), D(2023, 12, 31), 0.92)
    if not pr['p1']:
        tarif('FR', p, D(2024, 1, 1), D(2024, 12, 31), 0.95); tarif('FR', p, D(2025, 1, 1), D(2025, 12, 31), 0.98)
        tarif('FR', p, D(2026, 1, 1), None, 1.0)
        if SECT[pr['gamme']] == 'Vélos':   # en Allemagne, hausse des vélos au 1er juillet 2026 (comme au projet 1)
            tarif('DE', p, D(2026, 1, 1), D(2026, 6, 30), 0.97); tarif('DE', p, D(2026, 7, 1), None, 1.02)
        else:
            tarif('DE', p, D(2026, 1, 1), None, 0.97)
TARIF = collections.defaultdict(list)
for r in R['TARIFER']: TARIF[(r['CodePays'], r['CodeP'])].append((r['DateDebutTarif'], r['DateFinTarif'], r['Prix_loc_jour']))
def prix_jour(pays, p, d):
    for deb, fin, loc in TARIF[(pays, p)]:
        if deb <= d and (fin is None or d <= fin): return loc

# Réductions 2023 (même règle qu'au projet 1 : selon la classe de trajet et le secteur, +1 point par an)
RED = {(r['CodeCAT'], r['CodeG'], r['Annee']): r['PctReduc_Loc'] for r in R['REDUCTION']}
for (c, g, an) in [k for k in RED if k[2] == 2024]:
    base = {'TC': .05, 'TM': .10, 'TL': .18, 'TI': .15}[c[:2]] + (.05 if SECT[GNOM[g]] in ('Vélos', 'Micromobilité') else 0)
    loc = round(min(.6, base + random.choice([0, .01, .02]) - .01), 3)
    ins('REDUCTION', CodeCAT=c, CodeG=g, Annee=2023, PctReduc_Loc=loc, PctReduc_Achat=round(min(.5, base * .8 + random.choice([0, .01])), 3))
    RED[(c, g, 2023)] = loc

# Agences ajoutées et agence de rattachement des employés (selon la région ou le Land de leur société)
AG = {r['CodeAG']: r for r in R['AGENCE']}
for c, n, v, p in [('AG-MRS', 'MobiPass Marseille Saint-Charles', 'Marseille', 'FR'), ('AG-LIL', 'MobiPass Lille Europe', 'Lille', 'FR'),
                   ('AG-NTE', 'MobiPass Nantes Gare Nord', 'Nantes', 'FR'), ('AG-STR', 'MobiPass Strasbourg Gare', 'Strasbourg', 'FR'),
                   ('AG-FRA', 'MobiPass Frankfurt Hauptbahnhof', 'Frankfurt am Main', 'DE'),
                   ('AG-LEJ', 'MobiPass Leipzig Hauptbahnhof', 'Leipzig', 'DE'), ('AG-STU', 'MobiPass Stuttgart Hauptbahnhof', 'Stuttgart', 'DE')]:
    AG[c] = ins('AGENCE', CodeAG=c, NomAG=n, VilleAG=v, CodePays=p)
P1_AGENCES = {r['CodeAG'] for r in R['AGENCE'][:8]}
HOME = {'R11': 'AG-PAR', 'R84': 'AG-LYO', 'R76': 'AG-TLS', 'R75': 'AG-BOR', 'R93': 'AG-MRS', 'R32': 'AG-LIL', 'R52': 'AG-NTE',
        'R53': 'AG-NTE', 'R44': 'AG-STR', 'R28': 'AG-PAR', 'R27': 'AG-LYO', 'R24': 'AG-PAR', 'DE11': 'AG-BER', 'DE09': 'AG-MUC',
        'DE05': 'AG-KOE', 'DE02': 'AG-HAM', 'DE06': 'AG-FRA', 'DE08': 'AG-STU', 'DE14': 'AG-LEJ', 'DE04': 'AG-HAM', 'DE03': 'AG-HAM'}

# Sociétés du projet 1 et sociétés ajoutées (noms fictifs ; localisation, domaine et taille réalistes)
TYPES = {r['CodeTy']: r['LibelleTypeSoc'] for r in R['TYPE_SOCIETE']}
SOC = {r['CodeSOC']: dict(row=r, nom=r['NomSOC'], zg=r['CodeZG'], pays=ZG[r['CodeZG']]['CodePays'], p1=True, adh=None)
       for r in R['SOCIETE']}
SERV = {r['CodeSE']: dict(soc=r['CodeSOC'], nom=r['NomSE']) for r in R['SERVICE']}
INSC = {}
for r in R['ETRE_AFFECTE']: INSC[r['CodeE']] = min(INSC.get(r['CodeE'], r['DateDebutAffect']), r['DateDebutAffect'])
EMP = {r['CodeE']: dict(nom=r['NomE'], pre=r['PrenomE'], se=r['CodeSE'], soc=SERV[r['CodeSE']]['soc'], cat=r['CodeCAT'],
                        insc=INSC[r['CodeE']], p1=True) for r in R['EMPLOYE']}

SOC_NEW = [  # nom, pays, commune (INSEE / AGS), catégorie juridique, type, NAF (FR), nb employés bénéficiaires, adhésion
    ('Alpes Semi-conducteurs', 'FR', '38185', '5599', 'GE', '26.11Z', 220, D(2022, 10, 3)),
    ('Hérault Énergies', 'FR', '34172', '5599', 'GE', '35.11Z', 150, D(2022, 9, 5)),
    ('Azur Assurances', 'FR', '06088', '5599', 'ETI', '65.12Z', 110, D(2022, 11, 7)),
    ('Fromageries de Normandie', 'FR', '76540', '5710', 'ETI', '10.51C', 90, D(2022, 10, 17)),
    ('Institut Bourguignon de Recherche Agronomique', 'FR', '21231', '7383', 'ETI', '72.19Z', 80, D(2022, 9, 19)),
    ('Loire Logistique Express', 'FR', '45234', '5499', 'PME', '52.10B', 70, D(2022, 11, 14)),
    ('Volcans Ingénierie', 'FR', '63113', '5710', 'PME', '71.12B', 60, D(2022, 10, 10)),
    ('Seine Digital Factory', 'FR', '92040', '5710', 'ETI', '58.29C', 180, D(2024, 3, 4)),
    ('Défense Conseil Partners', 'FR', '92050', '5710', 'ETI', '70.22Z', 140, D(2022, 9, 12)),
    ('Hôpital Privé de la Plaine', 'FR', '93066', '5499', 'ETI', '86.10Z', 130, D(2022, 12, 5)),
    ('Essonne Recherche Appliquée', 'FR', '91377', '7383', 'GE', '72.19Z', 160, D(2022, 10, 24)),
    ('Atlantique Aéro Composites', 'FR', '44162', '5599', 'GE', '30.30Z', 120, D(2022, 11, 21)),
    ('Gironde Hypermarchés', 'FR', '33281', '5599', 'GE', '47.11F', 110, D(2022, 9, 26)),
    ('Toulouse Space Software', 'FR', '31254', '5710', 'ETI', '62.01Z', 130, D(2025, 1, 6)),
    ('Lyon Ouest Business School', 'FR', '69081', '5710', 'ETI', '85.42Z', 100, D(2022, 10, 3)),
    ('Provence Banque Régionale', 'FR', '13001', '5599', 'GE', '64.19Z', 120, D(2022, 9, 5)),
    ('Nord Retail Services', 'FR', '59009', '5710', 'GE', '47.11F', 140, D(2024, 9, 2)),
    ('Finistère Cybersécurité', 'FR', '29019', '5710', 'PME', '62.02A', 50, D(2022, 11, 28)),
    ('Moselle Mécanique de Précision', 'FR', '57463', '5499', 'PME', '71.12B', 60, D(2022, 12, 12)),
    ('Leipziger Paket-Logistik GmbH', 'DE', '14713000', 'D101', 'ETI', None, 90, D(2026, 1, 5)),
    ('Elbtal Halbleiter AG', 'DE', '14612000', 'D103', 'GE', None, 110, D(2026, 2, 2)),
    ('Ruhrtal Energiedienste GmbH', 'DE', '05113000', 'D101', 'GE', None, 80, D(2026, 1, 12)),
    ('Westfalen Versicherung AG', 'DE', '05913000', 'D103', 'GE', None, 70, D(2026, 3, 2)),
    ('Bonner Forschungsinstitut GmbH', 'DE', '05314000', 'D101', 'PME', None, 50, D(2026, 2, 16)),
    ('Kurpfalz Software GmbH & Co. KG', 'DE', '08222000', 'D203', 'PME', None, 60, D(2026, 4, 6)),
    ('Fugger Handelshaus KG', 'DE', '09761000', 'D201', 'PME', None, 45, D(2026, 3, 16)),
    ('Weser Hafen Logistik GmbH', 'DE', '04011000', 'D101', 'ETI', None, 60, D(2026, 1, 19)),
    ('Leine Consulting UG', 'DE', '03241001', 'D102', 'MICRO', None, 20, D(2026, 5, 4))]
DOMAINE_SOC_DE = {  # équivalent NACE (sous-classe NAF) du code WZ 2008 de chaque société allemande
    'Spreeware GmbH': '62.01Z', 'Isar Logistik GmbH & Co. KG': '52.10B', 'Garchinger Forschungs AG': '72.19Z',
    'Domstadt Consulting UG': '70.22Z', 'Mainfinanz AG': '64.19Z', 'Neckar Engineering GmbH': '71.12B',
    'Rheinmedia OHG': '73.11Z', 'Elbe Hafen Service KG': '52.24A', 'Leipziger Paket-Logistik GmbH': '52.10B',
    'Elbtal Halbleiter AG': '26.11Z', 'Ruhrtal Energiedienste GmbH': '35.11Z', 'Westfalen Versicherung AG': '65.12Z',
    'Bonner Forschungsinstitut GmbH': '72.19Z', 'Kurpfalz Software GmbH & Co. KG': '62.01Z',
    'Fugger Handelshaus KG': '46.90Z', 'Weser Hafen Logistik GmbH': '52.24A', 'Leine Consulting UG': '70.22Z'}
PERI = {'31069', '09184119', '91377', '44162', '33281', '31254', '69081', '13001', '59009'}   # communes périurbaines
SERV_FR = ['Direction', 'Ressources humaines', 'Informatique', 'Comptabilité', 'Commercial', 'Production', 'Logistique']
SERV_DE = ['Geschäftsführung', 'Personal', 'IT', 'Buchhaltung', 'Vertrieb', 'Produktion', 'Logistik']
PRE_FR = ['Marie', 'Lucas', 'Léa', 'Hugo', 'Chloé', 'Louis', 'Emma', 'Gabriel', 'Camille', 'Arthur', 'Manon', 'Jules', 'Sarah',
          'Nathan', 'Inès', 'Thomas', 'Julie', 'Paul', 'Clara', 'Adam', 'Zoé', 'Mathis', 'Lina', 'Théo', 'Alice', 'Raphaël',
          'Nora', 'Yanis', 'Anaïs', 'Karim', 'Sofia', 'Maxime', 'Lucie', 'Antoine', 'Elsa', 'Mehdi', 'Jade', 'Romain']
NOM_FR = ['Martin', 'Bernard', 'Dubois', 'Thomas', 'Robert', 'Richard', 'Petit', 'Durand', 'Leroy', 'Moreau', 'Simon', 'Laurent',
          'Lefebvre', 'Michel', 'Garcia', 'David', 'Bertrand', 'Roux', 'Vincent', 'Fournier', 'Morel', 'Girard', 'André',
          'Mercier', 'Dupont', 'Lambert', 'Bonnet', 'François', 'Martinez', 'Benali', 'Nguyen', 'Diallo', 'Rousseau', 'Blanc',
          'Guerin', 'Faure', 'Chevalier', 'Gauthier', 'Perrin', 'Robin', 'Masson', 'Henry', 'Kone', 'Haddad']
PRE_DE = ['Lukas', 'Anna', 'Leon', 'Mia', 'Finn', 'Emilia', 'Paul', 'Hannah', 'Jonas', 'Lea', 'Felix', 'Sophie', 'Elias', 'Marie',
          'Noah', 'Lena', 'Ben', 'Laura', 'Maximilian', 'Johanna', 'Tim', 'Katharina', 'Jan', 'Clara', 'Moritz', 'Greta']
NOM_DE = ['Müller', 'Schmidt', 'Schneider', 'Fischer', 'Weber', 'Meyer', 'Wagner', 'Becker', 'Schulz', 'Hoffmann', 'Koch',
          'Richter', 'Klein', 'Wolf', 'Schröder', 'Neumann', 'Schwarz', 'Zimmermann', 'Braun', 'Krüger', 'Hartmann', 'Lange',
          'Yilmaz', 'Kaya', 'Werner', 'Krause', 'Lehmann', 'Köhler']


def luhn_ok(s):
    t = 0
    for i, ch in enumerate(reversed(s)):
        d = int(ch) * (2 if i % 2 else 1); t += d - 9 if d > 9 else d
    return t % 10 == 0
def luhn_complete(prefix):
    return next(prefix + c for c in '0123456789' if luhn_ok(prefix + c))


cse, ce = max(SERV), max(EMP)
for nm, pays, zg, cj, ty, naf, ne, adh in SOC_NEW:
    code = None
    while code is None or code in SOC:
        code = luhn_complete(f"{random.randint(30000000, 99999999)}") if pays == 'FR' else f"DE{random.randint(100000000, 999999999)}"
    zgc = zg if pays == 'FR' else 'DE' + zg
    row = ins('SOCIETE', CodeSOC=code, NomSOC=nm, CodeTy=ty, CodeZG=zgc, CodeCJ=cj, CodeDO=naf)
    SOC[code] = dict(row=row, nom=nm, zg=zgc, pays=pays, p1=False, adh=adh)
    nbs = 3 if ne < 10 else 4 if ne < 20 else 6 if ne < 100 else 7
    svs = []
    for j in sorted([0, 1, 2] + random.sample(range(3, 7), nbs - 3)):
        cse += 1; svs.append(cse)
        SERV[cse] = dict(soc=code, nom=(SERV_FR if pays == 'FR' else SERV_DE)[j])
        ins('SERVICE', CodeSE=cse, NomSE=SERV[cse]['nom'], CodeSOC=code)
    zt = 'peri' if zg in PERI else 'dense'
    for _ in range(ne):
        ce += 1
        if nm == 'Seine Digital Factory':          # P4 : vague de recrutements de juin 2024 à fin 2025
            insc = rdate(adh, addd(adh, 90)) if random.random() < .25 else rdate(D(2024, 6, 1), D(2025, 12, 31))
        elif pays == 'DE':                         # P5 : montée en charge allemande
            insc = rdate(adh, addd(adh, 60)) if random.random() < .6 else rdate(adh, D(2026, 8, 31))
        else:
            insc = rdate(adh, addd(adh, 90)) if random.random() < .85 else rdate(addd(adh, 90), D(2026, 8, 31))
        fr = pays == 'FR'
        EMP[ce] = dict(nom=random.choice(NOM_FR if fr else NOM_DE), pre=random.choice(PRE_FR if fr else PRE_DE),
                       se=random.choice(svs), soc=code, insc=insc, p1=False,
                       cat=random.choices(list(CAT_W), [w * CLS_ZONE[zt][c[:2]] for c, w in CAT_W.items()])[0])
for s in SOC.values():
    if s['pays'] == 'DE': s['row']['CodeDO'] = DOMAINE_SOC_DE[s['nom']] if DOMAINE_DE else None

# Comportement de chaque employé : agence de rattachement, poids (gros ou petit loueur), préférences de gammes
PROV = next(c for c, s in SOC.items() if s['nom'] == 'Provence Banque Régionale')
for v in EMP.values():
    s = SOC[v['soc']]
    v['pays'], v['reg'], v['cls'] = s['pays'], sommet(s['zg']), v['cat'][:2]
    v['ag'] = HOME[v['reg']]
    v['w'] = (6 if random.random() < .25 else 1) * (.3 if random.random() < .3 else 1)
    v['gw'] = {g: b * GAMME_CLS[v['cls']].get(g, 1) * (GAMME_ARA.get(g, 1) if v['reg'] == 'R84' else 1)
                  * (GAMME_DE.get(g, 1) if v['pays'] == 'DE' else 1) for g, b in POP.items()}

# ================================================================== 3. parc d'exemplaires
EX = {r['CodeEX']: dict(p=r['CodeP'], ag=r['CodeAG'], pays=AG[r['CodeAG']]['CodePays'], ms=r['DateMiseServiceEX'],
                        ref=r['DateReformeEX'], starts=[], ends=[]) for r in R['EXEMPLAIRE']}
for r in sorted(R['LOUER'], key=lambda r: r['DateL']):   # occupations des locations du projet 1
    EX[r['CodeEX']]['starts'].append(r['DateL']); EX[r['CodeEX']]['ends'].append(addd(r['DateL'], r['Duree_Loc']))
LOUABLES = sorted(p for p, pr in PROD.items() if pr['loc'])
PROD_G = collections.defaultdict(list)
for p in LOUABLES: PROD_G[PROD[p]['gamme']].append(p)

# demande attendue (jours de location) par agence et gamme -> taille du parc à atteindre
DEBUT = {'FR': START, 'DE': DE_START}
dem, tot = collections.defaultdict(float), collections.Counter()
for v in EMP.values():
    d0 = DEBUT[v['pays']]
    k = (v['w'] * FREQ[v['cls']] * DMOY[v['cls']] * (DUREE_DE if v['pays'] == 'DE' else 1)
         * max(0, days(max(v['insc'], d0), LAST)) / days(d0, LAST) / sum(v['gw'].values()))
    for g, x in v['gw'].items():
        dem[(v['ag'], g)] += k * x; tot[v['pays']] += k * x
existe = collections.defaultdict(float)   # parc du projet 1, compté au prorata de sa durée de service sur la période
for x in EX.values():
    d0 = DEBUT[x['pays']]
    existe[(x['ag'], PROD[x['p']]['gamme'])] += max(0, days(max(x['ms'], d0), min(x['ref'] or LAST, LAST))) / days(d0, LAST)
cex = max(EX)
def nouvel_exemplaire(ag, p):
    global cex
    pays, sortie = AG[ag]['CodePays'], GENS[PROD[p]['gen']]['DateSortieGEN']
    ref = None
    if pays == 'FR':                       # le parc grandit chaque hiver, avant la saison
        u = random.random()
        ms = (rdate(D(2022, 6, 1), D(2022, 12, 15)) if u < .55 else rdate(D(2024, 1, 8), D(2024, 4, 15)) if u < .75
              else rdate(D(2025, 1, 6), D(2025, 4, 14)))
        if ms < sortie: ms = rdate(sortie, addd(sortie, 90))
        lo = max(addd(ms, 400), D(2025, 1, 1))
        if random.random() < .08 and lo < D(2026, 9, 30): ref = rdate(lo, D(2026, 9, 30))
    else:
        ms = max(rdate(D(2025, 12, 1), D(2026, 3, 31)), sortie)
    cex += 1
    EX[cex] = dict(p=p, ag=ag, pays=pays, ms=ms, ref=ref, starts=[], ends=[])
    ins('EXEMPLAIRE', CodeEX=cex, NumSerieEX=f"MP-{pays}-{ms.year}-{cex:05d}", DateMiseServiceEX=ms, DateReformeEX=ref, CodeAG=ag, CodeP=p)
for (ag, g), q in sorted(dem.items()):
    pays = AG[ag]['CodePays']
    cible = q / tot[pays] * PARC[pays] * CAP.get((ag, g), 1)
    n = max(0, round(cible - existe[(ag, g)]))
    if n == 0 and existe[(ag, g)] < .5 and cible >= .6: n = 1
    for _ in range(n): nouvel_exemplaire(ag, random.choice(PROD_G[g]))
for ag in sorted({v['ag'] for v in EMP.values()}):   # parc minimum de 8 exemplaires, dans les gammes les plus demandées
    l = sorted(((q, g) for (a, g), q in dem.items() if a == ag), reverse=True)
    for i in range(max(0, 8 - sum(1 for x in EX.values() if x['ag'] == ag))):
        nouvel_exemplaire(ag, random.choice(PROD_G[l[i % len(l)][1]]))
for p in sorted(set(LOUABLES) - {x['p'] for x in EX.values()}):   # chaque produit louable a au moins un exemplaire
    g = PROD[p]['gamme']
    nouvel_exemplaire(max((a for a in AG if AG[a]['CodePays'] == 'FR'), key=lambda a: dem[(a, g)]), p)
EXAGP, EXAG = collections.defaultdict(list), collections.defaultdict(list)
for x, v in EX.items():
    EXAGP[(v['ag'], v['p'])].append(x); EXAG[(v['ag'], PROD[v['p']]['gamme'])].append(x)
PRODS_AG = {k: sorted({EX[x]['p'] for x in l}) for k, l in EXAG.items()}
for v in EMP.values():                     # un employé ne demande que les gammes proposées par son agence
    v['gs'] = [g for g in v['gw'] if (v['ag'], g) in PRODS_AG]
    v['gcum'] = list(itertools.accumulate(v['gw'][g] for g in v['gs']))

# ================================================================== 4. demandes, locations et réservations
def libre(x, d, fin):
    e = EX[x]
    if d < e['ms'] or (e['ref'] and fin > e['ref']): return False
    i = bisect.bisect_right(e['starts'], d)
    return not ((i > 0 and e['ends'][i - 1] > d) or (i < len(e['starts']) and e['starts'][i] < fin))
def occupe(x, d, fin):
    e = EX[x]; i = bisect.bisect_right(e['starts'], d)
    e['starts'].insert(i, d); e['ends'].insert(i, fin)
def poisson(lam):
    if lam > 40: return max(0, round(random.gauss(lam, math.sqrt(lam))))
    k, p, seuil = 0, 1.0, math.exp(-lam)
    while True:
        p *= random.random()
        if p < seuil: return k
        k += 1
def facteur(e, d):                         # P4 : Provence Banque Régionale passe à ses propres vélos en avril 2025
    return .2 if EMP[e]['soc'] == PROV and d >= D(2025, 4, 1) else 1.0

RES_PK = {(r['CodeE'], r['CodeP'], r['DateLPrev']) for r in R['RESERVER']}
EMPS = {pays: sorted(e for e, v in EMP.items() if v['pays'] == pays) for pays in ('FR', 'DE')}
nb_dem = nb_ok = 0
d, actifs = START, {}
while d <= LAST:
    if d == START or d.weekday() == 0:      # employés actifs et poids, recalculés chaque lundi
        for pays, l in EMPS.items():
            act = [e for e in l if EMP[e]['insc'] <= d]
            actifs[pays] = (act, list(itertools.accumulate(EMP[e]['w'] * FREQ[EMP[e]['cls']] * facteur(e, d) for e in act)))
    for pays in ('FR', 'DE'):
        act, cum = actifs[pays]
        if (pays == 'DE' and d < DE_START) or not act: continue
        lam = (RATE[pays] * YEAR_F[d.year] * MONTH_W[d.month] * DOW_W[d.weekday()] * cum[-1]
               * (MOBILITE if d.month == 9 and 16 <= d.day <= 22 else 1))
        for _ in range(poisson(lam)):
            e = act[bisect.bisect_right(cum, random.random() * cum[-1])]
            v = EMP[e]
            g = v['gs'][bisect.bisect_right(v['gcum'], random.random() * v['gcum'][-1])]
            p = random.choice(PRODS_AG[(v['ag'], g)])
            du = random.choice(DUR[v['cls']])
            if pays == 'DE': du = min(30, max(1, round(du * DUREE_DE)))
            fin = addd(d, du)
            if fin > LAST: continue
            nb_dem += 1
            c1 = EXAGP[(v['ag'], p)][:]; random.shuffle(c1)                       # le produit demandé...
            c2 = [x for x in EXAG[(v['ag'], g)] if EX[x]['p'] != p]; random.shuffle(c2)   # ...sinon un autre de la gamme
            x = next((x for x in c1 + c2 if libre(x, d, fin)), None)
            dr = max(addd(d, -random.choice(DELAIS)), v['insc'])
            if x:
                occupe(x, d, fin); nb_ok += 1
                ins('LOUER', CodeE=e, CodeEX=x, DateL=d, Duree_Loc=du)
                px = EX[x]['p']
                if random.random() < P_RESA and (e, px, d) not in RES_PK:
                    RES_PK.add((e, px, d)); ins('RESERVER', CodeE=e, CodeP=px, DateLPrev=d, Nb_Ex_Prev=1, DateResa=dr, Duree_Prev=du)
            elif (e, p, d) not in RES_PK:          # aucun exemplaire libre : réservation non honorée
                RES_PK.add((e, p, d)); ins('RESERVER', CodeE=e, CodeP=p, DateLPrev=d, Nb_Ex_Prev=1, DateResa=dr, Duree_Prev=du)
    d = addd(d, 1)
LOUE = {(r['CodeE'], EX[r['CodeEX']]['p'], r['DateL']) for r in R['LOUER']}

# ================================================================== 5. contrôles (règles du sujet et du dictionnaire)
err = []
def chk(c, m):
    if not c: err.append(m)
PAYS = {r['CodePays']: r for r in R['PAYS']}
ex_ok = {r['CodeEX']: r for r in R['EXEMPLAIRE']}
chk(len({(r['CodeE'], r['CodeEX'], r['DateL']) for r in R['LOUER']}) == len(R['LOUER']), "clé de LOUER en double")
chk(len(RES_PK) == len(R['RESERVER']), "clé de RESERVER en double")
chk(P1_LOUER <= {(r['CodeE'], r['CodeEX'], r['DateL'], r['Duree_Loc']) for r in R['LOUER']}, "locations du projet 1 modifiées")
occ = collections.defaultdict(list)
for r in R['LOUER']:
    x, v, d, du = EX[r['CodeEX']], EMP[r['CodeE']], r['DateL'], r['Duree_Loc']
    fin = addd(d, du); occ[r['CodeEX']].append((d, fin))
    pj = prix_jour(x['pays'], x['p'], d); taux = RED.get((v['cat'], GCODE[PROD[x['p']]['gamme']], d.year))
    chk(du > 0 and d < TODAY and fin <= LAST, f"durée ou date de location {r}")
    chk(d >= x['ms'] and (x['ref'] is None or fin <= x['ref']), f"location hors mise en service / réforme {r}")
    chk(v['insc'] <= d and v['pays'] == x['pays'], f"employé inactif ou exemplaire d'un autre pays {r}")
    chk(pj is not None and taux is not None and 0 < taux <= 1, f"tarif ou réduction manquant {r}")
for x, l in occ.items():
    l.sort()
    chk(all(a[1] <= b[0] for a, b in zip(l, l[1:])), f"chevauchement sur l'exemplaire {x}")
for r in R['RESERVER']:
    chk(r['DateResa'] <= r['DateLPrev'] < TODAY and r['Duree_Prev'] > 0 and r['Nb_Ex_Prev'] > 0, f"réservation {r}")
    chk(EMP[r['CodeE']]['insc'] <= r['DateResa'] and PROD[r['CodeP']]['loc'], f"réservation d'un employé inactif ou d'un produit non louable {r}")
for x, v in EX.items():
    chk(v['ms'] >= GENS[PROD[v['p']]['gen']]['DateSortieGEN'] and (v['ref'] is None or v['ref'] > v['ms']), f"dates de l'exemplaire {x}")
for (pays, p), l in TARIF.items():
    s = sorted(l, key=lambda t: t[0])
    chk(all(a[1] is not None and a[1] < b[0] for a, b in zip(s, s[1:])), f"tarifs qui se chevauchent {pays} {p}")
for r in R['TARIFER']:
    chk(r['Prix_vente'] > 0 and (r['Prix_loc_jour'] is None or 0 < r['Prix_loc_jour'] < r['Prix_vente']), f"prix {r}")
chk(all(0 < r['PctReduc_Loc'] <= 1 and 0 < r['PctReduc_Achat'] <= 1 for r in R['REDUCTION']), "réduction hors ]0 ; 1]")
OK_PAR = {('COMMUNE', 'DEPARTEMENT'), ('DEPARTEMENT', 'REGION'), ('GEMEINDE', 'LANDKREIS'), ('GEMEINDE', 'KREISFREIE STADT'),
          ('LANDKREIS', 'DISTRICT'), ('LANDKREIS', 'LAND'), ('KREISFREIE STADT', 'DISTRICT'), ('KREISFREIE STADT', 'LAND'), ('DISTRICT', 'LAND')}
for r in R['ZONE_GEO']:
    par = r['CodeZG_zone_englobante']
    chk((r['NiveauZG'] in ('REGION', 'LAND')) == (par is None) and len(r['CodeZG']) <= 10, f"zone {r['CodeZG']}")
    if par: chk((r['NiveauZG'], ZG[par]['NiveauZG']) in OK_PAR and ZG[par]['CodePays'] == r['CodePays'], f"zone englobante {r['CodeZG']}")
for c, r in DOM.items():
    s = r['CodeDO_Sup']
    chk(re.fullmatch(r'[0-9]{2}(\.[0-9]([0-9][A-Z]?)?)?', c) and ((len(c) == 2 and s is None) or (s in DOM and c.startswith(s))), f"domaine {c}")
for c, s in SOC.items():
    chk(re.fullmatch(r'[0-9]{9}|DE[0-9]{9}', c) and (s['row']['CodeDO'] is None or len(s['row']['CodeDO']) == 6), f"société {c}")
annees = collections.defaultdict(set)
for r in R['LOUER']: annees[r['DateL'].year].add(r['DateL'].month)
VOL = [('sociétés', len(SOC), 40), ('régions (FR) et Länder (DE) des sociétés', len({sommet(s['zg']) for s in SOC.values()}), 5),
       ('employés', len(EMP), 3000), ('produits', len(PROD), 60), ('produits loués', len({x['p'] for x in EX.values()}), 60),
       ('secteurs des produits loués', len({SECT[PROD[x['p']]['gamme']] for x in EX.values()}), 3),
       ('exemplaires', len(EX), 400), ('locations', len(R['LOUER']), 60000),
       ('années complètes (12 mois de locations)', sum(1 for a in annees.values() if len(a) == 12), 3)]
for nom, nb, mini in VOL: chk(nb >= mini, f"volume insuffisant : {nom} {nb} < {mini}")
print("ERREURS :", err[:10] if err else "aucune")

# ================================================================== 6. fichiers CSV
def txt(v):
    if v is None: return ''
    if isinstance(v, D): return v.isoformat()
    return repr(v) if isinstance(v, float) else str(v)
def ecrire(chemin, entete, lignes):
    chemin.parent.mkdir(exist_ok=True)
    with open(chemin, 'w', encoding='utf-8-sig', newline='') as f:   # UTF-8 avec BOM : Excel affiche bien les accents
        w = csv.writer(f, lineterminator='\r\n')
        w.writerow(entete)
        for l in lignes: w.writerow([txt(v) for v in l])
    print(f"écrit : {chemin.relative_to(ICI)} ({len(lignes)} lignes)")

CATS = {r['CodeCAT']: r for r in R['CATEGORIE']}
def ligne_employe(e):            # colonnes de la dimension Employe_MD de la conception (docs/Location_MD.json)
    v = EMP[e]; s = SOC[v['soc']]; r = s['row']
    com = ZG[s['zg']]; par = ZG[com['CodeZG_zone_englobante']]; som = ZG[sommet(s['zg'])]
    do = r['CodeDO']
    dom = [do, DOM[do]['NomDO'], do[:2], DOM[do[:2]]['NomDO']] if do else ['ND', 'Non renseigné', 'ND', 'Non renseigné']
    so, lib_so = 'SO-' + s['pays'], 'Sans objet (France)' if s['pays'] == 'FR' else 'Sans objet (Allemagne)'
    if s['pays'] == 'FR':          # commune > département > région ; niveaux allemands « sans objet »
        fr = [com['CodeZG'], com['NomZG'], par['CodeZG'], par['NomZG'], som['CodeZG'], som['NomZG']]
        de = [so, lib_so, so, lib_so, lib_so, so, lib_so, so, lib_so, lib_so]
    else:                          # Gemeinde > Kreis (> District) > Land ; niveaux français « sans objet »
        sup = ZG[par['CodeZG_zone_englobante']]
        dis = ([sup['CodeZG'], sup['NomZG']] if sup['NiveauZG'] == 'DISTRICT'
               else [som['CodeZG'] + '-SD', f"Sans district ({som['NomZG']})"])
        fr = [so, lib_so] * 3
        de = [com['CodeZG'], com['NomZG'], par['CodeZG'], par['NomZG'],
              'Landkreis' if par['NiveauZG'] == 'LANDKREIS' else 'Kreisfreie Stadt', *dis, som['CodeZG'], som['NomZG'],
              'Stadtstaat' if som['CodeZG'] in ('DE02', 'DE04', 'DE11') else 'Flächenland']
    return [e, v['nom'], v['pre'], v['cat'], CATS[v['cat']]['NomCAT'], CATS[v['cat']]['SuperCAT'], v['se'], SERV[v['se']]['nom'],
            v['soc'], s['nom'], r['CodeTy'], TYPES[r['CodeTy']], *dom, *fr, *de,
            s['pays'], PAYS[s['pays']]['NomPays'], PAYS[s['pays']]['TauxTVA']]
def ligne_location(r):
    x, v = EX[r['CodeEX']], EMP[r['CodeE']]
    pj = prix_jour(x['pays'], x['p'], r['DateL'])
    if x['pays'] == 'DE': pj = round(pj * (1 + PAYS['DE']['TauxTVA']), 2)   # prix allemands HT -> TTC
    return [r['CodeE'], r['CodeEX'], r['DateL'], r['Duree_Loc'], pj, RED[(v['cat'], GCODE[PROD[x['p']]['gamme']], r['DateL'].year)]]
H_EMP = ['CodeEmploye', 'NomEmploye', 'PrenomEmploye', 'CodeCategorie', 'NomCategorie', 'SuperCategorie', 'CodeService',
         'NomService', 'CodeSociete', 'NomSociete', 'CodeTy', 'LibelleTypeSoc', 'CodeDomaine', 'LibDomaine', 'CodeDivision',
         'LibDivision', 'CodeVille', 'NomVille', 'CodeDepartement', 'NomDepartement', 'CodeRegion', 'NomRegion', 'CodeGemeinde',
         'NomGemeinde', 'CodeKreis', 'NomKreis', 'TypeKreis', 'CodeDistrict', 'NomDistrict', 'CodeLand', 'NomLand', 'TypeLand',
         'CodePays', 'NomPays', 'TauxTVA']
L_EMP = [ligne_employe(e) for e in sorted(EMP)]
H_PRO = ['CodeProduit', 'NomProduit', 'MarqueProduit', 'DescriptifProduit', 'PoidsKg', 'AutonomieKm', 'CodeGamme', 'NomGamme',
         'Secteur', 'CodeGeneration', 'NomGeneration', 'DateSortieGeneration', 'DateArretGeneration', 'CodeFabricant',
         'NomFabricant', 'PaysFabricant']
L_PRO = [[r['CodeP'], r['NomP'], r['MarqueP'], r['DescriptifP'], r['PoidsKg'], r['AutonomieKm'], r['CodeG'], GNOM[r['CodeG']],
          SECT[GNOM[r['CodeG']]], r['CodeGEN'], GENS[r['CodeGEN']]['NomGEN'], GENS[r['CodeGEN']]['DateSortieGEN'],
          GENS[r['CodeGEN']]['DateArretGEN'], GENS[r['CodeGEN']]['CodeFAB'], FAB[GENS[r['CodeGEN']]['CodeFAB']]['NomFAB'],
          FAB[GENS[r['CodeGEN']]['CodeFAB']]['PaysFAB']] for r in R['PRODUIT']]
H_EX = ['CodeExemplaire', 'NumeroSerie', 'DateMiseService', 'DateReforme', 'CodeAgence', 'NomAgence', 'VilleAgence', 'PaysAgence', 'CodeProduit']
L_EX = [[r['CodeEX'], r['NumSerieEX'], r['DateMiseServiceEX'], r['DateReformeEX'], r['CodeAG'], AG[r['CodeAG']]['NomAG'],
         AG[r['CodeAG']]['VilleAG'], AG[r['CodeAG']]['CodePays'], r['CodeP']] for r in R['EXEMPLAIRE']]
H_LOC = ['CodeEmploye', 'CodeExemplaire', 'DateLocation', 'DureeLocation', 'PrixJourTTC', 'TauxReduction']
L_LOC = [ligne_location(r) for r in R['LOUER']]
H_RES = ['CodeEmploye', 'CodeProduit', 'DateLocationPrevue', 'DateReservation', 'NbExemplaires', 'DureePrevue']
L_RES = [[r['CodeE'], r['CodeP'], r['DateLPrev'], r['DateResa'], r['Nb_Ex_Prev'], r['Duree_Prev']] for r in R['RESERVER']]

# Données manquantes et erronées, comme dans de vraies sources (environ 2 % des lignes) : le chargement
# (03_chargement_dw.sql) doit les détecter, puis les compléter, les corriger ou les rejeter.
rng = random.Random(4242)                 # tirages à part : les anomalies ne modifient pas les données propres
ANOM = []
def note(fichier, anomalie, nb, traitement): ANOM.append([fichier, anomalie, nb, traitement])
taille = collections.Counter(l[6] for l in L_EMP)
cand = [i for i, l in enumerate(L_EMP) if taille[l[6]] >= 6]
rng.shuffle(cand)
for i in cand[:40]: L_EMP[i][3:6] = [None] * 3
note('employe.csv', 'profil de trajet manquant', 40, 'complétée (profil « non renseigné »)')
var, n = collections.Counter(), 0
for i in cand[40:]:
    l = L_EMP[i]
    v = rng.choice([l[7].upper(), l[7].lower(), ' ' + l[7], l[7] + '  '])
    if v == l[7] or var[l[6]] >= taille[l[6]] // 5: continue
    l[7] = v; var[l[6]] += 1; n += 1
    if n == 120: break
note('employe.csv', 'libellé de service mal écrit (casse, espaces)', n, 'corrigée (libellé majoritaire du service)')
sans_dom = {c for c, s_ in SOC.items() if s_['nom'] in ('Loire Logistique Express', 'Finistère Cybersécurité')}
n = 0
for l in L_EMP:
    if l[8] in sans_dom: k = H_EMP.index('CodeDomaine'); l[k:k + 4] = [None] * 4; n += 1
note('employe.csv', 'domaine de la société manquant', n, 'complétée (domaine « non renseigné »)')
for l in rng.sample(L_EMP, 15): L_EMP.append(l[:])
note('employe.csv', 'ligne en double', 15, 'doublon supprimé')
for l in rng.sample([l for l in L_PRO if not PROD[l[0]]['p1']], 2): l[2] = None
note('produit.csv', 'marque manquante', 2, 'complétée (marque « non renseignée »)')
for l in rng.sample([l for l in L_EX if l[3] is None], 5): l[3] = addd(l[2], -rng.randint(10, 200))
note('exemplaire.csv', 'date de réforme antérieure à la mise en service', 5, 'corrigée (date supprimée)')
idx = rng.sample([i for i, l in enumerate(L_LOC) if not (l[2].month == 2 and l[2].day == 29)], 1175)
def prend(k):
    global idx
    pris, idx = idx[:k], idx[k:]
    return pris
for i in prend(60): L_LOC[i][3] = rng.choice([0, -1, -2, -5])
note('location.csv', 'durée nulle ou négative', 60, 'rejetée')
for i in prend(25): L_LOC[i][3] = 999
note('location.csv', 'durée aberrante (999 jours)', 25, 'rejetée')
for i in prend(20): L_LOC[i][2] = L_LOC[i][2].replace(year=2027)
note('location.csv', 'date future', 20, 'rejetée')
for k, i in enumerate(prend(20)): L_LOC[i][0] = 99001 + k
note('location.csv', 'employé inconnu', 20, 'rejetée')
for i in prend(300): L_LOC[i][4] = None
note('location.csv', 'prix journalier manquant', 300, 'complétée (prix du même produit, même pays, même mois)')
for i in prend(200): L_LOC[i][5] = None
note('location.csv', 'taux de réduction manquant', 200, 'complétée (taux du même employé, même gamme, même année)')
for i in prend(150): L_LOC[i][5] = round(L_LOC[i][5] * 100, 1)
note('location.csv', 'taux de réduction saisi en pourcentage (15 au lieu de 0,15)', 150, 'corrigée (divisé par 100)')
n, pris = 0, {(l[0], l[1], l[2]) for l in L_LOC}
for i in idx:                              # fausses locations qui chevauchent une vraie location du même exemplaire
    l = L_LOC[i]; x = EX[l[1]]; d2 = addd(l[2], 1); du2 = rng.randint(1, 3); e2 = rng.choice(EMPS[x['pays']])
    if (l[3] < 3 or EMP[e2]['insc'] > d2 or e2 == l[0] or (e2, l[1], d2) in pris or addd(d2, du2) > LAST
            or (x['ref'] and addd(d2, du2) > x['ref'])): continue
    L_LOC.append([e2, l[1], d2, du2, l[4], l[5]]); pris.add((e2, l[1], d2)); n += 1
    if n == 30: break
note('location.csv', 'exemplaire loué deux fois en même temps', n, 'rejetée (on garde la location commencée la première)')
for l in rng.sample(L_LOC[:len(R['LOUER'])], 250): L_LOC.append(l[:])
note('location.csv', 'ligne en double', 250, 'doublon supprimé')
idx = rng.sample(range(len(L_RES)), 135)
for i in idx[:80]: L_RES[i][4] = None
note('reservation.csv', "nombre d'exemplaires manquant", 80, 'complétée (1 exemplaire)')
for i in idx[80:120]: L_RES[i][3] = addd(L_RES[i][2], rng.randint(1, 10))
note('reservation.csv', 'date de réservation après la location prévue', 40, 'rejetée')
for i in idx[120:]: L_RES[i][1] = 999
note('reservation.csv', 'produit inconnu', 15, 'rejetée')
for l in rng.sample(L_RES[:len(R['RESERVER'])], 100): L_RES.append(l[:])
note('reservation.csv', 'ligne en double', 100, 'doublon supprimé')

ecrire(ICI / 'csv' / 'employe.csv', H_EMP, L_EMP)
ecrire(ICI / 'csv' / 'produit.csv', H_PRO, L_PRO)
ecrire(ICI / 'csv' / 'exemplaire.csv', H_EX, L_EX)
ecrire(ICI / 'csv' / 'location.csv', H_LOC, L_LOC)
ecrire(ICI / 'csv' / 'reservation.csv', H_RES, L_RES)
ecrire(ICI / 'referentiels' / 'anomalies_injectees.csv', ['Fichier', 'Anomalie', 'NbLignes', 'TraitementAttendu'], ANOM)

# Version du chargement sans BULK INSERT, pour un serveur distant (etu-mssql3) qui ne voit pas les fichiers du PC :
# même script que 03_chargement_dw.sql, mais les données des CSV y sont écrites en INSERT (1 000 lignes par INSERT).
def sql_val(v):
    if v is None: return 'NULL'
    if isinstance(v, D): return f"'{v.isoformat()}'"
    if isinstance(v, (int, float)): return repr(v)
    return "N'" + str(v).replace("'", "''") + "'"
modele = (ICI.parent / '1_entrepot_sql' / '03_chargement_dw.sql').read_text(encoding='utf-8-sig').replace('\r\n', '\n')
debut, fin = modele.index('SET NOCOUNT ON;'), modele.index('DECLARE @sql NVARCHAR(MAX), @options')
out = ["-- MobiPass - Projet 2 : chargement de l'entrepôt dw, VERSION SANS BULK INSERT (serveur distant, ex. etu-mssql3)",
       "-- Fichier produit par 3_donnees/gen_donnees_projet2.py à partir de 03_chargement_dw.sql : ne pas le modifier à la main.",
       "-- Même traitement que 03_chargement_dw.sql (contrôle qualité, dimensions puis faits), mais les données des fichiers",
       "-- CSV sont écrites ici en INSERT : le serveur n'a pas besoin de voir les fichiers de votre PC.",
       "-- À lancer après 01_creation_dw.sql et 02_dimension_temps.sql, dans la même base (liste déroulante de SSMS).", "",
       modele[modele.index('IF DB_NAME() IN'):debut].rstrip(),
       re.sub(r"DECLARE @dossier[^\n]*\n", "", modele[debut:fin]).rstrip(), "GO"]
for table, lignes in (('#employe', L_EMP), ('#produit', L_PRO), ('#exemplaire', L_EX), ('#location', L_LOC), ('#reservation', L_RES)):
    out.append(f"-- {table[1:]}.csv : {len(lignes)} lignes")
    for k in range(0, len(lignes), 1000):
        out.append(f"INSERT INTO {table} VALUES\n" + ",\n".join("(" + ", ".join(sql_val(v) for v in l) + ")" for l in lignes[k:k + 1000]) + ";")
        if k // 1000 % 10 == 9: out.append("GO")
    out.append("GO")
out += ["SET NOCOUNT ON;", modele[modele.index('CREATE INDEX ix_location'):]]
FAC = ICI.parent / '1_entrepot_sql' / '03_chargement_dw_fac.sql'
with open(FAC, 'w', encoding='utf-8-sig', newline='\r\n') as f: f.write("\n".join(out))
print(f"écrit : {FAC.relative_to(ICI.parent)} ({FAC.stat().st_size / 1048576:.1f} Mo)")

# référentiels à relire (origine : projet 1 ou ajout du projet 2)
nbe, nbx = collections.Counter(v['soc'] for v in EMP.values()), collections.Counter(x['ag'] for x in EX.values())
ecrire(ICI / 'referentiels' / 'societes.csv',
       ['CodeSociete', 'NomSociete', 'Pays', 'Ville', 'RegionOuLand', 'CodeDomaine', 'Domaine', 'TypeSociete', 'CategorieJuridique',
        'NbEmployesBeneficiaires', 'DateAdhesion', 'Origine'],
       [[c, s['nom'], s['pays'], ZG[s['zg']]['NomZG'], ZG[sommet(s['zg'])]['NomZG'], s['row']['CodeDO'],
         DOM[s['row']['CodeDO']]['NomDO'] if s['row']['CodeDO'] else None, s['row']['CodeTy'], s['row']['CodeCJ'], nbe[c], s['adh'],
         'projet 1' if s['p1'] else 'projet 2'] for c, s in SOC.items()])
ecrire(ICI / 'referentiels' / 'produits.csv',
       ['CodeProduit', 'NomProduit', 'Marque', 'Gamme', 'Secteur', 'Fabricant', 'PaysFabricant', 'PrixLocJourHT', 'PrixVenteHT',
        'Louable', 'NbExemplaires', 'Origine'],
       [[r['CodeP'], r['NomP'], r['MarqueP'], GNOM[r['CodeG']], SECT[GNOM[r['CodeG']]], FAB[GENS[r['CodeGEN']]['CodeFAB']]['NomFAB'],
         FAB[GENS[r['CodeGEN']]['CodeFAB']]['PaysFAB'], round(PROD[r['CodeP']]['loc'], 2) if PROD[r['CodeP']]['loc'] else None,
         round(PROD[r['CodeP']]['vente'], 2), 'oui' if PROD[r['CodeP']]['loc'] else 'non',
         sum(1 for x in EX.values() if x['p'] == r['CodeP']), 'projet 1' if PROD[r['CodeP']]['p1'] else 'projet 2'] for r in R['PRODUIT']])
ecrire(ICI / 'referentiels' / 'agences.csv', ['CodeAgence', 'NomAgence', 'Ville', 'Pays', 'NbExemplaires', 'Origine'],
       [[c, a['NomAG'], a['VilleAG'], a['CodePays'], nbx[c], 'projet 1' if c in P1_AGENCES else 'projet 2'] for c, a in AG.items()])
ecrire(ICI / 'referentiels' / 'tarifs.csv', ['Pays', 'CodeProduit', 'DateDebut', 'DateFin', 'PrixLocJour', 'PrixVente', 'ModePrix'],
       [[r['CodePays'], r['CodeP'], r['DateDebutTarif'], r['DateFinTarif'], r['Prix_loc_jour'], r['Prix_vente'], r['ModePrix']]
        for r in sorted(R['TARIFER'], key=lambda r: (r['CodePays'], r['CodeP'], r['DateDebutTarif']))])
ecrire(ICI / 'referentiels' / 'reductions.csv', ['CodeProfil', 'CodeGamme', 'Gamme', 'Annee', 'PctReducLocation', 'PctReducAchat'],
       [[r['CodeCAT'], r['CodeG'], GNOM[r['CodeG']], r['Annee'], r['PctReduc_Loc'], r['PctReduc_Achat']]
        for r in sorted(R['REDUCTION'], key=lambda r: (r['CodeCAT'], r['CodeG'], r['Annee']))])
ecrire(ICI / 'referentiels' / 'profils_trajet.csv', ['CodeProfil', 'Profil', 'ClasseTrajet', 'DureeMoyenneVisee', 'FrequenceRelative'],
       [[c, r['NomCAT'], r['SuperCAT'], round(DMOY[c[:2]], 1), FREQ[c[:2]]] for c, r in CATS.items()])

# ================================================================== 7. indicateurs des phénomènes (pour la vérité terrain)
print(f"\nvolumes (minimum du sujet) :")
for nom, nb, mini in VOL: print(f"  {nom:45s}{nb:7d}  ({mini})")
print(f"  ajouts au projet 1 : " + ", ".join(f"{t} +{len(R[t]) - n}" for t, n in P1_NB.items()))
print(f"demandes simulées {nb_dem}, servies {nb_ok} ({nb_ok / nb_dem:.1%})")
loc = collections.Counter((r['DateL'].year, EMP[r['CodeE']]['pays']) for r in R['LOUER'])
print("locations par année :", {a: (loc[(a, 'FR')], loc[(a, 'DE')]) for a in range(2023, 2027)}, "(FR, DE)")
res = [(r, (r['CodeE'], r['CodeP'], r['DateLPrev']) not in LOUE) for r in R['RESERVER']]
nh = [r for r, n in res if n]
print(f"P1 réservations {len(res)}, non honorées {len(nh)} ({len(nh) / len(res):.1%})")
m = collections.Counter(r['DateLPrev'].month for r in nh)
print("   non honorées par mois :", dict(sorted(m.items())))
s = collections.Counter((r['DateLPrev'].isocalendar()[0], r['DateLPrev'].isocalendar()[1]) for r in nh)
print("   semaines ISO les plus touchées :", s.most_common(6))
a = collections.Counter((EMP[r['CodeE']]['ag'], PROD[r['CodeP']]['gamme']) for r in nh)
print("   agences x gammes les plus touchées :", a.most_common(5))
g = collections.Counter((EMP[r['CodeE']]['reg'] == 'R84', PROD[EX[r['CodeEX']]['p']]['gamme'] == 'VTT électriques') for r in R['LOUER'])
print(f"P2 part des VTT électriques : Auvergne-Rhône-Alpes {g[(True, True)] / (g[(True, True)] + g[(True, False)]):.1%}, "
      f"ailleurs {g[(False, True)] / (g[(False, True)] + g[(False, False)]):.1%}")
du, nl, ne_ = collections.defaultdict(list), collections.Counter(), collections.Counter(v['cls'] for v in EMP.values())
for r in R['LOUER']: du[EMP[r['CodeE']]['cls']].append(r['Duree_Loc']); nl[EMP[r['CodeE']]['cls']] += 1
print("P3 durée moyenne et locations par employé selon la classe :",
      {c: (round(sum(l) / len(l), 1), round(nl[c] / ne_[c], 1)) for c, l in sorted(du.items())})
for nom in ('Seine Digital Factory', 'Provence Banque Régionale'):
    c = next(k for k, s_ in SOC.items() if s_['nom'] == nom)
    n = collections.Counter(r['DateL'].year for r in R['LOUER'] if EMP[r['CodeE']]['soc'] == c)
    print(f"P4 {nom} : locations par année {dict(sorted(n.items()))}")
for pays in ('FR', 'DE'):
    l = [r for r in R['LOUER'] if r['DateL'].year == 2026 and EMP[r['CodeE']]['pays'] == pays]
    cargo = sum(1 for r in l if PROD[EX[r['CodeEX']]['p']]['gamme'] == 'Vélos cargo')
    print(f"P5 {pays} 2026 : {len(l)} locations, durée moyenne {sum(r['Duree_Loc'] for r in l) / len(l):.1f} j, vélos cargo {cargo / len(l):.1%}")
de = collections.Counter(r['DateL'].month for r in R['LOUER'] if EMP[r['CodeE']]['pays'] == 'DE')
print("   Allemagne, locations par mois de 2026 :", dict(sorted(de.items())))

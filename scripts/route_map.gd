class_name RouteMap
extends RefCounted
## Carte de la nuit : la pyramide OutRun de 15 tronçons et 5 destinations.
##
## Étape k (0..4) compte k+1 tronçons. Après chaque station, la route se
## sépare : à gauche le tronçon du même rang, à droite celui d'à côté. Le rang
## d'un tronçon est donc le nombre de fois où l'on a pris à droite.
##
##   Étape 1                 A
##   Étape 2               B   C
##   Étape 3             D   E   F
##   Étape 4           G   H   I   J
##   Étape 5         K   L   M   N   O
##   Aube          Mer Ville Barr. Mont. Nulle-part

## Après le portique de la station, le terre-plein commence (m) et finit (m) :
## le choix se fait à son nez, la nouvelle ambiance commence à sa fin.
const DIVIDER_START := 40.0
const DIVIDER_END := 400.0
const DIVIDER_HALF_WIDTH := 0.6
## Route droite et à plat autour d'une bifurcation, pour bien la lire.
const STRAIGHT_BEFORE := 350.0

const STAGES := [
	["autoroute"],
	["foret", "port"],
	["lac", "faubourgs", "usines"],
	["cote", "periph", "vallee", "col"],
	["dunes", "centre", "retenue", "tunnels", "blanche"],
]

const ENDINGS := ["LA MER", "LA VILLE", "LE BARRAGE", "LA MONTAGNE", "NULLE PART"]

## Ambiances. lamps : écart entre lampadaires (0 = aucun) ; lamp_color :
## sodium ou LED ; trees, buildings, houses, industry : densités 0..1 ;
## water : côté de l'eau (-1 gauche, 1 droite, 0 aucune) ; tunnels : part de
## la route sous tunnel ; fog : épaisseur ; rain : 0 sec, 1 pluie, -1 neige ;
## curv, relief : virages et collines ; traffic, trucks : trafic.
const THEMES := {
	"autoroute": {"name": "L'AUTOROUTE", "lamps": 48.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.55, "ground": Color(0.07, 0.11, 0.08), "fog": 1.0, "rain": 1.0,
		"curv": 1.0, "relief": 1.0, "traffic": 1.0, "trucks": 0.2},
	"foret": {"name": "LA FORÊT", "lamps": 150.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 1.0, "ground": Color(0.05, 0.09, 0.06), "fog": 1.5, "fog_tint": Color(0.04, 0.07, 0.07),
		"rain": 1.0, "curv": 1.35, "relief": 1.3, "traffic": 0.7, "trucks": 0.15},
	"port": {"name": "LE PORT", "lamps": 40.0, "lamp_color": Color(0.75, 0.88, 1.0),
		"trees": 0.05, "industry": 1.0, "water": 1, "ground": Color(0.12, 0.12, 0.13), "fog": 1.1,
		"rain": 1.0, "curv": 0.6, "relief": 0.3, "traffic": 1.15, "trucks": 0.5},
	"lac": {"name": "LE LAC", "lamps": 64.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.45, "water": -1, "ground": Color(0.06, 0.1, 0.08), "fog": 1.3,
		"fog_tint": Color(0.07, 0.09, 0.14), "rain": 0.6, "curv": 0.9, "relief": 0.8,
		"traffic": 0.8, "trucks": 0.15},
	"faubourgs": {"name": "LES FAUBOURGS", "lamps": 36.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.3, "houses": 1.0, "ground": Color(0.08, 0.1, 0.08), "fog": 1.0, "rain": 1.0,
		"curv": 0.9, "relief": 0.5, "traffic": 1.1, "trucks": 0.15},
	"usines": {"name": "LES USINES", "lamps": 44.0, "lamp_color": Color(0.75, 0.88, 1.0),
		"trees": 0.0, "industry": 1.0, "ground": Color(0.11, 0.1, 0.1), "fog": 1.2,
		"fog_tint": Color(0.1, 0.07, 0.07), "rain": 1.0, "curv": 1.0, "relief": 0.4,
		"traffic": 1.1, "trucks": 0.45},
	"cote": {"name": "LA CÔTE", "lamps": 52.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.2, "water": 1, "ground": Color(0.09, 0.09, 0.07), "fog": 1.0, "rain": 0.5,
		"curv": 1.2, "relief": 1.4, "traffic": 0.9, "trucks": 0.15},
	"periph": {"name": "LE PÉRIPHÉRIQUE", "lamps": 30.0, "lamp_color": Color(0.75, 0.88, 1.0),
		"trees": 0.0, "buildings": 1.0, "ground": Color(0.1, 0.1, 0.11), "fog": 1.0, "rain": 1.0,
		"curv": 0.8, "relief": 0.3, "traffic": 1.3, "trucks": 0.25},
	"vallee": {"name": "LA VALLÉE", "lamps": 72.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.5, "ground": Color(0.06, 0.1, 0.07), "fog": 1.2, "rain": 0.8,
		"curv": 1.1, "relief": 2.0, "traffic": 0.9, "trucks": 0.3},
	"col": {"name": "LE COL", "lamps": 0.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.6, "snow": true, "ground": Color(0.55, 0.57, 0.62), "fog": 1.7,
		"fog_tint": Color(0.16, 0.17, 0.22), "rain": -1.0, "curv": 1.55, "relief": 2.2,
		"traffic": 0.8, "trucks": 0.2},
	"dunes": {"name": "LES DUNES", "lamps": 60.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.0, "water": 1, "ground": Color(0.32, 0.28, 0.2), "fog": 1.0, "rain": 0.3,
		"curv": 0.8, "relief": 0.7, "traffic": 0.8, "trucks": 0.1},
	"centre": {"name": "LE CENTRE", "lamps": 26.0, "lamp_color": Color(0.75, 0.88, 1.0),
		"trees": 0.0, "buildings": 1.0, "ground": Color(0.1, 0.1, 0.11), "fog": 0.9, "rain": 1.0,
		"curv": 0.7, "relief": 0.2, "traffic": 1.4, "trucks": 0.15},
	"retenue": {"name": "LA RETENUE", "lamps": 56.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.35, "water": -1, "ground": Color(0.07, 0.09, 0.08), "fog": 1.3,
		"fog_tint": Color(0.07, 0.09, 0.13), "rain": 0.6, "curv": 1.0, "relief": 1.6,
		"traffic": 0.9, "trucks": 0.3},
	"tunnels": {"name": "LES TUNNELS", "lamps": 0.0, "lamp_color": Color(1.0, 0.62, 0.28),
		"trees": 0.4, "tunnels": 0.5, "ground": Color(0.08, 0.09, 0.09), "fog": 1.2, "rain": 1.0,
		"curv": 1.2, "relief": 2.3, "traffic": 1.0, "trucks": 0.3},
	"blanche": {"name": "LA ROUTE BLANCHE", "lamps": 0.0, "lamp_color": Color(0.9, 0.95, 1.0),
		"trees": 0.15, "snow": true, "ground": Color(0.7, 0.72, 0.76), "fog": 2.2,
		"fog_tint": Color(0.55, 0.57, 0.62), "rain": 0.0, "curv": 0.5, "relief": 0.4,
		"traffic": 0.35, "trucks": 0.0},
}


## s de la bifurcation k (portique de la station k), k = 0..3.
static func fork_s(k: int) -> float:
	return RunConfig.station_s(k)


## Début de la région de l'étape k : 0 pour la première, sinon fin du
## terre-plein de la bifurcation précédente.
static func region_start(stage: int) -> float:
	return 0.0 if stage == 0 else fork_s(stage - 1) + DIVIDER_END


## Étape dont la région contient s.
static func stage_at(s: float) -> int:
	var k := 0
	while k < STAGES.size() - 1 and s >= region_start(k + 1):
		k += 1
	return k


## Rang du tronçon de l'étape `stage` selon les choix (0 gauche, 1 droite).
static func node_of(stage: int, choices: Array) -> int:
	var n := 0
	for i in mini(stage, choices.size()):
		n += int(choices[i])
	return n


static func theme_id(stage: int, choices: Array) -> String:
	return STAGES[stage][node_of(stage, choices)]


static func theme(stage: int, choices: Array) -> Dictionary:
	return THEMES[theme_id(stage, choices)]


## Valeur d'un réglage d'ambiance, avec sa valeur par défaut.
static func get_param(t: Dictionary, key: String, default: Variant = 0.0) -> Variant:
	return t.get(key, default)


## Le terre-plein de la bifurcation k est-il présent en s ?
static func divider_fork(s: float) -> int:
	for k in STAGES.size() - 1:
		var f := fork_s(k)
		if s >= f + DIVIDER_START and s < f + DIVIDER_END:
			return k
	return -1

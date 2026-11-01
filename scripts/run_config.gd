class_name RunConfig
extends RefCounted
## Réglages d'une partie (M1 : un seul chemin jusqu'à l'aube). Toutes les
## valeurs d'équilibrage sont ici ; tests/run_tests.gd vérifie qu'un bon
## pilote arrive à l'aube et qu'un pilote trop prudent n'y arrive pas.

## Longueur d'une étape (m). 5 étapes ; une station au bout des 4 premières.
const SEGMENT_LENGTH := 5200.0
const SEGMENT_COUNT := 5
## Chrono de départ (s) et temps rendu à chaque station. Calé pour qu'une
## moyenne d'environ 240 km/h suffise tout juste à atteindre l'aube : il faut
## rouler fort et éviter le trafic (chaque choc coûte 3 à 4 s). Le pilote
## automatique du banc (réflexes parfaits) arrive avec 20 à 50 s d'avance.
const START_TIME := 88.0
const STATION_TIME := [77.0, 76.0, 75.0, 74.0]
## Nombre moyen de véhicules par kilomètre, par étape.
const TRAFFIC_DENSITY := [5.0, 6.5, 8.0, 9.0, 10.0]
const DESTINATION := "La Mer"

# Score.
const POINTS_PER_METER := 1.0
const NEAR_MISS_POINTS := 500
const STATION_POINTS := 2000
const TIME_BONUS_PER_SECOND := 1000
const DRIFT_POINTS_PER_SECOND := 300
const CHAIN_STEP := 0.25          # multiplicateur gagné par maillon de chaîne
const MAX_MULTIPLIER := 5.0
const CLEAN_DISTANCE := 1000.0    # mètres sans choc = un maillon


static func station_s(index: int) -> float:
	return SEGMENT_LENGTH * (index + 1)


static func arrival_s() -> float:
	return SEGMENT_LENGTH * SEGMENT_COUNT


static func stations() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in SEGMENT_COUNT - 1:
		out.append(station_s(i))
	return out

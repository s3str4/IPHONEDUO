class_name Rivals
extends RefCounted
## Les dix-neuf autres voitures de la nuit : on part vingtième, chaque rival
## doublé fait gagner une place. Ils sont suivis tout le long, même hors de
## vue : loin du joueur, une simple avance à leur vitesse ; près de lui, ils
## entrent dans le trafic (mêmes collisions, frôlements, clignotants), avec
## leur propre allure, et en ressortent quand ils sont loin.

const COUNT := 19
## Fenêtre où un rival est un vrai véhicule du trafic.
const WINDOW_AHEAD := 460.0
const WINDOW_BEHIND := 50.0

class Rival:
	extends RefCounted
	var s := 0.0
	var pace := 60.0
	var variant := 0
	var vehicle: Traffic.Vehicle = null

var rivals: Array[Rival] = []


## Rivaux répartis devant le départ ; les plus lointains roulent moins vite :
## un bon pilote peut tous les doubler avant l'aube, pas sans effort.
func _init(seed: int, start_s: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "rivaux"])
	for i in COUNT:
		var r := Rival.new()
		r.s = start_s + 90.0 + i * 140.0 + rng.randf_range(-20.0, 20.0)
		r.pace = 66.0 - 0.35 * i + rng.randf_range(-1.5, 1.5)
		r.variant = i
		rivals.append(r)


## Place du joueur (1 = en tête).
func position(car_s: float) -> int:
	var ahead := 0
	for r in rivals:
		if r.s > car_s:
			ahead += 1
	return ahead + 1


## Avance les rivaux ; insère dans le trafic ceux qui approchent du joueur,
## reprend ceux que le trafic a retirés.
func update(car: CarPhysics, traffic: Traffic, delta: float) -> void:
	for r in rivals:
		# Allure : un peu d'élastique pour que la course reste serrée.
		var gap := r.s - car.s
		var speed := r.pace + clampf(-gap * 0.004, -3.0, 3.0)
		if r.vehicle != null:
			if r.vehicle in traffic.vehicles:
				r.s = r.vehicle.s
				r.vehicle.cruise = speed
				continue
			r.vehicle = null
		r.s += speed * delta
		gap = r.s - car.s
		if gap < WINDOW_AHEAD and gap > -WINDOW_BEHIND and _lane_free(traffic, r.s):
			var v := Traffic.Vehicle.new()
			v.kind = VehicleMesh.Kind.SPORT
			v.rival = true
			v.variant = r.variant
			v.s = r.s
			var lanes := traffic.usable_lanes(r.s)
			v.x = lanes[r.variant % lanes.size()]
			v.target_x = v.x
			v.speed = speed
			v.cruise = speed
			traffic.vehicles.append(v)
			r.vehicle = v


func _lane_free(traffic: Traffic, s: float) -> bool:
	if traffic.in_fork_zone(s):
		return false
	for v in traffic.vehicles:
		if absf(v.s - s) < 30.0:
			return false
	return true


## Prime d'arrivée selon la place.
static func position_bonus(pos: int) -> int:
	match pos:
		1:
			return 20000
		2:
			return 12000
		3:
			return 8000
	return maxi(0, (COUNT + 1 - pos) * 400)

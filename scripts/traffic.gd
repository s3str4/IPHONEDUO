class_name Traffic
extends RefCounted
## Trafic dans le sens de la marche, sur 3 voies, sans rendu : apparition
## devant le joueur, suivi et changements de voie, chocs et frôlages.

const LANES := [-4.0, 0.0, 4.0]
const SPAWN_AHEAD_MIN := 160.0   # jamais d'apparition sous le nez du joueur
const SPAWN_AHEAD_MAX := 480.0
const DESPAWN_BEHIND := 60.0
const SAME_LANE_GAP := 30.0
const LANE_CHANGE_SPEED := 1.6   # m/s latéraux
const NEAR_MISS_GAP := 1.3       # m d'espace latéral maximum pour un frôlage
const NEAR_MISS_MIN_SPEED := 10.0
const CRASH_SPEED_FACTOR := 0.7  # vitesse gardée : celle du véhicule percuté × facteur
const CRASH_COOLDOWN := 1.0
## Règle anti-mur : 3 véhicules de front à moins de WALL_SPAN m les uns des
## autres ferment la route (on ne peut plus se faufiler). Les apparitions
## gardent une marge plus large.
const WALL_SPAN := 22.0
const SPAWN_WALL_SPAN := 40.0
## Avant une bifurcation, la voie du milieu se vide sur cette longueur (m).
const FORK_CLEAR_BEFORE := 380.0


class Vehicle:
	extends RefCounted
	var s := 0.0
	var x := 0.0
	var target_x := 0.0
	var speed := 0.0
	var cruise := 0.0
	var kind := VehicleMesh.Kind.SEDAN
	var variant := 0
	var cooldown := 0.0
	## Temps restant pendant lequel le véhicule cède (règle anti-mur).
	var yield_time := 0.0
	var behind_player := false

	func half_length() -> float:
		return VehicleMesh.HALF_LENGTH[kind]

	func half_width() -> float:
		return VehicleMesh.HALF_WIDTH[kind]


var vehicles: Array[Vehicle] = []
## Voiture fantôme (événement) : roule à côté du joueur, phares éteints, sans
## collision ; hors de `vehicles` pour ne gêner ni le trafic ni ses règles.
var ghost: Vehicle
var _ghost_time := 0.0
## Véhicules par km (réglé par étape et par ambiance).
var density := 6.0
## Part de camions (réglée par ambiance).
var truck_ratio := 0.2

var _rng := RandomNumberGenerator.new()
var _next_spawn_s := 0.0


func _init(seed: int = 1) -> void:
	_rng.seed = seed * 7919 + 13
	_next_spawn_s = SPAWN_AHEAD_MIN


## Avance le trafic et gère les contacts avec la voiture du joueur.
## Renvoie les événements : [{"type": "crash"}, {"type": "near_miss"}].
func update(car: CarPhysics, delta: float) -> Array:
	_spawn(car.s)
	_drive_ghost(car, delta)
	var events := []
	for v in vehicles:
		_drive(v, car, delta)
	for v in vehicles:
		var e := _contact(v, car)
		if e != "":
			events.append({"type": e})
	vehicles = vehicles.filter(func(v: Vehicle) -> bool:
		return v.s > car.s - DESPAWN_BEHIND and not (absf(v.x) < 2.0 and RouteMap.divider_fork(v.s + v.half_length()) != -1))
	return events


## Fait apparaître la voiture fantôme à côté du joueur, dans la voie voisine.
func spawn_ghost(car: CarPhysics) -> void:
	ghost = Vehicle.new()
	ghost.kind = VehicleMesh.Kind.SPORT
	ghost.x = car.x + (4.0 if car.x < 0.0 else -4.0)
	ghost.target_x = ghost.x
	ghost.s = car.s - 20.0
	ghost.speed = car.speed + 8.0
	_ghost_time = 0.0


func _drive_ghost(car: CarPhysics, delta: float) -> void:
	if ghost == null:
		return
	_ghost_time += delta
	if _ghost_time < EventDirector.GHOST_DURATION:
		# Se cale à hauteur du joueur et y reste.
		ghost.speed = car.speed + clampf(car.s - ghost.s, -10.0, 10.0)
	else:
		ghost.speed += 12.0 * delta
	ghost.s += ghost.speed * delta
	if ghost.s > car.s + 260.0:
		ghost = null


## Voie la plus dégagée devant (pilote automatique et tests).
func best_lane(car: CarPhysics) -> float:
	var best_x: float = LANES[_nearest_lane(car.x)]
	var best_gap := -1.0
	for lane_x in usable_lanes(car.s + 60.0):
		var gap := _free_gap(car, lane_x)
		# Ne pas se jeter sur un véhicule juste à côté.
		if lane_x != LANES[_nearest_lane(car.x)] and _blocked_beside(car, lane_x):
			continue
		# Petite préférence pour la voie actuelle : pas de zigzag inutile.
		if is_equal_approx(lane_x, LANES[_nearest_lane(car.x)]):
			gap += 25.0
		if gap > best_gap:
			best_gap = gap
			best_x = lane_x
	return best_x


func _spawn(player_s: float) -> void:
	_next_spawn_s = maxf(_next_spawn_s, player_s + SPAWN_AHEAD_MIN)
	while _next_spawn_s < player_s + SPAWN_AHEAD_MAX:
		var s := _next_spawn_s
		_next_spawn_s += -log(1.0 - _rng.randf() * 0.999) * 1000.0 / maxf(density, 0.1)
		var lane := _rng.randi_range(0, LANES.size() - 1)
		# Zone de bifurcation : pas de nouveaux venus (une seule voie par côté le
		# long du terre-plein, un véhicule lent y boucherait tout).
		if in_fork_zone(s):
			continue
		var free := -1
		for k in LANES.size():
			var l := (lane + k) % LANES.size()
			if not LANES[l] in usable_lanes(s):
				continue
			if _lane_clear(LANES[l], s, SAME_LANE_GAP):
				free = l
				break
		if free == -1 or _would_wall(LANES[free], s, null, SPAWN_WALL_SPAN):
			continue
		var v := Vehicle.new()
		v.s = s
		v.x = LANES[free]
		v.target_x = v.x
		var r := _rng.randf()
		v.kind = VehicleMesh.Kind.TRUCK if r < truck_ratio else (VehicleMesh.Kind.SPORT if r > 0.88 else VehicleMesh.Kind.SEDAN)
		v.variant = _rng.randi_range(0, 3)
		v.cruise = _rng.randf_range(21.0, 25.0) if v.kind == VehicleMesh.Kind.TRUCK else _rng.randf_range(25.0, 37.0)
		v.speed = v.cruise
		vehicles.append(v)


func _drive(v: Vehicle, car: CarPhysics, delta: float) -> void:
	v.cooldown = maxf(0.0, v.cooldown - delta)
	var ahead := _vehicle_ahead(v)
	var wanted := v.cruise
	# Bifurcation devant : quitter la voie du milieu avant le terre-plein.
	if absf(v.target_x) < 1.0 and not 0.0 in usable_lanes(v.s + 60.0):
		_try_lane_change(v, car)
	if ahead != null:
		var gap := ahead.s - ahead.half_length() - (v.s + v.half_length())
		if gap < 28.0 and ahead.speed < v.speed and is_equal_approx(v.x, v.target_x):
			# Bloqué : on tente de doubler.
			_try_lane_change(v, car)
		# Toujours garder ses distances avec ce qui est devant (même en changeant de voie).
		var safe := 12.0 + maxf(0.0, v.speed - ahead.speed) * 1.2
		if gap < safe:
			wanted = minf(wanted, ahead.speed - (safe - gap) * 0.5)
	if is_equal_approx(v.x, v.target_x) and _rng.randf() < 0.025 * delta:
		_try_lane_change(v, car)
	# Trois de front : le plus en arrière cède franchement pour rouvrir une voie
	# (sinon il resterait collé à la limite du mur).
	v.yield_time = maxf(0.0, v.yield_time - delta)
	if _would_wall(v.x, v.s, v) and _is_rearmost_of_wall(v):
		v.yield_time = 3.0
	if v.yield_time > 0.0:
		wanted = minf(wanted, v.cruise - 8.0)
	# Mieux encore : ne pas venir fermer la troisième voie à côté de deux
	# véhicules déjà de front devant soi.
	var blockers_speed := _joining_wall_speed(v)
	if blockers_speed > 0.0:
		wanted = minf(wanted, blockers_speed - 1.5)
	# Céder ne descend jamais sous 60 % de l'allure de croisière ; seul le suivi
	# d'un véhicule devant (sécurité) peut ralentir davantage.
	var floor_speed := 8.0 if ahead != null and ahead.s - v.s < 30.0 else v.cruise * 0.6
	v.speed = move_toward(v.speed, maxf(wanted, floor_speed), (10.0 if wanted < v.speed else 4.0) * delta)
	v.x = move_toward(v.x, v.target_x, LANE_CHANGE_SPEED * delta)
	v.s += v.speed * delta


func _try_lane_change(v: Vehicle, car: CarPhysics) -> bool:
	var l := _nearest_lane(v.x)
	var options := []
	for d in [-1, 1]:
		if l + d >= 0 and l + d < LANES.size():
			options.append(LANES[l + d])
	if options.size() == 2 and _rng.randf() < 0.5:
		options.reverse()
	for lane_x in options:
		if not lane_x in usable_lanes(v.s) or not lane_x in usable_lanes(v.s + 80.0):
			continue
		# Pas de queue de poisson au joueur : il doit être loin derrière.
		var player_gap := v.s - car.s
		if absf(car.x - lane_x) < 3.0 and player_gap > -10.0 and player_gap < 90.0:
			continue
		# Pendant le changement, le véhicule occupe deux voies : la troisième doit
		# rester libre, sinon il ferme la route.
		if _lane_clear(lane_x, v.s, 20.0) and _third_lane_clear(v.x, lane_x, v):
			v.target_x = lane_x
			return true
	return false


func _contact(v: Vehicle, car: CarPhysics) -> String:
	var ds := v.s - car.s
	var reach_s := v.half_length() + CarPhysics.CAR_LENGTH * 0.5
	var reach_x := v.half_width() + CarPhysics.CAR_HALF_WIDTH
	var dx := car.x - v.x
	var was_behind := v.behind_player
	v.behind_player = ds < 0.0
	if absf(ds) < reach_s and absf(dx) < reach_x - 0.1:
		if v.cooldown > 0.0:
			return ""
		v.cooldown = CRASH_COOLDOWN
		var side := signf(dx) if absf(dx) > 0.05 else 1.0
		if ds > 0.0:
			# Par l'arrière : on repart à la vitesse du véhicule, écarté sur le côté.
			car.speed = minf(car.speed, v.speed * CRASH_SPEED_FACTOR)
			car.s = minf(car.s, v.s - reach_s - 0.05)
		car.lateral = side * 5.0
		car.x = clampf(v.x + side * (reach_x + 0.05), -CarPhysics.RAIL + CarPhysics.CAR_HALF_WIDTH,
				CarPhysics.RAIL - CarPhysics.CAR_HALF_WIDTH)
		return "crash"
	# Frôlage : on vient de doubler, de près, sans toucher.
	if not was_behind and v.behind_player and v.cooldown == 0.0 \
			and absf(dx) - reach_x < NEAR_MISS_GAP and car.speed - v.speed > NEAR_MISS_MIN_SPEED:
		return "near_miss"
	return ""


## Voies praticables en s : les 3, ou seulement celles de côté à l'approche
## et le long du terre-plein d'une bifurcation.
func usable_lanes(s: float) -> Array:
	return [LANES[0], LANES[2]] if in_fork_zone(s) else LANES


func in_fork_zone(s: float) -> bool:
	for k in RouteMap.STAGES.size() - 1:
		var f := RouteMap.fork_s(k)
		if s > f - FORK_CLEAR_BEFORE and s < f + RouteMap.DIVIDER_END:
			return true
	return false


## Un véhicule en (lane_x, s) fermerait-il toutes les voies praticables ?
## (`self_v` est ignoré.)
func _would_wall(lane_x: float, s: float, self_v: Vehicle, span: float = WALL_SPAN) -> bool:
	for other_lane in usable_lanes(s):
		if absf(other_lane - lane_x) < 1.0:
			continue
		var occupied := false
		for o in vehicles:
			if o != self_v and (absf(o.x - other_lane) < 2.5 or absf(o.target_x - other_lane) < 2.5) \
					and absf(o.s - s) < span:
				occupied = true
				break
		if not occupied:
			return false
	return true


func _third_lane_clear(from_x: float, to_x: float, self_v: Vehicle) -> bool:
	for lane_x in LANES:
		if absf(lane_x - from_x) < 1.0 or absf(lane_x - to_x) < 1.0:
			continue
		for o in vehicles:
			if o != self_v and (absf(o.x - lane_x) < 2.5 or absf(o.target_x - lane_x) < 2.5) \
					and absf(o.s - self_v.s) < WALL_SPAN + 10.0:
				return false
	return true


## Si v s'apprête à rattraper deux véhicules qui occupent les deux autres voies
## juste devant lui, renvoie la vitesse du plus lent des deux ; sinon 0.
func _joining_wall_speed(v: Vehicle) -> float:
	var slowest := INF
	for other_lane in usable_lanes(v.s):
		if absf(other_lane - v.x) < 1.0:
			continue
		var found := false
		for o in vehicles:
			if o != v and (absf(o.x - other_lane) < 2.5 or absf(o.target_x - other_lane) < 2.5) \
					and o.s > v.s - 5.0 and o.s < v.s + WALL_SPAN + 25.0:
				found = true
				slowest = minf(slowest, o.speed)
				break
		if not found:
			return 0.0
	return slowest


## Le véhicule est-il le plus en arrière du mur (parmi ceux des autres voies) ?
func _is_rearmost_of_wall(v: Vehicle) -> bool:
	for o in vehicles:
		if o != v and absf(o.x - v.x) > 2.0 and absf(o.s - v.s) < WALL_SPAN and o.s < v.s:
			return false
	return true


## Véhicule le plus proche devant, dans la voie actuelle ou celle visée.
func _vehicle_ahead(v: Vehicle) -> Vehicle:
	var best: Vehicle = null
	for o in vehicles:
		if o != v and o.s > v.s and (absf(o.x - v.x) < 2.5 or absf(o.x - v.target_x) < 2.5) \
				and (best == null or o.s < best.s):
			best = o
	return best


func _lane_clear(lane_x: float, s: float, gap: float) -> bool:
	for o in vehicles:
		if (absf(o.x - lane_x) < 2.5 or absf(o.target_x - lane_x) < 2.5) \
				and absf(o.s - s) < gap + o.half_length():
			return false
	return true


## Espace libre devant la voiture dans la voie lane_x (m), et vitesse du
## véhicule qui la ferme.
func free_gap(car: CarPhysics, lane_x: float) -> float:
	return _free_gap(car, lane_x)


func speed_ahead(car: CarPhysics, lane_x: float) -> float:
	var best := 999.0
	var best_s := INF
	for o in vehicles:
		if o.s > car.s and absf(o.x - lane_x) < 2.6 and o.s < best_s:
			best_s = o.s
			best = o.speed
	return best


func _free_gap(car: CarPhysics, lane_x: float) -> float:
	var gap := 400.0
	for o in vehicles:
		var ds := o.s - o.half_length() - car.s
		if ds > -2.0 and (absf(o.x - lane_x) < 2.6 or absf(o.target_x - lane_x) < 2.6):
			gap = minf(gap, ds)
	return gap


func _blocked_beside(car: CarPhysics, lane_x: float) -> bool:
	for o in vehicles:
		if absf(o.x - lane_x) < 2.8 and o.s - car.s > -o.half_length() - 4.0 and o.s - car.s < o.half_length() + 14.0:
			return true
	return false


func _nearest_lane(x: float) -> int:
	var best := 0
	for i in LANES.size():
		if absf(LANES[i] - x) < absf(LANES[best] - x):
			best = i
	return best

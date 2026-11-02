class_name Police
extends RefCounted
## La police de la nuit. Depuis que Marceau a parlé à l'antenne d'« une voiture
## rouge qui file vers l'aube », la gendarmerie écoute Radio Nuit : une
## patrouille attend au bord de la route dans chaque région après l'autoroute.
## Passer devant elle à plus de 200 km/h, c'est la réveiller.
##
## La poursuite, en coordonnées de route (s, x), sans rendu :
## - CHASE : la voiture de police remonte, de plus en plus vite d'une région à
##   l'autre (plus vite que vous, sauf sous turbo ou dans l'aspiration) ;
## - RAM : à dix mètres, elle choisit une voie et fonce pour vous percuter :
##   changer de voie au bon moment la fait passer à côté ;
## - AHEAD : si elle vous dépasse, elle se rabat devant vous et freine.
## Trois touches : arrêté (contrôle : la voiture s'arrête le temps du contrôle,
## puis repart de zéro). La semer : la distancer de 300 m, ou sortir de son secteur (la
## région suivante) ; prime et turbo plein.
##
## update() renvoie des événements : {type: "start" | "contact" | "busted" |
## "escaped", ...}.

enum State { IDLE, CHASE, RAM, AHEAD, YIELD, DONE }

const TRIGGER_SPEED := 200.0 / 3.6
## Vitesse de pointe de la police par étape (m/s) : 288 à 310 km/h, au-dessus
## des 280 km/h de la voiture (sauf améliorations, turbo, aspiration).
const TOP_SPEED := [0.0, 78.5, 80.0, 81.0, 82.0]
const ACCEL := 15.0
## Rattrapage tant qu'elle vous voit : +29 km/h au-dessus de sa pointe, jusqu'à
## 25 m de vous ; le duel se joue ensuite à sa vitesse de pointe.
const SIGHT := 200.0
const CATCH_UP := 8.0
const RAM_DISTANCE := 11.0
const RAM_TIME := 2.4
## Après une charge ratée, elle reprend ses distances avant d'en tenter une autre.
const RAM_RETRY := 2.0
## Avant de charger, elle se cale derrière vous et annonce sa voie (à l'écran :
## l'alerte rouge et bleue du rétroviseur) : de quoi esquiver.
const RAM_WINDUP := 1.1
## Le barrage roulant ne dure pas : ensuite elle s'écarte et vous laisse passer
## (sans quoi on finirait tous les deux à l'arrêt).
const AHEAD_TIME := 2.5
const ESCAPE_GAP := 300.0
const STRIKES_TO_BUST := 3
const CONTACT_COOLDOWN := 2.2
## Contrôle : la voiture reste arrêtée, la police garée derrière, gyrophares.
## C'est la punition : l'arrêt complet et le temps de repartir (≈ 8 s perdues).
const HOLD_TIME := 2.5
const PATROL_X := 10.0           # garée derrière la glissière
const HALF_LENGTH := 2.3
const HALF_WIDTH := 0.95

## Position s de la patrouille garée dans chaque étape (aucune sur l'autoroute).
var patrols := {}
var state := State.IDLE
var s := 0.0
var x := 0.0
var speed := 0.0
var stage := -1
var strikes := 0
var time := 0.0
## Voie visée pendant l'éperonnage (lisible à l'écran : le joueur peut esquiver).
var ram_x := 0.0
var escapes := 0
## Touches reçues selon la manœuvre (équilibrage, voir tools/balance.gd).
var contact_log := {}
## Contrôle en cours (s) : pas de gaz possible.
var hold := 0.0
var busts := 0
var _ram_time := 0.0
var _cooldown := 0.0
var _retry := 0.0
var _side := 1.0
var _woken := {}


func _init(seed: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "police"])
	for k in range(1, RouteMap.STAGES.size()):
		patrols[k] = RouteMap.region_start(k) + rng.randf_range(900.0, 2400.0)


## La patrouille de l'étape k a-t-elle déjà vu passer le joueur ?
func woken(k: int) -> bool:
	return _woken.has(k)


func active() -> bool:
	return state in [State.CHASE, State.RAM, State.AHEAD, State.YIELD]


## Distance de la voiture de police derrière le joueur (négative : devant).
func gap(car: CarPhysics) -> float:
	return car.s - s


## Côté de la route où la patrouille est garée (opposé à l'eau, s'il y en a).
func patrol_side(k: int, water_side: int = 0) -> float:
	return -1.0 if water_side == 1 else 1.0


func update(car: CarPhysics, traffic: Traffic, delta: float, water_side := 0) -> Array:
	var events := []
	var car_stage := RouteMap.stage_at(car.s)
	hold = maxf(0.0, hold - delta)
	if state == State.IDLE or state == State.DONE:
		# Une patrouille par étape : elle se réveille si on passe trop vite.
		if patrols.has(car_stage) and not _woken.has(car_stage):
			var p: float = patrols[car_stage]
			if car.s > p and car.s < p + 40.0:
				_woken[car_stage] = true
				if car.speed > TRIGGER_SPEED:
					_start(car_stage, p, water_side)
					events.append({"type": "start"})
		return events

	time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_retry = maxf(0.0, _retry - delta)
	# Hors de son secteur, elle abandonne.
	if car_stage != stage:
		return _escape(events, "secteur")
	var g := gap(car)
	if g > ESCAPE_GAP:
		return _escape(events, "distance")
	var top: float = TOP_SPEED[stage]

	var target_speed := top
	var target_x := x
	match state:
		State.CHASE:
			# Encore en vue (moins de 200 m) : elle met tout pour revenir au contact.
			var reach := top + (CATCH_UP if g > 25.0 and g < SIGHT else 0.0)
			target_speed = minf(reach, car.speed + clampf(g * 0.25, 3.0, 25.0))
			# Pas le droit de charger maintenant : elle reste à distance, sans coller.
			var can_ram := g > HALF_LENGTH * 2.5 and _cooldown == 0.0 and _retry == 0.0 and speed > 40.0
			if g < RAM_DISTANCE + 6.0 and g > 0.0 and not can_ram:
				target_speed = minf(target_speed, car.speed - 1.0)
			# Elle prend votre voie de derrière ; à votre hauteur, elle garde la sienne.
			if g > HALF_LENGTH * 2.5:
				target_x = _lane_of(car.x)
			elif g < -HALF_LENGTH * 2.0:
				state = State.AHEAD
				_ram_time = 0.0
			# Charger seulement de derrière (pas en coup de côté), et pas juste après une charge.
			if g < RAM_DISTANCE and can_ram:
				state = State.RAM
				_ram_time = 0.0
				ram_x = car.x
		State.RAM:
			_ram_time += delta
			target_speed = car.speed if _ram_time < RAM_WINDUP else minf(top + 4.0, car.speed + 6.0)
			target_x = ram_x
			if _ram_time > RAM_TIME or g < -HALF_LENGTH * 2.0:
				state = State.AHEAD if g < 0.0 else State.CHASE
				_ram_time = 0.0
				_retry = RAM_RETRY
		State.AHEAD:
			# Devant : elle se rabat dans votre voie et freine.
			_ram_time += delta
			target_speed = maxf(car.speed - 4.0, 45.0)
			# Se rabattre seulement avec de la marge devant vous.
			if g < -HALF_LENGTH * 4.0:
				target_x = car.x
			if g > HALF_LENGTH * 2.5:
				state = State.CHASE
			elif _ram_time > AHEAD_TIME:
				state = State.YIELD
		State.YIELD:
			# Elle se range dans la voie la plus loin de vous et ralentit.
			target_speed = car.speed * 0.8
			# À votre hauteur, elle ne traverse pas votre voie.
			if absf(g) > HALF_LENGTH * 3.0 or absf(x - car.x) > 3.0:
				target_x = Traffic.LANES[0] if car.x > 0.0 else Traffic.LANES[2]
			if g > HALF_LENGTH * 2.5:
				state = State.CHASE
	if _cooldown > 0.0:
		target_speed = minf(target_speed, car.speed * 0.9)
	# Ne pas traverser le trafic : changer de voie, ou ralentir derrière.
	var blocker := _blocker(traffic, target_x)
	if blocker != null:
		var free := _free_lane(traffic, car)
		if free != INF:
			target_x = free
		else:
			target_speed = minf(target_speed, blocker.speed)
	var accel := ACCEL if target_speed > speed else ACCEL * 1.6
	speed = move_toward(speed, maxf(target_speed, 0.0), accel * delta)
	var lateral := 7.0 if state == State.RAM else 4.5
	x = move_toward(x, target_x, lateral * delta)
	x = clampf(x, -CarPhysics.ROAD_HALF_WIDTH + 1.0, CarPhysics.ROAD_HALF_WIDTH - 1.0) if absf(x) < 7.0 else x
	_divider(car)
	s += speed * delta

	var _contact_state := state
	# Contact : une touche, la voiture ralentit, la police recule un instant.
	# En simple chasse (vous avez freiné ou percuté quelqu'un devant elle), elle
	# pile derrière vous au lieu de vous emboutir : seules ses manœuvres comptent.
	if state == State.CHASE and car.s > s and car.s - s < HALF_LENGTH + CarPhysics.CAR_LENGTH * 0.5 + 0.3 \
			and absf(car.x - x) < HALF_WIDTH + CarPhysics.CAR_HALF_WIDTH:
		s = car.s - HALF_LENGTH - CarPhysics.CAR_LENGTH * 0.5 - 0.3
		speed = minf(speed, car.speed)
	# Quand elle s'écarte pour vous laisser passer, elle ne compte pas de touche.
	if _cooldown == 0.0 and state != State.YIELD and absf(car.s - s) < HALF_LENGTH + CarPhysics.CAR_LENGTH * 0.5 \
			and absf(car.x - x) < HALF_WIDTH + CarPhysics.CAR_HALF_WIDTH - 0.1:
		strikes += 1
		var key: String = State.keys()[_contact_state] + ("_behind" if car.s > s else "_ahead")
		contact_log[key] = contact_log.get(key, 0) + 1
		_cooldown = CONTACT_COOLDOWN
		var side := signf(car.x - x) if absf(car.x - x) > 0.05 else 1.0
		car.lateral = side * 5.0
		if car.s > s:
			car.speed *= 0.86
		else:
			car.speed = minf(car.speed, speed * 0.85)
		speed *= 0.8
		state = State.CHASE
		events.append({"type": "contact", "strikes": strikes, "from": State.keys()[_contact_state], "behind": car.s > s})
		if strikes >= STRIKES_TO_BUST:
			busts += 1
			state = State.DONE
			car.speed = 0.0
			hold = HOLD_TIME
			speed = 0.0
			s = car.s - 7.0
			events.append({"type": "busted"})
	return events


func _start(k: int, p: float, water_side: int) -> void:
	state = State.CHASE
	stage = k
	s = p
	_side = patrol_side(k, water_side)
	x = _side * PATROL_X
	speed = 0.0
	strikes = 0
	time = 0.0
	_cooldown = 0.0


func _escape(events: Array, why: String) -> Array:
	state = State.DONE
	escapes += 1
	events.append({"type": "escaped", "why": why, "time": time})
	return events


## Effet d'un événement sur la partie (le même en jeu et en simulation) :
## une touche casse la chaîne, semer la police
## rapporte une prime et remplit le turbo.
func apply(e: Dictionary, game: GameRun) -> void:
	match e.type:
		"contact":
			game.on_crash(s)
		"escaped":
			game.score += escape_points(stage, e.time)
			game.charge_turbo(1.0)
	game.pursuit = active()


## Prime d'évasion : plus la poursuite a été longue et l'étape dure, plus elle paie.
static func escape_points(stage_k: int, seconds: float) -> int:
	return 1500 * stage_k + int(seconds * 60.0)


func _lane_of(car_x: float) -> float:
	var best: float = Traffic.LANES[0]
	for l in Traffic.LANES:
		if absf(l - car_x) < absf(best - car_x):
			best = l
	return best


func _blocker(traffic: Traffic, lane_x: float) -> Traffic.Vehicle:
	for v in traffic.vehicles:
		if v.s > s - HALF_LENGTH and v.s < s + 26.0 and absf(v.x - lane_x) < 2.2:
			return v
	return null


func _free_lane(traffic: Traffic, car: CarPhysics) -> float:
	var best := INF
	for l in traffic.usable_lanes(s + 40.0):
		var clear := true
		for v in traffic.vehicles:
			if v.s > s - 8.0 and v.s < s + 30.0 and absf(v.x - l) < 2.4:
				clear = false
				break
		if clear and (best == INF or absf(l - car.x) < absf(best - car.x)):
			best = l
	return best


## Terre-plein des bifurcations : la police reste du côté du joueur.
func _divider(car: CarPhysics) -> void:
	if RouteMap.divider_fork(s) == -1:
		return
	var inner := RouteMap.DIVIDER_HALF_WIDTH + HALF_WIDTH + 0.1
	var side := signf(car.x) if car.x != 0.0 else 1.0
	if x * side < inner:
		x = side * inner

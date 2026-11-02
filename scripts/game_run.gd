class_name GameRun
extends RefCounted
## Règles d'une partie, sans rendu : chrono, stations, bifurcations, score,
## chaîne, événements vus, arrivée à l'aube et sa destination. main.gd
## l'alimente à chaque image et affiche ses signaux.

enum State { WAITING, RUNNING, ARRIVED, TIME_UP }

signal station_reached(index: int, time_added: float)
signal near_miss(points: int)
signal chain_broken
signal arrived(time_bonus: int)
signal time_up
signal fork_taken(index: int, side: int)
signal region_entered(stage: int, theme_id: String)
signal turbo_ready
signal turbo_fired

## Bonus de score selon la destination : les routes de droite sont plus dures.
const ENDING_BONUS := [0, 5000, 10000, 15000, 25000]

var state := State.WAITING
var time_left := RunConfig.START_TIME
var score := 0.0
var chain := 0
var next_station := 0
var near_misses := 0
var crashes := 0
var elapsed := 0.0
var time_bonus := 0
## Choix aux bifurcations (0 gauche, 1 droite).
var choices: Array[int] = []
## Événements étranges vus pendant la nuit (nom -> vrai).
var flags := {}
## Destination atteinte (indice dans RouteMap.ENDINGS), -1 avant l'aube.
var ending := -1
## Le chrono est suspendu (tunnel trop long).
var clock_frozen := false
## Jauge du turbo (0..1) et temps de turbo restant (s).
var turbo := 0.0
var turbo_left := 0.0
var turbos_fired := 0
## Améliorations du garage : vitesse de charge et durée du turbo.
var turbo_gain := 1.0
var turbo_duration := RunConfig.TURBO_DURATION

var _clean_from := 0.0
var _last_s := 0.0


func start(s: float = 0.0) -> void:
	state = State.RUNNING
	_last_s = s
	_clean_from = s
	next_station = 0
	while next_station < RunConfig.SEGMENT_COUNT - 1 and RunConfig.station_s(next_station) <= s:
		next_station += 1


func multiplier() -> float:
	return minf(1.0 + chain * RunConfig.CHAIN_STEP, RunConfig.MAX_MULTIPLIER)


## Étape en cours (0..SEGMENT_COUNT-1).
func segment() -> int:
	return mini(int(_last_s / RunConfig.SEGMENT_LENGTH), RunConfig.SEGMENT_COUNT - 1)


## Avancement vers l'aube (0..1).
func progress() -> float:
	return clampf(_last_s / RunConfig.arrival_s(), 0.0, 1.0)


func update(s: float, x: float, drifting: bool, delta: float) -> void:
	if state != State.RUNNING:
		_last_s = s
		return
	var prev_s := _last_s
	elapsed += delta
	var travelled := maxf(0.0, s - _last_s)
	score += travelled * RunConfig.POINTS_PER_METER * multiplier()
	if drifting:
		score += RunConfig.DRIFT_POINTS_PER_SECOND * delta * multiplier()
		charge_turbo(RunConfig.TURBO_PER_DRIFT_SECOND * delta)
	turbo_left = maxf(0.0, turbo_left - delta)
	_last_s = s

	if s - _clean_from >= RunConfig.CLEAN_DISTANCE:
		_clean_from = s
		chain += 1
		charge_turbo(RunConfig.TURBO_PER_CHAIN)

	while next_station < RunConfig.SEGMENT_COUNT - 1 and s >= RunConfig.station_s(next_station):
		var added: float = RunConfig.STATION_TIME[next_station]
		time_left += added
		score += RunConfig.STATION_POINTS * (next_station + 1)
		station_reached.emit(next_station, added)
		next_station += 1

	# Bifurcation : le côté où l'on est au nez du terre-plein décide.
	while choices.size() < RouteMap.STAGES.size() - 1 \
			and s >= RouteMap.fork_s(choices.size()) + RouteMap.DIVIDER_START:
		var side := 1 if x > 0.0 else 0
		choices.append(side)
		fork_taken.emit(choices.size() - 1, side)
	for k in range(1, RouteMap.STAGES.size()):
		var r := RouteMap.region_start(k)
		if prev_s < r and s >= r:
			region_entered.emit(k, RouteMap.theme_id(k, choices))

	if s >= RunConfig.arrival_s():
		state = State.ARRIVED
		ending = RouteMap.node_of(RouteMap.STAGES.size() - 1, choices)
		time_bonus = int(ceil(time_left)) * RunConfig.TIME_BONUS_PER_SECOND
		score += time_bonus + ENDING_BONUS[ending]
		arrived.emit(time_bonus)
		return

	if not clock_frozen:
		time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.TIME_UP
		time_up.emit()


func charge_turbo(amount: float) -> void:
	if state != State.RUNNING or turbo >= 1.0:
		return
	turbo = minf(1.0, turbo + amount * turbo_gain)
	if turbo >= 1.0:
		turbo_ready.emit()


## Aspiration derrière un véhicule : charge le turbo.
func on_draft(delta: float) -> void:
	charge_turbo(RunConfig.TURBO_PER_DRAFT_SECOND * delta)


## Déclenche le turbo si la jauge est pleine.
func fire_turbo() -> bool:
	if state != State.RUNNING or turbo < 1.0:
		return false
	turbo = 0.0
	turbo_left = turbo_duration
	turbos_fired += 1
	turbo_fired.emit()
	return true


func is_boosting() -> bool:
	return turbo_left > 0.0


func set_flag(name: String) -> void:
	flags[name] = true


func on_near_miss() -> void:
	if state != State.RUNNING:
		return
	near_misses += 1
	chain += 1
	charge_turbo(RunConfig.TURBO_PER_NEAR_MISS)
	var pts := int(RunConfig.NEAR_MISS_POINTS * multiplier())
	score += pts
	near_miss.emit(pts)


## Choc (trafic ou glissière) : la chaîne repart de zéro.
func on_crash(s: float) -> void:
	if state != State.RUNNING:
		return
	crashes += 1
	_clean_from = s
	if chain > 0:
		chain = 0
		chain_broken.emit()

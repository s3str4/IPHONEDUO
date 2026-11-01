class_name GameRun
extends RefCounted
## Règles d'une partie, sans rendu : chrono, stations, score, chaîne,
## arrivée à l'aube. main.gd l'alimente à chaque image et affiche ses signaux.

enum State { WAITING, RUNNING, ARRIVED, TIME_UP }

signal station_reached(index: int, time_added: float)
signal near_miss(points: int)
signal chain_broken
signal arrived(time_bonus: int)
signal time_up

var state := State.WAITING
var time_left := RunConfig.START_TIME
var score := 0.0
var chain := 0
var next_station := 0
var near_misses := 0
var crashes := 0
var elapsed := 0.0
var time_bonus := 0

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


func update(s: float, drifting: bool, delta: float) -> void:
	if state != State.RUNNING:
		_last_s = s
		return
	elapsed += delta
	var travelled := maxf(0.0, s - _last_s)
	score += travelled * RunConfig.POINTS_PER_METER * multiplier()
	if drifting:
		score += RunConfig.DRIFT_POINTS_PER_SECOND * delta * multiplier()
	_last_s = s

	if s - _clean_from >= RunConfig.CLEAN_DISTANCE:
		_clean_from = s
		chain += 1

	while next_station < RunConfig.SEGMENT_COUNT - 1 and s >= RunConfig.station_s(next_station):
		var added: float = RunConfig.STATION_TIME[next_station]
		time_left += added
		score += RunConfig.STATION_POINTS * (next_station + 1)
		station_reached.emit(next_station, added)
		next_station += 1

	if s >= RunConfig.arrival_s():
		state = State.ARRIVED
		time_bonus = int(ceil(time_left)) * RunConfig.TIME_BONUS_PER_SECOND
		score += time_bonus
		arrived.emit(time_bonus)
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.TIME_UP
		time_up.emit()


func on_near_miss() -> void:
	if state != State.RUNNING:
		return
	near_misses += 1
	chain += 1
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

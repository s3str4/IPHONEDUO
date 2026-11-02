class_name Ghost
extends RefCounted
## Le fantôme du record : la meilleure partie sur cette route (même graine :
## la route normale, ou la nuit du jour), notée dix fois par seconde. La
## partie suivante, une voiture hologramme refait ce trajet et l'écran donne
## l'écart en direct. Sans collision. S'il a pris une autre route à une
## bifurcation, il disparaît après le terre-plein.

const STEP := 0.1                 # s entre deux points
const VERSION := 1

var seed := 1
var score := 0
## Choix aux bifurcations (0 gauche, 1 droite), dans l'ordre.
var choices: Array = []
## Positions s et x à chaque pas de temps.
var s_track := PackedFloat32Array()
var x_track := PackedFloat32Array()
var _next_t := 0.0
## Dernière image reçue : [t, s, x].
var _last := Vector3.ZERO


func _init(p_seed: int = 1) -> void:
	seed = p_seed


## Enregistrement : à appeler à chaque pas de physique pendant la course.
func record(t: float, s: float, x: float) -> void:
	# Position exacte à chaque dixième de seconde, interpolée entre deux images.
	while t >= _next_t:
		var k := 1.0 if t <= _last.x else clampf((_next_t - _last.x) / (t - _last.x), 0.0, 1.0)
		s_track.append(lerpf(_last.y, s, k) if not s_track.is_empty() or _last.x > 0.0 else s)
		x_track.append(lerpf(_last.z, x, k) if not x_track.is_empty() or _last.x > 0.0 else x)
		_next_t += STEP
	_last = Vector3(t, s, x)


func duration() -> float:
	return maxf(0.0, (s_track.size() - 1) * STEP)


func is_empty() -> bool:
	return s_track.size() < 2


## Position [s, x] à l'instant t de la course (interpolée).
func at(t: float) -> Vector2:
	if is_empty():
		return Vector2.ZERO
	var f := clampf(t / STEP, 0.0, s_track.size() - 1.0001)
	var i := int(f)
	var k := f - i
	return Vector2(lerpf(s_track[i], s_track[i + 1], k), lerpf(x_track[i], x_track[i + 1], k))


## Instant où le fantôme est passé en s (INF s'il n'y est jamais arrivé).
func time_at(s: float) -> float:
	if is_empty() or s > s_track[s_track.size() - 1]:
		return INF
	var lo := 0
	var hi := s_track.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if s_track[mid] < s:
			lo = mid
		else:
			hi = mid
	var span := s_track[hi] - s_track[lo]
	var k := 0.0 if span <= 0.0 else (s - s_track[lo]) / span
	return (lo + clampf(k, 0.0, 1.0)) * STEP


## Le fantôme suit-il la même route que le joueur jusqu'ici ?
func same_route(player_choices: Array) -> bool:
	for i in mini(player_choices.size(), choices.size()):
		if player_choices[i] != choices[i]:
			return false
	return true


static func path_for(p_seed: int) -> String:
	return "user://ghost_%d.save" % p_seed


func write(path: String = "") -> void:
	var f := FileAccess.open(path if path != "" else path_for(seed), FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"v": VERSION, "seed": seed, "score": score, "choices": choices,
			"s": s_track, "x": x_track})


static func load_for(p_seed: int, path: String = "") -> Ghost:
	var f := FileAccess.open(path if path != "" else path_for(p_seed), FileAccess.READ)
	if f == null:
		return null
	var d = f.get_var()
	if not d is Dictionary or int(d.get("v", 0)) != VERSION or int(d.get("seed", -1)) != p_seed:
		return null
	var g := Ghost.new(p_seed)
	g.score = int(d["score"])
	g.choices = d["choices"]
	g.s_track = d["s"]
	g.x_track = d["x"]
	return g if not g.is_empty() else null

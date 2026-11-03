class_name Pickups
extends RefCounted
## Ce qu'on ramasse sur la route, façon arcade : des jetons néon en lignes et
## en serpentins (des points, et une raison de changer de voie au milieu du
## trafic), et de rares bonus de temps (+2 s), souvent mal placés exprès.
## Ramasser tous les jetons d'une étape rapporte une prime. Tout est tiré
## d'avance, au hasard mais toujours pareil pour une graine donnée.

enum Kind { TOKEN, TIME }

const TOKEN_POINTS := 150
const TIME_BONUS := 2.0
const PERFECT_POINTS := 5000
const REACH_S := 2.6
const REACH_X := 1.5
## Pas de ramassage près des bifurcations (on y choisit sa route).
const FORK_MARGIN := 420.0

class Item:
	extends RefCounted
	var s := 0.0
	var x := 0.0
	var kind := Kind.TOKEN
	var stage := 0
	var taken := false

## Tous les objets, triés par s.
var items: Array[Item] = []
## Jetons par étape : [total, ramassés].
var tokens := {}
var _next := 0


func _init(seed: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "jetons"])
	var end := RunConfig.arrival_s() - 150.0
	var s := 260.0
	while s < end:
		if _near_fork(s) or _near_fork(s + 120.0):
			s += 60.0
			continue
		var stage := RouteMap.stage_at(s)
		var lanes: Array = Traffic.LANES
		var pattern := rng.randi_range(0, 2)
		var lane: int = rng.randi_range(0, 2)
		var count := rng.randi_range(6, 9)
		for i in count:
			var x: float = lanes[lane]
			if pattern == 1:
				# Serpentin : d'une voie à l'autre.
				x = lerpf(lanes[0], lanes[2], 0.5 + 0.5 * sin(i * 0.7 + rng.randf() * 0.01))
			elif pattern == 2 and i == count / 2:
				lane = clampi(lane + (1 if rng.randf() < 0.5 else -1), 0, 2)
			_add(s + i * 11.0, x, Kind.TOKEN, stage)
		s += count * 11.0
		# Un bonus de temps de temps en temps, dans une autre voie que les jetons.
		if rng.randf() < 0.22:
			var other: float = lanes[(lane + rng.randi_range(1, 2)) % 3]
			_add(s + rng.randf_range(40.0, 90.0), other, Kind.TIME, stage)
		s += rng.randf_range(220.0, 420.0)
	items.sort_custom(func(a: Item, b: Item) -> bool: return a.s < b.s)


func _add(s: float, x: float, kind: Kind, stage: int) -> void:
	var it := Item.new()
	it.s = s
	it.x = x
	it.kind = kind
	it.stage = stage
	items.append(it)
	if kind == Kind.TOKEN:
		var t: Array = tokens.get(stage, [0, 0])
		t[0] += 1
		tokens[stage] = t


static func _near_fork(s: float) -> bool:
	for k in RouteMap.STAGES.size() - 1:
		var f := RouteMap.fork_s(k)
		if s > f - FORK_MARGIN and s < f + RouteMap.DIVIDER_END + 40.0:
			return true
	return false


## Ramasse ce que la voiture touche. Renvoie les objets pris à cette image.
func update(car: CarPhysics) -> Array:
	var got := []
	while _next < items.size() and items[_next].s < car.s - REACH_S:
		_next += 1
	var i := _next
	while i < items.size() and items[i].s < car.s + REACH_S:
		var it := items[i]
		if not it.taken and absf(it.x - car.x) < REACH_X:
			it.taken = true
			got.append(it)
			if it.kind == Kind.TOKEN:
				tokens[it.stage][1] += 1
		i += 1
	return got


## Effet sur la partie ; renvoie vrai si l'étape est devenue parfaite.
func apply(it: Item, game: GameRun) -> bool:
	if it.kind == Kind.TIME:
		game.time_left += TIME_BONUS
		return false
	game.score += TOKEN_POINTS * game.multiplier()
	game.charge_turbo(0.04)
	var t: Array = tokens[it.stage]
	if t[1] == t[0]:
		game.score += PERFECT_POINTS
		return true
	return false


## Les objets à afficher entre s0 et s1.
func visible_between(s0: float, s1: float) -> Array:
	var out := []
	var i := _next
	while i < items.size() and items[i].s < s1:
		if items[i].s > s0 and not items[i].taken:
			out.append(items[i])
		i += 1
	return out

extends SceneTree
## Équilibrage : simule des parties et affiche temps restant, score, chocs.
## Le bon pilote vise chacune des 5 destinations ; le prudent (215 km/h) et
## celui qui ignore le trafic suivent le chemin le plus facile.
##   godot --headless --path . --script res://tools/balance.gd

const SEEDS := 6


func _initialize() -> void:
	for ending in RouteMap.ENDINGS.size():
		_report("BON → %s" % RouteMap.ENDINGS[ending], Sim.Driver.GOOD, path_to(ending))
	_report("PRUDENT", Sim.Driver.CAUTIOUS, path_to(0))
	_report("AVEUGLE", Sim.Driver.BLIND, path_to(0))
	quit()


## Chemin type vers une destination : d'abord à droite, puis à gauche.
static func path_to(ending: int) -> Array:
	var p := []
	for k in RouteMap.STAGES.size() - 1:
		p.append(1 if k < ending else 0)
	return p


func _report(name: String, driver: Sim.Driver, path: Array) -> void:
	var arrivals := 0
	var margins := []
	for seed in range(1, SEEDS + 1):
		var r := Sim.run(seed, driver, path)
		var g: GameRun = r.game
		print("%-18s graine %d : %-8s étape %d  temps %5.1f s  durée %5.1f s  moy %3d km/h  score %7d  frôlages %2d  turbos %d  trafic %2d  chocs %2d" % [
			name, seed, GameRun.State.keys()[g.state], g.segment() + 1, g.time_left, g.elapsed,
			int(r.car.s / maxf(g.elapsed, 1.0) * 3.6), int(g.score), g.near_misses, g.turbos_fired, r.traffic_crashes, r.car.rail_hits])
		if g.state == GameRun.State.ARRIVED:
			arrivals += 1
			margins.append(g.time_left)
	margins.sort()
	print("%s : %d / %d à l'aube%s\n" % [name, arrivals, SEEDS,
			"" if margins.is_empty() else ", marge %.0f à %.0f s" % [margins[0], margins[-1]]])

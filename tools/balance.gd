extends SceneTree
## Équilibrage : simule des parties pour chaque type de pilote et affiche
## temps restant, score, chocs. godot --headless --path . --script res://tools/balance.gd


func _initialize() -> void:
	for driver in [Sim.Driver.GOOD, Sim.Driver.CAUTIOUS, Sim.Driver.BLIND]:
		var name: String = Sim.Driver.keys()[driver]
		var arrivals := 0
		for seed in range(1, 13):
			var r := Sim.run(seed, driver)
			var g: GameRun = r.game
			print("%-8s graine %d : %-8s étape %d  temps %5.1f s  durée %5.1f s  moy %3d km/h  score %7d  frôlages %3d  trafic %2d  glissière %2d" % [
				name, seed, GameRun.State.keys()[g.state], g.segment() + 1, g.time_left, g.elapsed, int(r.car.s / maxf(g.elapsed, 1.0) * 3.6),
				int(g.score), g.near_misses, r.traffic_crashes, r.car.rail_hits])
			if g.state == GameRun.State.ARRIVED:
				arrivals += 1
		print("%s : %d / 12 à l'aube\n" % [name, arrivals])
	quit()

class_name Autopilot
extends RefCounted
## Pilote automatique : démos du jeu, simulations d'équilibrage et tests.
## Suit un chemin dans la pyramide (0 gauche, 1 droite à chaque bifurcation).

enum Driver { GOOD, CAUTIOUS, BLIND }


## Renvoie [gaz, braquage, turbo] pour cette image (turbo : vrai pour le
## déclencher, en ligne droite dégagée et loin des bifurcations).
static func drive(car: CarPhysics, track: Track, traffic: Traffic, path: Array, driver: Driver,
		police: Police = null) -> Array:
	var target := 0.0
	if driver != Driver.BLIND:
		target = traffic.best_lane(car)
	# Un bon pilote esquive la police : quitter la voie qu'elle vise, ou celle
	# où elle s'est rabattue devant.
	if driver == Driver.GOOD and police != null and police.active():
		var g := police.gap(car)
		var danger := police.ram_x if police.state == Police.State.RAM else police.x
		# Elle charge, elle bloque devant, ou elle est juste à côté : pas dans sa voie.
		var threat := police.state in [Police.State.RAM, Police.State.AHEAD] and g > -40.0 and g < 16.0 \
				or absf(g) < 7.0
		if threat and absf(danger - target) < 2.5:
			var best := target
			var best_d := -1.0
			for l in traffic.usable_lanes(car.s + 30.0):
				var d := absf(l - danger)
				if d > 2.5 and traffic.free_gap(car, l) > 40.0 and not traffic._blocked_beside(car, l) and d > best_d:
					best = l
					best_d = d
			target = best
	# Bifurcation devant : se placer du côté du chemin voulu.
	for k in RouteMap.STAGES.size() - 1:
		var f := RouteMap.fork_s(k)
		if car.s > f + RouteMap.DIVIDER_START - 200.0 and car.s < f + RouteMap.DIVIDER_END:
			var side: int = path[k] if k < path.size() else 0
			target = Traffic.LANES[2] if side == 1 else Traffic.LANES[0]
	var throttle := 1.0
	if driver == Driver.CAUTIOUS and car.speed_kmh() > 215.0:
		throttle = 0.0
	# Un bon pilote lève le pied quand sa voie est bouchée de près.
	if driver != Driver.BLIND and traffic.free_gap(car, car.x) < 12.0 \
			+ maxf(0.0, car.speed - traffic.speed_ahead(car, car.x)) * 0.45:
		throttle = 0.0
	var turbo := driver == Driver.GOOD and traffic.free_gap(car, car.x) > 160.0 \
			and absf(track.curvature_at(car.s + 80.0)) < 0.004 and not traffic.in_fork_zone(car.s + 150.0)
	return [throttle, car.autopilot_steer(track, target), turbo]

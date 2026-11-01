class_name Autopilot
extends RefCounted
## Pilote automatique : démos du jeu, simulations d'équilibrage et tests.
## Suit un chemin dans la pyramide (0 gauche, 1 droite à chaque bifurcation).

enum Driver { GOOD, CAUTIOUS, BLIND }


## Renvoie [gaz, braquage] pour cette image.
static func drive(car: CarPhysics, track: Track, traffic: Traffic, path: Array, driver: Driver) -> Array:
	var target := 0.0
	if driver != Driver.BLIND:
		target = traffic.best_lane(car)
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
	return [throttle, car.autopilot_steer(track, target)]

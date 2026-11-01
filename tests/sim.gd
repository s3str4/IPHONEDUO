class_name Sim
extends RefCounted
## Simulation d'une partie complète sans rendu, avec différents pilotes.
## Sert au banc d'essai et à l'équilibrage (tools/balance.gd).

enum Driver { GOOD, CAUTIOUS, BLIND }


## Renvoie {"game": GameRun, "car": CarPhysics, "traffic_crashes": int}.
static func run(seed: int, driver: Driver, dt: float = 1.0 / 60.0) -> Dictionary:
	var track := Track.new(seed)
	var car := CarPhysics.new()
	var traffic := Traffic.new(seed)
	var game := GameRun.new()
	game.start(0.0)
	var limit := 60.0 * 20.0
	var t := 0.0
	var traffic_crashes := 0
	while game.state == GameRun.State.RUNNING and t < limit:
		traffic.density = RunConfig.TRAFFIC_DENSITY[game.segment()]
		var target := 0.0
		if driver != Driver.BLIND:
			target = traffic.best_lane(car)
		var throttle := 1.0
		if driver == Driver.CAUTIOUS and car.speed_kmh() > 215.0:
			throttle = 0.0
		# Un bon pilote lève le pied quand sa voie est bouchée de près.
		if driver != Driver.BLIND and traffic.free_gap(car, car.x) < 12.0 + maxf(0.0, car.speed - traffic.speed_ahead(car, car.x)) * 0.45:
			throttle = 0.0
		car.step(track, throttle, car.autopilot_steer(track, target), dt)
		if car.hit_rail:
			game.on_crash(car.s)
		for e in traffic.update(car, dt):
			if e.type == "crash":
				traffic_crashes += 1
				game.on_crash(car.s)
			else:
				game.on_near_miss()
		game.update(car.s, absf(car.slip) > 0.12 and car.speed > 45.0, dt)
		track.ensure(car.s + 600.0)
		track.trim(car.s - 300.0)
		t += dt
	return {"game": game, "car": car, "traffic_crashes": traffic_crashes}

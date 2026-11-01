class_name Sim
extends RefCounted
## Simulation d'une partie complète sans rendu, avec différents pilotes et
## chemins. Sert au banc d'essai et à l'équilibrage (tools/balance.gd).

const Driver := Autopilot.Driver


## Renvoie {"game": GameRun, "car": CarPhysics, "traffic_crashes": int}.
static func run(seed: int, driver: Autopilot.Driver, path: Array = [0, 0, 0, 0],
		dt: float = 1.0 / 60.0) -> Dictionary:
	var track := Track.new(seed, true)
	var car := CarPhysics.new()
	var traffic := Traffic.new(seed)
	var game := GameRun.new()
	game.start(0.0)
	var limit := 60.0 * 20.0
	var t := 0.0
	var traffic_crashes := 0
	while game.state == GameRun.State.RUNNING and t < limit:
		var th := RouteMap.theme(RouteMap.stage_at(car.s), game.choices)
		traffic.density = RunConfig.TRAFFIC_DENSITY[game.segment()] * th.get("traffic", 1.0)
		traffic.truck_ratio = th.get("trucks", 0.2)
		var cmd := Autopilot.drive(car, track, traffic, path, driver)
		car.step(track, cmd[0], cmd[1], dt)
		if car.hit_rail:
			game.on_crash(car.s)
		for e in traffic.update(car, dt):
			if e.type == "crash":
				traffic_crashes += 1
				game.on_crash(car.s)
			else:
				game.on_near_miss()
		game.update(car.s, car.x, absf(car.slip) > 0.12 and car.speed > 45.0, dt)
		track.choices.assign(game.choices)
		track.ensure(car.s + 600.0)
		track.trim(car.s - 300.0)
		t += dt
	return {"game": game, "car": car, "traffic_crashes": traffic_crashes}

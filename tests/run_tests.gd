extends SceneTree
## Banc d'essai headless du prototype :
##   godot --headless --path . --script res://tests/run_tests.gd
## Code de sortie 0 si tout passe, 1 sinon.

var _failures := 0


func _initialize() -> void:
	_test_track_is_continuous()
	_test_track_is_deterministic()
	_test_track_trim_keeps_sampling()
	_test_autopilot_drives_clean()
	_test_curves_need_steering()
	_test_lifting_thumb_brakes()
	_test_chunks_are_valid()
	_test_run_rules()
	_test_traffic_rules()
	_test_balance()
	await _test_thumb_input()
	print("\n%s" % ("TOUT PASSE" if _failures == 0 else "%d ÉCHEC(S)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("  ok    %s" % name)
	else:
		_failures += 1
		print("  ÉCHEC %s %s" % [name, detail])


func _test_track_is_continuous() -> void:
	var t := Track.new(3)
	t.ensure(20000.0)
	var worst_gap := 0.0
	var worst_turn := 0.0
	var worst_curv := 0.0
	var s := Track.STEP
	while s < 20000.0:
		var gap := t.point_at(s).distance_to(t.point_at(s - Track.STEP))
		worst_gap = maxf(worst_gap, absf(gap - Track.STEP))
		worst_turn = maxf(worst_turn, absf(t.yaw_at(s) - t.yaw_at(s - Track.STEP)))
		worst_curv = maxf(worst_curv, absf(t.curvature_at(s)))
		s += Track.STEP
	_check(worst_gap < 0.01, "route continue (pas de trou entre les points)", "écart %.4f m" % worst_gap)
	_check(worst_turn <= Track.MAX_CURVATURE * Track.STEP + 1e-5, "pas de cassure de direction", "%.5f rad" % worst_turn)
	_check(worst_curv <= Track.MAX_CURVATURE + 1e-6, "courbure bornée", "%.5f" % worst_curv)
	_check(absf(t.point_at(20000.0).y) < 60.0, "altitude qui ne dérive pas", "%.1f m" % t.point_at(20000.0).y)


func _test_track_is_deterministic() -> void:
	var a := Track.new(42)
	var b := Track.new(42)
	var c := Track.new(43)
	a.ensure(5000.0)
	b.ensure(5000.0)
	c.ensure(5000.0)
	_check(a.point_at(4999.0).is_equal_approx(b.point_at(4999.0)), "même graine = même route")
	_check(not a.point_at(4999.0).is_equal_approx(c.point_at(4999.0)), "autre graine = autre route")


func _test_track_trim_keeps_sampling() -> void:
	var t := Track.new(5)
	t.ensure(3000.0)
	var before := t.point_at(2500.0)
	t.trim(2000.0)
	_check(t.start_s() > 1500.0, "la route derrière est oubliée", "start_s %.0f" % t.start_s())
	_check(t.point_at(2500.0).is_equal_approx(before), "l'échantillonnage survit à l'oubli")


## Le pilote automatique (qui braque comme un joueur attentif) tient 3 minutes
## à fond sans toucher la glissière, sur plusieurs routes : la route est
## conduisible à pleine vitesse.
func _test_autopilot_drives_clean() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var t := Track.new(seed)
		var car := CarPhysics.new()
		var top := 0.0
		var worst_x := 0.0
		for i in 60 * 180:
			car.step(t, 1.0, car.autopilot_steer(t, 0.0), 1.0 / 60.0)
			t.ensure(car.s + 500.0)
			t.trim(car.s - 300.0)
			top = maxf(top, car.speed_kmh())
			worst_x = maxf(worst_x, absf(car.x))
		_check(car.rail_hits == 0 and worst_x < CarPhysics.ROAD_HALF_WIDTH,
				"graine %d : 3 min à fond sans sortir de la route" % seed,
				"chocs %d, écart max %.1f m" % [car.rail_hits, worst_x])
		_check(top > 260.0, "graine %d : vitesse de pointe atteinte" % seed, "%.0f km/h" % top)


## Sans braquer, la voiture finit contre la glissière : les virages comptent.
func _test_curves_need_steering() -> void:
	var t := Track.new(1)
	var car := CarPhysics.new()
	for i in 60 * 90:
		car.step(t, 1.0, 0.0, 1.0 / 60.0)
		t.ensure(car.s + 500.0)
	_check(car.rail_hits > 0, "sans braquer on touche la glissière", "chocs %d" % car.rail_hits)


func _test_lifting_thumb_brakes() -> void:
	var t := Track.new(1)
	var car := CarPhysics.new()
	car.speed = 60.0
	for i in 60 * 2:
		car.step(t, 0.0, car.autopilot_steer(t, 0.0), 1.0 / 60.0)
	_check(car.speed < 25.0, "pouce levé 2 s : la voiture freine", "%.1f m/s" % car.speed)


func _test_chunks_are_valid() -> void:
	var t := Track.new(1)
	var b := RoadBuilder.new(t, 1)
	var ok := true
	var detail := ""
	for i in 6:
		var mi := b.build_chunk(i)
		var mesh: ArrayMesh = mi.mesh
		if mesh.get_surface_count() < 2:
			ok = false
			detail = "tronçon %d : %d surfaces" % [i, mesh.get_surface_count()]
		for surf in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
				if not v.is_finite():
					ok = false
					detail = "sommet invalide tronçon %d" % i
		mi.free()
	_check(ok, "tronçons de route valides", detail)
	# Tronçon d'une station : portique avec son texte, aire plate et éclairée.
	var tb := Track.new(1)
	var sb := RoadBuilder.new(tb, 1)
	sb.stations = RunConfig.stations()
	var st := RunConfig.station_s(0)
	var chunk := sb.build_chunk(int(st / RoadBuilder.CHUNK_LENGTH))
	var labels := chunk.get_children().filter(func(n: Node) -> bool: return n is Label3D)
	_check(labels.size() == 1 and labels[0].text == "STATION 1", "station : portique et son texte", str(labels.size()))
	chunk.free()
	_check(is_zero_approx(sb.ground_height(st - RoadBuilder.STATION_SITE_BACK, 30.0)), "station : aire plate")
	_check(sb.lamp_light(st - RoadBuilder.STATION_SITE_BACK, 4.0) > 0.6, "station : la route est éclairée devant la station")
	# Les lampadaires éclairent la route, pas partout.
	var lit := 0
	var samples := 0
	var s := 0.0
	while s < 600.0:
		samples += 1
		if b.lamp_light(s, 0.0) > 0.2:
			lit += 1
		s += 1.0
	var ratio := float(lit) / samples
	_check(ratio > 0.2 and ratio < 0.8, "alternance ombre / lumière sous les lampadaires", "%.0f %% éclairé" % (ratio * 100.0))


func _test_thumb_input() -> void:
	# L'arbre de scène n'est pas prêt pendant _initialize : on attend une image.
	await process_frame
	var input := ThumbInput.new()
	root.add_child(input)
	_check(input.is_inside_tree(), "pouce : le nœud d'entrée est dans l'arbre")
	if not input.is_inside_tree():
		return
	var w := input.get_viewport().get_visible_rect().size.x
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(w * 0.5, 300)
	input._unhandled_input(touch)
	input._process(0.0)
	_check(input.throttle == 1.0 and absf(input.steer) < 0.01, "pouce posé : gaz, roues droites")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(w * 0.5 + w * input.steer_range * 0.5, 300)
	input._unhandled_input(drag)
	input._process(0.0)
	_check(input.steer > 0.3 and input.steer < 0.7, "glissé à droite : braquage partiel", "%.2f" % input.steer)
	# Dépasser la course puis revenir un peu : l'ancre a suivi, on contre-braque vite.
	drag.position = Vector2(w * 0.95, 300)
	input._unhandled_input(drag)
	input._process(0.0)
	_check(is_equal_approx(input.steer, 1.0), "glissé loin : braquage à fond")
	drag.position = Vector2(w * 0.95 - w * input.steer_range, 300)
	input._unhandled_input(drag)
	input._process(0.0)
	_check(absf(input.steer) < 0.01, "l'ancre suit le pouce : revenir d'une course remet droit", "%.2f" % input.steer)
	touch.pressed = false
	input._unhandled_input(touch)
	input._process(0.0)
	_check(input.throttle == 0.0, "pouce levé : plus de gaz")
	input.queue_free()
	await process_frame


func _test_run_rules() -> void:
	var g := GameRun.new()
	g.start()
	g.update(100.0, false, 1.0)
	_check(is_equal_approx(g.score, 100.0) and is_equal_approx(g.time_left, RunConfig.START_TIME - 1.0),
			"partie : le score suit la distance, le chrono descend", "score %.0f, temps %.1f" % [g.score, g.time_left])
	var before := g.time_left
	g.update(RunConfig.station_s(0) + 1.0, false, 0.0)
	_check(is_equal_approx(g.time_left, before + RunConfig.STATION_TIME[0]) and g.next_station == 1,
			"station : temps rendu une seule fois", "temps %.1f" % g.time_left)
	g.update(RunConfig.station_s(0) + 2.0, false, 0.0)
	_check(g.next_station == 1, "station : pas de double bonus")
	g.on_near_miss()
	g.on_near_miss()
	_check(g.multiplier() > 1.4, "frôlages : le multiplicateur monte", "×%.2f" % g.multiplier())
	g.on_crash(RunConfig.station_s(0) + 2.0)
	_check(is_equal_approx(g.multiplier(), 1.0), "choc : le multiplicateur retombe à ×1")
	var t := GameRun.new()
	t.start()
	t.update(10.0, false, RunConfig.START_TIME + 1.0)
	_check(t.state == GameRun.State.TIME_UP, "chrono à zéro : la nuit gagne")
	var a := GameRun.new()
	a.start(RunConfig.arrival_s() - 10.0)
	a.time_left = 12.3
	a.update(RunConfig.arrival_s() + 1.0, false, 0.0)
	_check(a.state == GameRun.State.ARRIVED and a.time_bonus == 13 * RunConfig.TIME_BONUS_PER_SECOND,
			"aube : arrivée et bonus de temps", "bonus %d" % a.time_bonus)


func _test_traffic_rules() -> void:
	# Choc par l'arrière : la voiture perd sa vitesse et ne traverse pas le véhicule.
	var tr := Traffic.new(1)
	var v := Traffic.Vehicle.new()
	v.s = 102.5
	v.x = 0.0
	v.target_x = 0.0
	v.speed = 30.0
	v.cruise = 30.0
	tr.vehicles.append(v)
	tr._next_spawn_s = INF
	var car := CarPhysics.new()
	car.s = 100.0
	car.speed = 75.0
	var events := tr.update(car, 1.0 / 60.0)
	_check(events.size() == 1 and events[0].type == "crash" and car.speed <= 30.0 * Traffic.CRASH_SPEED_FACTOR + 0.01
			and car.s < v.s - v.half_length(), "trafic : choc par l'arrière", str(events))
	# Frôlage : doubler à 2,9 m d'axe à axe (env. 1 m d'espace).
	var tr2 := Traffic.new(1)
	var w := Traffic.Vehicle.new()
	w.s = 100.5
	w.x = 0.0
	w.target_x = 0.0
	w.speed = 30.0
	w.cruise = 30.0
	tr2.vehicles.append(w)
	tr2._next_spawn_s = INF
	var car2 := CarPhysics.new()
	car2.s = 100.0
	car2.x = 2.9
	car2.speed = 75.0
	var got_near := false
	for i in 30:
		car2.s += car2.speed / 60.0
		for e in tr2.update(car2, 1.0 / 60.0):
			got_near = got_near or e.type == "near_miss"
	_check(got_near, "trafic : frôlage détecté en doublant de près")
	# Doubler loin (une voie d'écart) ne compte pas.
	var tr3 := Traffic.new(1)
	var u := Traffic.Vehicle.new()
	u.s = 100.5
	u.speed = 30.0
	u.cruise = 30.0
	tr3.vehicles.append(u)
	tr3._next_spawn_s = INF
	var car3 := CarPhysics.new()
	car3.s = 100.0
	car3.x = 6.0
	car3.speed = 75.0
	var far_near := false
	for i in 30:
		car3.s += car3.speed / 60.0
		for e in tr3.update(car3, 1.0 / 60.0):
			far_near = far_near or e.type == "near_miss"
	_check(not far_near, "trafic : doubler de loin n'est pas un frôlage")
	# Jamais de mur sous le nez du joueur : sur 3 minutes au trafic le plus dense
	# du jeu, il ne doit pas tomber sur 3 véhicules de front juste devant lui.
	var tr4 := Traffic.new(3)
	tr4.density = RunConfig.TRAFFIC_DENSITY.max()
	var runner := CarPhysics.new()
	var blocked_frames := 0
	var overlaps := 0
	for i in 60 * 180:
		runner.s += 70.0 / 60.0
		runner.speed = 70.0
		runner.x = 7.0
		tr4.update(runner, 1.0 / 60.0)
		for a in tr4.vehicles:
			if a.s - runner.s > 15.0 and a.s - runner.s < 60.0 and _true_wall(tr4, a):
				blocked_frames += 1
				break
			for b in tr4.vehicles:
				if a != b and absf(a.x - b.x) < 2.0 and absf(a.s - b.s) < a.half_length() + b.half_length():
					overlaps += 1
	_check(_traffic_signature(5) == _traffic_signature(5), "trafic : même graine = même trafic")
	# Témoin : le détecteur de mur voit bien un mur posé à la main.
	var probe := Traffic.new(1)
	for k in 3:
		var pv := Traffic.Vehicle.new()
		pv.s = 100.0 + k * 6.0
		pv.x = Traffic.LANES[k]
		pv.target_x = pv.x
		probe.vehicles.append(pv)
	_check(_true_wall(probe, probe.vehicles[0]), "témoin : un mur posé à la main est détecté")
	probe.vehicles[2].s = 140.0
	_check(not _true_wall(probe, probe.vehicles[0]), "témoin : trois véhicules en quinconce large ne sont pas un mur")
	_check(blocked_frames == 0, "trafic : jamais de mur sur les 3 voies juste devant le joueur",
			"%.1f s bloqué" % (blocked_frames / 60.0))
	_check(overlaps == 0, "trafic : les véhicules ne se chevauchent pas", "%d" % overlaps)


## Équilibrage : le bon pilote arrive à l'aube, le prudent (215 km/h) et
## celui qui ignore le trafic n'y arrivent pas.
func _test_balance() -> void:
	var good := 0
	var margin_min := INF
	for seed in [1, 2, 3, 4]:
		var r := Sim.run(seed, Sim.Driver.GOOD)
		if r.game.state == GameRun.State.ARRIVED:
			good += 1
			margin_min = minf(margin_min, r.game.time_left)
	_check(good == 4, "équilibrage : le bon pilote atteint l'aube", "%d / 4" % good)
	_check(margin_min < 60.0, "équilibrage : sans marge énorme", "marge min %.1f s" % margin_min)
	for seed in [1, 2]:
		var c := Sim.run(seed, Sim.Driver.CAUTIOUS)
		_check(c.game.state == GameRun.State.TIME_UP, "équilibrage : 215 km/h ne suffit pas (graine %d)" % seed)
		var b := Sim.run(seed, Sim.Driver.BLIND)
		_check(b.game.state == GameRun.State.TIME_UP, "équilibrage : ignorer le trafic ne passe pas (graine %d)" % seed)


func _traffic_signature(seed: int) -> String:
	var tr := Traffic.new(seed)
	tr.density = 10.0
	var car := CarPhysics.new()
	var out := ""
	for i in 60 * 60:
		car.s += 70.0 / 60.0
		car.speed = 70.0
		car.x = 7.0
		tr.update(car, 1.0 / 60.0)
	for v in tr.vehicles:
		out += "%.3f/%.3f;" % [v.s, v.x]
	return out


## Mur infranchissable : trois véhicules, un par voie, tenant dans une fenêtre
## de Traffic.WALL_SPAN mètres (en quinconce plus large, on se faufile).
func _true_wall(tr: Traffic, a: Traffic.Vehicle) -> bool:
	var lanes := [[], [], []]
	for o in tr.vehicles:
		if absf(o.s - a.s) < Traffic.WALL_SPAN:
			for l in 3:
				if absf(o.x - Traffic.LANES[l]) < 2.5:
					lanes[l].append(o.s)
	for s0 in lanes[0]:
		for s1 in lanes[1]:
			for s2 in lanes[2]:
				if maxf(s0, maxf(s1, s2)) - minf(s0, minf(s1, s2)) < Traffic.WALL_SPAN:
					return true
	return false

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
	_test_route_map()
	_test_branching_track()
	_test_divider()
	_test_forks_and_endings()
	_test_fork_traffic()
	_test_events_and_story()
	await _test_audio_and_double_tap()
	await _test_turbo()
	_test_save_and_garage()
	await _test_car_feel()
	await _test_thumb_input()
	_test_ending_scenes()
	_test_police()
	_test_ghost()
	_test_fair_traffic()
	_test_short_lines()
	_test_pickups()
	await _test_english()
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
			# Voie de gauche : le terre-plein des bifurcations occupe le milieu.
			car.step(t, 1.0, car.autopilot_steer(t, -4.0), 1.0 / 60.0)
			t.ensure(car.s + 500.0)
			t.trim(car.s - 300.0)
			top = maxf(top, car.speed_kmh())
			worst_x = maxf(worst_x, absf(car.x))
		_check(car.rail_hits == 0 and worst_x < CarPhysics.ROAD_HALF_WIDTH + 0.5,
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
	var texts := labels.map(func(l: Label3D) -> String: return l.text)
	_check("STATION 1" in texts and "< LA FORÊT" in texts and "LE PORT >" in texts,
			"station : portique, son texte et les deux directions", str(texts))
	chunk.free()
	_check(is_zero_approx(sb.ground_height(st - RoadBuilder.STATION_SITE_BACK, 30.0)), "station : aire plate")
	# Chaque décor périodique tombe dans exactement un tronçon.
	var found := 0
	for i in 30:
		var s0 := i * RoadBuilder.CHUNK_LENGTH
		found += sb._every(RoadBuilder.BILLBOARD_SPACING, 330.0, s0, s0 + RoadBuilder.CHUNK_LENGTH).size()
	_check(found == 3, "décors : un panneau tous les 900 m, ni oublié ni doublé", "%d sur 3 km" % found)
	# Construction par étapes (version web) = construction d'un bloc.
	var tb2 := Track.new(1)
	var whole := RoadBuilder.new(tb2, 1)
	whole.stations = RunConfig.stations()
	var tb3 := Track.new(1)
	var sliced := RoadBuilder.new(tb3, 1)
	sliced.stations = RunConfig.stations()
	var same := true
	for i in [3, int(RunConfig.station_s(0) / RoadBuilder.CHUNK_LENGTH)]:
		var one := whole.build_chunk(i)
		var job := sliced.begin_chunk(i)
		var steps := 1
		while not sliced.step_chunk(job):
			steps += 1
		var parts: MeshInstance3D = job["result"]
		same = same and steps > 8 and _vertex_count(one) == _vertex_count(parts) \
				and one.get_child_count() == parts.get_child_count()
		one.free()
		parts.free()
	_check(same, "construction par étapes identique à la construction d'un bloc")
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
	g.update(100.0, 0.0, false, 1.0)
	_check(is_equal_approx(g.score, 100.0) and is_equal_approx(g.time_left, RunConfig.START_TIME - 1.0),
			"partie : le score suit la distance, le chrono descend", "score %.0f, temps %.1f" % [g.score, g.time_left])
	var before := g.time_left
	g.update(RunConfig.station_s(0) + 1.0, 0.0, false, 0.0)
	_check(is_equal_approx(g.time_left, before + RunConfig.STATION_TIME[0]) and g.next_station == 1,
			"station : temps rendu une seule fois", "temps %.1f" % g.time_left)
	g.update(RunConfig.station_s(0) + 2.0, 0.0, false, 0.0)
	_check(g.next_station == 1, "station : pas de double bonus")
	g.on_near_miss()
	g.on_near_miss()
	_check(g.multiplier() > 1.4, "frôlages : le multiplicateur monte", "×%.2f" % g.multiplier())
	g.on_crash(RunConfig.station_s(0) + 2.0)
	_check(is_equal_approx(g.multiplier(), 1.0), "choc : le multiplicateur retombe à ×1")
	var t := GameRun.new()
	t.start()
	t.update(10.0, 0.0, false, RunConfig.START_TIME + 1.0)
	_check(t.state == GameRun.State.TIME_UP, "chrono à zéro : la nuit gagne")
	var a := GameRun.new()
	a.start(RunConfig.arrival_s() - 10.0)
	a.time_left = 12.3
	a.update(RunConfig.arrival_s() + 1.0, 0.0, false, 0.0)
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


# --- M2 : bifurcations, ambiances, fins, événements --------------------------

func _test_route_map() -> void:
	var count := 0
	var ok := true
	for k in RouteMap.STAGES.size():
		_check(RouteMap.STAGES[k].size() == k + 1, "carte : l'étape %d compte %d tronçons" % [k + 1, k + 1])
		for id in RouteMap.STAGES[k]:
			count += 1
			ok = ok and RouteMap.THEMES.has(id)
	_check(count == 15 and ok, "carte : 15 tronçons, tous avec une ambiance", str(count))
	_check(RouteMap.node_of(4, [0, 0, 0, 0]) == 0 and RouteMap.node_of(4, [1, 1, 1, 1]) == 4
			and RouteMap.node_of(4, [1, 0, 1, 0]) == 2, "carte : le rang = nombre de virages à droite")
	_check(RouteMap.stage_at(RouteMap.region_start(2) - 1.0) == 1 and RouteMap.stage_at(RouteMap.region_start(2)) == 2,
			"carte : les régions commencent à la fin du terre-plein")
	for k in range(1, RouteMap.STAGES.size()):
		_check(is_zero_approx(fmod(RouteMap.region_start(k), RoadBuilder.CHUNK_LENGTH)),
				"carte : la région %d commence au début d'un tronçon de 100 m" % (k + 1))


func _test_branching_track() -> void:
	# Sans choix connu, la route s'arrête à la fin du premier terre-plein.
	var w := Track.new(1, true)
	w.ensure(20000.0)
	_check(w.end_s() <= RouteMap.region_start(1) + Track.STEP and w.end_s() > RouteMap.region_start(1) - 10.0,
			"tracé : rien n'est généré au-delà d'une bifurcation non choisie", "%.0f" % w.end_s())
	w.choices.assign([1])
	w.ensure(8000.0)
	_check(w.end_s() >= 8000.0, "tracé : le choix connu, la route reprend")
	# Un même tronçon a la même forme, quel que soit le chemin pour y arriver.
	var a := Track.new(7, true)
	a.choices.assign([1, 0, 0, 0])
	var b := Track.new(7, true)
	b.choices.assign([0, 1, 0, 0])
	a.ensure(16000.0)
	b.ensure(16000.0)
	var same := true
	var s := RouteMap.region_start(2)
	while s < RouteMap.region_start(3) - 10.0:
		same = same and is_equal_approx(a.curvature_at(s), b.curvature_at(s))
		s += 20.0
	_check(same, "tracé : même tronçon, même forme (gauche puis droite = droite puis gauche)")
	var c := Track.new(7, true)
	c.choices.assign([0, 0, 0, 0])
	c.ensure(16000.0)
	var differs := false
	s = RouteMap.region_start(2)
	while s < RouteMap.region_start(3) - 10.0:
		differs = differs or not is_equal_approx(a.curvature_at(s), c.curvature_at(s))
		s += 20.0
	_check(differs, "tracé : un autre tronçon a une autre forme")
	# Continuité et bornes sur le chemin le plus sinueux (col).
	var r := Track.new(3, true)
	r.choices.assign([1, 1, 1, 1])
	r.ensure(RunConfig.arrival_s() + 200.0)
	var worst_gap := 0.0
	var worst_curv := 0.0
	var straight := true
	s = Track.STEP
	while s < RunConfig.arrival_s():
		worst_gap = maxf(worst_gap, absf(r.point_at(s).distance_to(r.point_at(s - Track.STEP)) - Track.STEP))
		worst_curv = maxf(worst_curv, absf(r.curvature_at(s)))
		if RouteMap.divider_fork(s) != -1 and absf(r.curvature_at(s)) > 1e-6:
			straight = false
		s += Track.STEP
	_check(worst_gap < 0.01 and worst_curv <= Track.MAX_CURVATURE + 1e-6,
			"tracé : continu et borné jusqu'à l'aube (chemin de droite)", "écart %.3f, courbure %.4f" % [worst_gap, worst_curv])
	_check(straight, "tracé : la route est droite le long des terre-pleins")


func _test_divider() -> void:
	var t := Track.new(1)
	var f := RouteMap.fork_s(0)
	# Au milieu au nez du terre-plein : choc.
	var car := CarPhysics.new()
	car.s = f + RouteMap.DIVIDER_START - 1.0
	car.speed = 70.0
	var hit := false
	for i in 10:
		car.step(t, 1.0, 0.0, 1.0 / 60.0)
		hit = hit or car.hit_divider
	_check(hit and car.speed < 35.0, "terre-plein : arriver au milieu, c'est le percuter", "%.0f m/s" % car.speed)
	# Côté gauche : pas de choc, et impossible de passer à droite.
	var left := CarPhysics.new()
	left.s = f
	left.x = -4.0
	left.speed = 70.0
	var crossed := false
	var hit_left := false
	for i in 240:
		# Tout droit jusqu'au nez, puis braquage à fond vers la droite.
		var steer := 1.0 if RouteMap.divider_fork(left.s) != -1 else left.autopilot_steer(t, -4.0)
		left.step(t, 1.0, steer, 1.0 / 60.0)
		hit_left = hit_left or left.hit_divider
		if RouteMap.divider_fork(left.s) != -1 and left.x > -1.0:
			crossed = true
	_check(not hit_left and not crossed, "terre-plein : on reste du côté choisi", "x %.2f" % left.x)


func _test_forks_and_endings() -> void:
	for ending in RouteMap.ENDINGS.size():
		var path := []
		for k in 4:
			path.append(1 if k < ending else 0)
		var g := GameRun.new()
		g.start()
		var regions := []
		g.region_entered.connect(func(stage: int, id: String) -> void: regions.append(id))
		var s := 0.0
		while g.state == GameRun.State.RUNNING:
			var k := g.choices.size()
			var x := 0.0
			if k < 4:
				x = 4.0 if path[k] == 1 else -4.0
			g.time_left = 100.0
			s += 50.0
			g.update(s, x, false, 0.01)
		_check(g.state == GameRun.State.ARRIVED and g.ending == ending and g.choices == path,
				"fins : le chemin %s mène à %s" % [str(path), RouteMap.ENDINGS[ending]], "fin %d" % g.ending)
		_check(regions.size() == 4 and regions[3] == RouteMap.STAGES[4][ending],
				"fins : 4 régions traversées vers %s" % RouteMap.ENDINGS[ending], str(regions))


func _test_fork_traffic() -> void:
	var tr := Traffic.new(4)
	tr.density = 12.0
	var runner := CarPhysics.new()
	runner.x = 7.0
	var in_middle := 0
	for i in 60 * 140:
		runner.s += 70.0 / 60.0
		runner.speed = 70.0
		tr.update(runner, 1.0 / 60.0)
		for v in tr.vehicles:
			if RouteMap.divider_fork(v.s) != -1 and absf(v.x) < RouteMap.DIVIDER_HALF_WIDTH + v.half_width():
				in_middle += 1
	_check(in_middle == 0, "trafic : aucun véhicule dans le terre-plein", "%d" % in_middle)
	# Le bon pilote prend le côté demandé à chaque bifurcation.
	var r := Sim.run(2, Sim.Driver.GOOD, [1, 0, 1, 1])
	_check(r.game.choices == [1, 0, 1, 1], "pilote : il prend les directions demandées", str(r.game.choices))


func _test_events_and_story() -> void:
	var d0 := EventDirector.new(5, 0)
	var d1 := EventDirector.new(5, 1)
	_check(d1.plan["stoppeuse"] > d0.plan["stoppeuse"], "événements : l'auto-stoppeuse est plus loin à chaque partie")
	var fired := d0.crossed(0.0, RunConfig.arrival_s())
	_check(fired.size() == 5, "événements : les 5 événements de route se déclenchent", str(fired))
	_check(d0.crossed(0.0, RunConfig.arrival_s()).is_empty(), "événements : une seule fois chacun")
	var p := d0.panneau_at(0.0, RunConfig.arrival_s())
	_check(p.size() == 3, "événements : trois panneaux « VOUS ÊTES ICI »")
	for id in RouteMap.THEMES:
		_check(Scenario.RADIO.has(id) or id == "autoroute", "radio : une réplique pour %s" % id)
	var all := {"stoppeuse": true, "radio_live": true, "panneau": true, "fantome": true}
	_check(Scenario.ending_text(4, all).contains("Lou, à dix-sept ans"), "fins : l'épilogue secret avec 4 événements")
	_check(not Scenario.ending_text(4, {"panneau": true}).contains("dix-sept"), "fins : pas d'épilogue sans eux")
	for e in 5:
		_check(Scenario.ending_text(e, {}).length() > 80, "fins : un texte pour %s" % RouteMap.ENDINGS[e])
	# Toutes les lettres des textes existent dans la police pixel.
	var fonts := [Hud.arcade_font(), Hud.text_font(), Hud.text_font(true)]
	var texts := Scenario.RADIO.values() + Scenario.DETAILS.values() + [Scenario.EPILOGUE]
	for en in Scenario.ENDINGS:
		texts.append_array(en)
	for th in RouteMap.THEMES.values():
		texts.append(th["name"])
	var missing := ""
	for txt in texts:
		for ch in txt:
			for font in fonts:
				if ch != "\n" and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
					missing += ch
	_check(missing == "", "polices : tous les caractères des textes existent", missing)


# --- M3 : son --------------------------------------------------------------------

func _test_audio_and_double_tap() -> void:
	await process_frame
	var audio := AudioDirector.new()
	root.add_child(audio)
	await process_frame
	# Version web : le mode « échantillons » de Godot (par défaut depuis 4.3)
	# restait muet avec nos bus créés en cours de jeu, la réverbération et le
	# moteur dont la hauteur change à chaque image (mesuré dans Chromium : 0,0000
	# en sortie). Le mode « flux » (Godot mixe lui-même) doit rester choisi.
	_check(int(ProjectSettings.get_setting("audio/general/default_playback_type.web", 1)) == 0,
			"son : version web en mode flux (sinon muette)")
	# Aube : la radio s'éteint, la musique de fin joue, le moteur se fait discret.
	audio.play_dawn()
	for i in 20:
		await create_timer(0.3).timeout
	audio.update(0.0, 0.0, 0.0, false, 1.0 / 30.0)
	_check(audio._dawn.playing and audio._dawn.stream.get_length() > 20.0 and not audio._music.playing
			and audio._engine_fade < 0.35 and audio._dawn.bus == "Musique",
			"son : à l'aube, la musique de fin remplace la radio")
	audio.queue_free()
	audio = AudioDirector.new()
	root.add_child(audio)
	await process_frame
	# Le régime monte dans un rapport, retombe au passage du suivant.
	var rpms := []
	var gears := []
	var speed := 0.0
	while speed < CarPhysics.TOP_SPEED:
		audio.update(speed, 1.0, 1.0, false, 1.0 / 30.0)
		rpms.append(audio.rpm)
		gears.append(audio.gear)
		speed += 0.5
	var drops := 0
	for i in range(1, rpms.size()):
		if gears[i] > gears[i - 1] and rpms[i] < rpms[i - 1]:
			drops += 1
	_check(gears[-1] == AudioDirector.GEARS.size() - 2 and drops >= 4,
			"son : six rapports, le régime retombe à chaque passage", "rapport %d, %d chutes" % [gears[-1], drops])
	var names := []
	for i in AudioDirector.STATIONS.size():
		names.append(audio.next_station())
	_check(names[-1] == AudioDirector.STATIONS[0]["name"] and names.has("RADIO ÉTEINTE"),
			"radio : le double tap fait le tour des stations", str(names))
	for name in ["engine_low", "engine_high", "rain", "wind", "tires", "crash", "whoosh", "chime", "static",
			"thud", "blip", "thunder", "music_synthwave", "music_italo", "music_euro", "music_ballad", "dawn", "siren"]:
		_check(ResourceLoader.exists("res://assets/audio/%s.ogg" % name), "son : %s présent" % name)
	audio.queue_free()
	# Double tap : deux touches brèves rapprochées.
	var input := ThumbInput.new()
	root.add_child(input)
	var taps := [0]
	input.double_tapped.connect(func() -> void: taps[0] += 1)
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	for k in 2:
		ev.pressed = true
		input._unhandled_input(ev)
		input._process(0.1)
		ev.pressed = false
		input._unhandled_input(ev)
		input._process(0.1)
	_check(taps[0] == 1, "pouce : double tap reconnu", str(taps[0]))
	# Une longue pression (on roule) suivie d'une touche n'est pas un double tap.
	ev.pressed = true
	input._unhandled_input(ev)
	input._process(1.0)
	ev.pressed = false
	input._unhandled_input(ev)
	input._process(0.1)
	ev.pressed = true
	input._unhandled_input(ev)
	_check(taps[0] == 1, "pouce : lâcher après avoir roulé ne compte pas", str(taps[0]))
	input.queue_free()
	await process_frame


func _vertex_count(mi: MeshInstance3D) -> int:
	var n := 0
	for m in [mi] + mi.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D):
		for s in m.mesh.get_surface_count():
			n += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	return n


# --- Turbo néon ---------------------------------------------------------------

func _test_turbo() -> void:
	var g := GameRun.new()
	g.start()
	_check(not g.fire_turbo(), "turbo : impossible avec une jauge vide")
	var ready := [false]
	g.turbo_ready.connect(func() -> void: ready[0] = true)
	for i in 5:
		g.on_near_miss()
	_check(ready[0] and is_equal_approx(g.turbo, 1.0), "turbo : les frôlages remplissent la jauge", "%.2f" % g.turbo)
	_check(g.fire_turbo() and g.is_boosting() and g.turbo == 0.0, "turbo : déclenché, la jauge se vide")
	g.update(10.0, 0.0, false, RunConfig.TURBO_DURATION + 0.1)
	_check(not g.is_boosting(), "turbo : il s'arrête après sa durée")
	# Sous turbo, la voiture dépasse sa vitesse de pointe puis y retombe en douceur.
	var t := Track.new(1)
	var car := CarPhysics.new()
	car.speed = CarPhysics.TOP_SPEED
	car.boost = RunConfig.TURBO_SPEED
	car.accel_boost = RunConfig.TURBO_ACCEL
	for i in 60 * 3:
		car.step(t, 1.0, car.autopilot_steer(t, -4.0), 1.0 / 60.0)
	var boosted := car.speed
	car.boost = 1.0
	car.accel_boost = 1.0
	car.step(t, 1.0, 0.0, 1.0 / 60.0)
	var after_one := car.speed
	_check(boosted > CarPhysics.TOP_SPEED * 1.1, "turbo : vitesse de pointe relevée", "%.0f km/h" % (boosted * 3.6))
	_check(after_one > CarPhysics.TOP_SPEED and after_one < boosted, "turbo : retombée progressive, pas brutale")
	# Glissé vers le haut.
	await process_frame
	var input := ThumbInput.new()
	root.add_child(input)
	var swipes := [0]
	input.swiped_up.connect(func() -> void: swipes[0] += 1)
	var h := input.get_viewport().get_visible_rect().size.y
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(100, h * 0.7)
	input._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(100, h * 0.55)
	input._unhandled_input(drag)
	drag.position = Vector2(100, h * 0.5)
	input._unhandled_input(drag)
	_check(swipes[0] == 1, "turbo : glisser vers le haut le déclenche, une seule fois", str(swipes[0]))
	drag.position = Vector2(110, h * 0.68)
	input._unhandled_input(drag)
	_check(swipes[0] == 1, "turbo : tourner ne déclenche rien")
	input.queue_free()
	await process_frame


# --- Sauvegarde, garage, carnet -------------------------------------------------------

func _test_save_and_garage() -> void:
	var path := "user://test_save.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := SaveData.load_or_new(path)
	_check(s.best == 0 and s.credits == 0 and s.unlocked_colors() == [0], "sauvegarde : neuve et vide")
	s.credits = SaveData.credits_for(150000)
	_check(s.credits == 1500, "garage : 1 crédit tous les 100 points", str(s.credits))
	_check(s.buy_upgrade("moteur") and s.upgrades["moteur"] == 1 and s.credits == 300, "garage : achat d'un niveau")
	_check(not s.buy_upgrade("moteur"), "garage : pas d'achat sans les crédits")
	_check(s.record_ending(2, 90000) and not s.record_ending(2, 80000) and s.endings[2] == 90000,
			"carnet : une fin découverte garde son record")
	_check(s.unlocked_colors() == [0, 3], "garage : chaque fin débloque sa teinte", str(s.unlocked_colors()))
	s.messages["lac"] = true
	s.write()
	var r := SaveData.load_or_new(path)
	_check(r.upgrades["moteur"] == 1 and r.endings[2] == 90000 and r.messages.has("lac") and r.credits == 300,
			"sauvegarde : tout est relu à l'identique")
	# Les améliorations restent modestes et vont dans le bon sens.
	var car := CarPhysics.new()
	var g := GameRun.new()
	for k in r.upgrades:
		r.upgrades[k] = Garage.MAX_LEVEL
	Garage.apply(r, car, g)
	_check(car.upgrade_top > 1.0 and car.upgrade_top <= 1.05 and car.steer_mult > 1.0 and car.grip < 1.0
			and car.crash_keep > 0.0 and g.turbo_gain > 1.0, "garage : améliorations au maximum, gains modestes")
	# Chaque tronçon a son message de Lou, et chaque texte s'affiche avec nos polices.
	var missing := []
	for stage in RouteMap.STAGES:
		for id in stage:
			if not Scenario.LOU.has(id):
				missing.append(id)
	_check(missing.is_empty(), "Lou : un message par tronçon", str(missing))
	var bad := ""
	# Tous les textes en dur du carnet et du garage aussi.
	var menu_src := FileAccess.get_file_as_string("res://scripts/menus.gd") + FileAccess.get_file_as_string("res://scripts/garage.gd")
	var literals := []
	var rx := RegEx.create_from_string("\"([^\"]*)\"")
	for m in rx.search_all(menu_src):
		literals.append(m.get_string(1))
	for txt in Scenario.LOU.values() + Menus.EVENT_NAMES.values() + [Scenario.LOU_HEADER] + literals:
		for ch in txt:
			for font in [Hud.arcade_font(), Hud.text_font(), Hud.text_font(true)]:
				if not font.has_char(ch.unicode_at(0)) and not bad.contains(ch):
					bad += ch
	_check(bad == "", "polices : messages et carnet affichables", bad)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_car_feel() -> void:
	await process_frame
	var view := CarView.new()
	root.add_child(view)
	await process_frame
	# Une image très longue et une accélération absurde ne doivent pas faire
	# diverger la suspension (la voiture disparaissait au premier pas de temps).
	view.animate(2500.0, 30.0, 70.0, 0.5)
	for i in 120:
		view.animate(-40.0, -12.0, 70.0, 1.0 / 60.0)
	var r: Vector3 = view.get_child(0).rotation
	_check(r.is_finite() and absf(r.x) <= 0.08 and absf(r.z) <= 0.1, "voiture : suspension bornée et stable", str(r))
	# Vers la gauche (vitesse latérale négative), le flanc droit (+X) descend : rotation z < 0.
	_check(r.x < 0.0 and r.z < 0.0, "voiture : plonge au freinage, penche vers l'extérieur", str(r))
	view.queue_free()
	await process_frame


func _test_ending_scenes() -> void:
	var arrival := RunConfig.arrival_s()
	var anchor := EndingScene.anchor_s(arrival)
	_check(anchor >= arrival + EndingScene.RUNOUT and fmod(anchor, RoadBuilder.CHUNK_LENGTH) == 0.0,
			"fin : bout de la route au-delà de l'arrivée, en début de tronçon", str(anchor))
	# La voiture la plus rapide possible (turbo, aspiration, moteur au maximum)
	# s'arrête avant le bout de la route, sans le frein brutal à la dernière seconde.
	var track := Track.new(3)
	for path in [[0, 0, 0, 0], [1, 1, 1, 1]]:
		track.choices.assign(path)
		track.ensure(anchor + 500.0)
		var car := CarPhysics.new()
		car.s = arrival
		car.speed = CarPhysics.TOP_SPEED * RunConfig.TURBO_SPEED * RunConfig.DRAFT_SPEED * 1.1
		var worst := 0.0
		for i in 1200:
			var before := car.speed
			car.step(track, 0.0, 0.0, 1.0 / 60.0)
			EndingScene.brake(car, anchor, 1.0 / 60.0, before)
			worst = maxf(worst, (before - car.speed) * 60.0)
		_check(car.speed == 0.0 and car.s <= anchor - EndingScene.STOP_BEFORE + 0.5
				and car.s > anchor - EndingScene.STOP_BEFORE - 3.0,
				"fin : la voiture s'arrête au bout de la route, pas avant", "s %.4f / %.1f, v %s" % [car.s, anchor, str(car.speed)])
		_check(worst < 40.0, "fin : freinage final sans à-coup", "%.1f m/s²" % worst)
	# Chaque destination a son décor, devant la voiture.
	var b := RoadBuilder.new(track, 3)
	var ok := true
	var detail := ""
	for e in RouteMap.ENDINGS.size():
		var sc := EndingScene.build(e, b, track, anchor)
		var mi: MeshInstance3D = sc["node"]
		var focus: Vector3 = sc["focus"]
		var surfaces := mi.mesh.get_surface_count() if mi.mesh else 0
		if surfaces < 1 or focus.z >= 0.0 or not (sc["frame"] as Transform3D).origin.is_finite():
			ok = false
			detail += "%d " % e
		mi.free()
	_check(ok, "fin : un décor pour chacune des cinq destinations", detail)


## Textes qui ne s'affichent jamais (bus audio, noms de nœuds).
const NOT_SHOWN := ["Bruitages", "Musique", "Master", "EndingScene", "Chunk%d", "II", "La Mer",
		"https://s3str4.github.io/IPHONEDUO/", "  ·  %d Hz"]
## Lettres et signes qui trahissent du français resté à l'écran.
const FRENCH_MARKS := "éèêëàâçôûùîïœÉÈÊÀÂÇÔÛÎ«»"


func _test_english() -> void:
	# 1. Chaque texte du code a sa version anglaise, avec les mêmes gabarits.
	var rx := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var ident := RegEx.create_from_string("^[a-z0-9_#./:%-]*$")
	var letters := RegEx.create_from_string("[A-Za-zÀ-ÿ]{2,}")
	var holes := RegEx.create_from_string("%[-0-9.]*[dsf]")
	var missing := []
	var wrong := []
	var scanned := 0
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "lang.gd":
			continue
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			var code := line.get_slice("##", 0)
			if code.strip_edges().begins_with("#") or code.contains("print(") or code.contains("push_"):
				continue
			for m in rx.search_all(code):
				var v := m.get_string(1).c_unescape()
				if ident.search(v) != null or v.begins_with("res://") or letters.search(v) == null or v in NOT_SHOWN:
					continue
				scanned += 1
				if not Lang.EN.has(v):
					missing.append("%s: %s" % [f, v.left(40)])
				else:
					var a := holes.search_all(v).map(func(h: RegExMatch) -> String: return h.get_string())
					var b := holes.search_all(Lang.EN[v]).map(func(h: RegExMatch) -> String: return h.get_string())
					if a != b:
						wrong.append(v.left(40))
	# Le banc doit voir tous les textes (192 au moment où il est écrit), sinon il ne vérifie rien.
	_check(missing.is_empty() and scanned >= 180, "anglais : chaque texte du jeu est traduit", "%d vus, manquants : %s" % [scanned, str(missing)])
	_check(wrong.is_empty(), "anglais : mêmes gabarits (%d, %s) que le français", str(wrong))
	var french := []
	for v in Lang.EN.values():
		for ch in FRENCH_MARKS:
			if v.contains(ch) and v != "FRANÇAIS":
				french.append(v.left(30))
				break
	_check(french.is_empty(), "anglais : aucune traduction ne garde du français", str(french))
	var bad := ""
	for v in Lang.EN.values():
		for ch in v:
			if ch.unicode_at(0) < 32:
				continue
			for font in [Hud.arcade_font(), Hud.text_font(), Hud.text_font(true)]:
				if not font.has_char(ch.unicode_at(0)) and not bad.contains(ch):
					bad += ch
	_check(bad == "", "anglais : tout s'affiche avec nos polices", bad)
	Lang.code = "fr"
	_check(Lang.group(1234567) == "1 234 567" and Lang.t("TEMPS") == "TEMPS", "français : nombres et textes intacts")

	# 2. En anglais, aucun écran ne montre de français : interface, fins, menus
	# ouverts avec une sauvegarde où tout est découvert.
	Lang.code = "en"
	_check(Lang.group(1234567) == "1,234,567", "anglais : nombres groupés à l'anglaise")
	var hud := Hud.new()
	root.add_child(hud)
	await process_frame
	var save := SaveData.load_or_new("user://test_lang.cfg")
	for e in RouteMap.ENDINGS.size():
		save.endings[e] = 1000
	for id in Scenario.LOU:
		save.messages[id] = true
	for key in Menus.EVENT_NAMES:
		save.events_seen[key] = true
	for key in Garage.OPTIONS:
		save.owned[key] = true
	var menus := Menus.new()
	menus.save = save
	root.add_child(menus)
	await process_frame
	var seen := []
	hud.radio(Scenario.RADIO["lac"])
	hud.title_card(RouteMap.THEMES["lac"]["name"])
	hud.set_values(60.0, 1000.0, 2, 1.5, 200.0, 0.5)
	for e in RouteMap.ENDINGS.size():
		hud.show_overlay(RouteMap.ENDINGS[e], Scenario.ending_text(e, {"stoppeuse": true}), "TOUCHE POUR REJOUER")
		seen.append_array(_texts(hud))
	seen.append(Scenario.ending_text(4, {"a": 1, "b": 1, "c": 1, "d": 1}))
	hud.radio(Scenario.LOU["lac"], Scenario.LOU_HEADER)
	hud._process(30.0)
	seen.append_array(_texts(hud))
	for screen in ["open_journal", "open_settings", "open_garage"]:
		menus.call(screen)
		seen.append_array(_texts(menus))
	var leaks := []
	for txt in seen:
		for ch in FRENCH_MARKS:
			if txt.contains(ch) and txt != "FRANÇAIS":
				leaks.append(txt.left(40))
				break
	_check(leaks.is_empty() and seen.size() > 40, "anglais : aucun écran ne montre de français",
			"%d textes, fuites : %s" % [seen.size(), str(leaks)])
	hud.queue_free()
	menus.queue_free()
	Lang.code = "fr"
	await process_frame


func _texts(node: Node) -> Array:
	var out := []
	if node is Label or node is Button:
		if node.text != "":
			out.append(node.text)
	for c in node.get_children():
		out.append_array(_texts(c))
	return out


## Fait rouler `car` tout droit à vitesse constante (voie car.x) avec la police.
func _police_run(police: Police, car: CarPhysics, traffic: Traffic, seconds: float,
		speed: float, dodge := false) -> Array:
	var events := []
	for i in int(seconds * 60.0):
		car.speed = speed if police.hold == 0.0 else car.speed
		# Esquive : pendant l'annonce de la charge, changer de voie.
		if dodge and police.state == Police.State.RAM and absf(police.ram_x - car.x) < 2.0:
			car.x = -4.0 if car.x >= 0.0 else 4.0
		car.s += car.speed / 60.0
		for e in police.update(car, traffic, 1.0 / 60.0):
			events.append(e)
	return events


func _test_police() -> void:
	var police := Police.new(5)
	var placed := true
	for k in range(1, RouteMap.STAGES.size()):
		var p: float = police.patrols[k]
		if p < RouteMap.region_start(k) + 500.0 or p > RouteMap.fork_s(k) - 1500.0:
			placed = false
	_check(placed and not police.patrols.has(0) and Police.new(5).patrols == police.patrols,
			"police : une patrouille par étape, loin des bifurcations, toujours la même")
	var traffic := Traffic.new(5)
	traffic.density = 0.0
	# Passer devant à 190 km/h : rien. À 250 : poursuite.
	var car := CarPhysics.new()
	car.s = police.patrols[1] - 20.0
	var ev := _police_run(police, car, traffic, 2.0, 190.0 / 3.6)
	_check(ev.is_empty() and not police.active(), "police : sous 200 km/h, la patrouille reste garée")
	police = Police.new(5)
	police.patrols[3] = RouteMap.region_start(3) + 300.0
	car = CarPhysics.new()
	car.s = police.patrols[3] - 20.0
	car.x = 0.0
	ev = _police_run(police, car, traffic, 1.0, 250.0 / 3.6)
	_check(ev.size() == 1 and ev[0].type == "start" and police.active(), "police : au-dessus, poursuite")
	# À 280 km/h sans esquiver, elle rattrape et percute ; trois fois, arrêté.
	ev = _police_run(police, car, traffic, 60.0, CarPhysics.TOP_SPEED)
	var types := ev.map(func(e: Dictionary) -> String: return e.type)
	_check(types.count("contact") == Police.STRIKES_TO_BUST and types.has("busted") and police.busts == 1,
			"police : plus rapide que vous, trois touches et c'est le contrôle", str(types))
	# En changeant de voie quand elle charge, on l'évite.
	police = Police.new(5)
	police.patrols[3] = RouteMap.region_start(3) + 300.0
	car = CarPhysics.new()
	car.s = police.patrols[3] - 20.0
	ev = _police_run(police, car, traffic, 1.0, 250.0 / 3.6)
	ev = _police_run(police, car, traffic, 55.0, CarPhysics.TOP_SPEED, true)
	types = ev.map(func(e: Dictionary) -> String: return e.type)
	_check(not types.has("busted") and police.time > 30.0, "police : esquiver la charge marche",
			str(ev.map(func(e: Dictionary) -> String: return e.type + ":" + str(e.get("from", "")))))
	# Sous turbo, on la sème ; et elle abandonne en sortant de son secteur.
	police = Police.new(5)
	car = CarPhysics.new()
	car.s = police.patrols[1] - 20.0
	_police_run(police, car, traffic, 1.0, 250.0 / 3.6)
	ev = _police_run(police, car, traffic, 30.0, CarPhysics.TOP_SPEED * RunConfig.TURBO_SPEED)
	_check(ev.size() > 0 and ev.back().type == "escaped" and ev.back().why == "distance",
			"police : sous turbo, on la distance", str(ev.back() if ev.size() > 0 else {}))
	police = Police.new(5)
	car = CarPhysics.new()
	car.s = RouteMap.fork_s(1) + RouteMap.DIVIDER_END - 400.0
	police.patrols[1] = car.s + 10.0
	_police_run(police, car, traffic, 1.0, 250.0 / 3.6)
	ev = _police_run(police, car, traffic, 10.0, 60.0)
	_check(ev.size() > 0 and ev.back().type == "escaped" and ev.back().why == "secteur",
			"police : hors de son secteur, elle abandonne", str(ev))
	var game := GameRun.new()
	game.start(0.0)
	var before := game.score
	police.apply(ev.back(), game)
	_check(game.score > before and game.turbo >= 1.0 and not game.pursuit,
			"police : la semer paie (prime, turbo plein)")
	# Elle ne traverse jamais le trafic : simulation complète, chevauchements comptés.
	var overlaps := 0
	var frames := 0
	for seed in [1, 2]:
		var track := Track.new(seed, true)
		var c := CarPhysics.new()
		var tr := Traffic.new(seed)
		var pol := Police.new(seed)
		var g := GameRun.new()
		g.start(0.0)
		for i in 60 * 260:
			tr.density = RunConfig.TRAFFIC_DENSITY[g.segment()]
			var cmd := Autopilot.drive(c, track, tr, [0, 0, 0, 0], Autopilot.Driver.GOOD, pol)
			c.step(track, 0.0 if pol.hold > 0.0 else cmd[0], cmd[1], 1.0 / 60.0)
			tr.update(c, 1.0 / 60.0)
			for e in pol.update(c, tr, 1.0 / 60.0):
				pol.apply(e, g)
			g.update(c.s, c.x, false, 1.0 / 60.0)
			track.choices.assign(g.choices)
			track.ensure(c.s + 600.0)
			track.trim(c.s - 300.0)
			if pol.active():
				frames += 1
				for v in tr.vehicles:
					if absf(v.s - pol.s) < v.half_length() + Police.HALF_LENGTH - 0.3 \
							and absf(v.x - pol.x) < v.half_width() + Police.HALF_WIDTH - 0.3:
						overlaps += 1
	_check(frames > 60 * 30 and overlaps < frames / 200, "police : ne traverse pas le trafic",
			"%d images en poursuite, %d chevauchements" % [frames, overlaps])


func _test_ghost() -> void:
	var g := Ghost.new(7)
	# Une voiture à 50 m/s pendant 10 s, enregistrée à 60 images/s.
	for i in 601:
		g.record(i / 60.0, i / 60.0 * 50.0, 1.0)
	_check(absf(g.duration() - 10.0) < 0.11 and g.s_track.size() == 101, "fantôme : dix points par seconde", str(g.s_track.size()))
	_check(absf(g.at(4.25).x - 212.5) < 0.5 and absf(g.time_at(300.0) - 6.0) < 0.02 and g.time_at(900.0) == INF,
			"fantôme : position et instant de passage", "%s %s" % [g.at(4.25), g.time_at(300.0)])
	g.choices = [0, 1]
	_check(g.same_route([0]) and g.same_route([0, 1, 1]) and not g.same_route([1]),
			"fantôme : reconnaît une autre route")
	var path := "user://test_ghost.save"
	g.score = 1234
	g.write(path)
	var back := Ghost.load_for(7, path)
	_check(back != null and back.score == 1234 and back.choices == [0, 1] and back.s_track == g.s_track
			and Ghost.load_for(8, path) == null, "fantôme : sauvegardé et relu, pour sa route seulement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Trafic juste, façon OutRun : il annonce ses changements de voie, un passage
## serré n'est pas un choc, un frottement de côté ne vous arrête pas.
func _one_vehicle(s: float, x: float, speed: float) -> Array:
	var tr := Traffic.new(1)
	var v := Traffic.Vehicle.new()
	v.s = s
	v.x = x
	v.target_x = x
	v.speed = speed
	v.cruise = speed
	tr.vehicles.append(v)
	tr._next_spawn_s = INF
	return [tr, v]


func _test_fair_traffic() -> void:
	# Clignotant : il annonce, puis seulement il bouge.
	var tv := _one_vehicle(300.0, 0.0, 25.0)
	var tr: Traffic = tv[0]
	var v: Traffic.Vehicle = tv[1]
	var car := CarPhysics.new()
	car.s = 0.0
	car.x = -4.0
	car.speed = 0.0
	var ok := tr._try_lane_change(v, car)
	var moved_early := false
	for i in int(Traffic.SIGNAL_TIME * 60.0) - 3:
		tr.update(car, 1.0 / 60.0)
		moved_early = moved_early or absf(v.x) > 0.01
	for i in 90:
		tr.update(car, 1.0 / 60.0)
	_check(ok and not moved_early and absf(v.x) > 1.0, "trafic : clignotant avant de changer de voie", "x %.2f" % v.x)
	# Passage serré (chevauchement plus petit que la tolérance) : frôlement, pas choc.
	tv = _one_vehicle(102.0, 0.0, 30.0)
	tr = tv[0]
	v = tv[1]
	car = CarPhysics.new()
	var reach_x := v.half_width() + CarPhysics.CAR_HALF_WIDTH
	car.s = 101.0
	car.x = reach_x - Traffic.HIT_TOLERANCE_X * 0.5
	car.speed = 70.0
	var types := []
	for i in 30:
		car.s += car.speed / 60.0
		for e in tr.update(car, 1.0 / 60.0):
			types.append(e.type)
	_check(not "crash" in types and "near_miss" in types, "trafic : passage serré = frôlement (des points), pas choc", str(types))
	# Frottement de côté : on garde l'essentiel de sa vitesse.
	tv = _one_vehicle(100.0, 0.0, 30.0)
	tr = tv[0]
	v = tv[1]
	car = CarPhysics.new()
	car.s = 100.0
	car.x = reach_x * 0.7
	car.speed = 70.0
	var ev := tr.update(car, 1.0 / 60.0)
	_check(ev.size() == 1 and ev[0].type == "crash" and car.speed >= 70.0 * Traffic.SCRAPE_SPEED_KEPT - 0.01,
			"trafic : frottement de côté, petite perte seulement", "v %.1f" % car.speed)


## En course, une réplique se lit d'un coup d'œil : chacune a sa version courte.
func _test_short_lines() -> void:
	var missing := []
	var long := []
	for key in Scenario.RADIO:
		if key == "radio_live":
			continue
		var s := Scenario.short(Scenario.RADIO[key])
		if s == Scenario.RADIO[key]:
			missing.append(key)
		if s.length() > 60 or Lang.EN.get(s, "").length() > 60:
			long.append(key)
	_check(missing.is_empty(), "textes : chaque réplique a sa version courte", str(missing))
	_check(long.is_empty(), "textes : versions courtes de 60 signes au plus (FR et EN)", str(long))


func _test_pickups() -> void:
	var p := Pickups.new(4)
	var q := Pickups.new(4)
	var same := p.items.size() == q.items.size() and p.items.size() > 200
	var near_fork := 0
	var times := 0
	for i in p.items.size():
		same = same and p.items[i].s == q.items[i].s and p.items[i].x == q.items[i].x
		if Pickups._near_fork(p.items[i].s):
			near_fork += 1
		if p.items[i].kind == Pickups.Kind.TIME:
			times += 1
	_check(same and near_fork == 0 and times >= 5, "ramassage : jetons et bonus de temps, toujours pareils, loin des bifurcations",
			"%d objets, %d bonus de temps, %d près d'une bifurcation" % [p.items.size(), times, near_fork])
	# Rouler sur une ligne de jetons les ramasse ; tous ceux d'une étape = prime.
	var game := GameRun.new()
	game.start(0.0)
	var car := CarPhysics.new()
	var first: Pickups.Item = p.items[0]
	car.x = first.x
	var got := 0
	var perfect := false
	var t0 := game.time_left
	var time_item: Pickups.Item = null
	for it in p.items:
		if it.kind == Pickups.Kind.TIME:
			time_item = it
			break
	# Ramasser une étape entière (téléportation de jeton en jeton).
	for it in p.items:
		if it.stage != 0:
			break
		car.s = it.s
		car.x = it.x
		for g in p.update(car):
			got += 1
			perfect = p.apply(g, game) or perfect
	_check(got == p.items.filter(func(i: Pickups.Item) -> bool: return i.stage == 0).size() and perfect
			and game.time_left > t0, "ramassage : toute l'étape ramassée, prime d'étape parfaite, temps gagné",
			"%d ramassés, parfait %s" % [got, perfect])

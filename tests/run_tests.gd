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

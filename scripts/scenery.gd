class_name Scenery
extends RefCounted
## Décors propres aux ambiances (immeubles, maisons, port et usines, tunnels)
## et signalisation des bifurcations (terre-plein, panneaux de direction).
## Appelé par RoadBuilder.build_chunk ; s'appuie sur ses primitives.

const WINDOW_WARM := Color(1.0, 0.8, 0.48)
const WINDOW_COOL := Color(0.7, 0.85, 1.0)
const BEACON := Color(1.0, 0.1, 0.05)
const LEFT_SIGN := Color(0.1, 0.45, 0.25)
const RIGHT_SIGN := Color(0.12, 0.3, 0.62)


## Construit les décors du tronçon [s0, s1) ; renvoie les textes 3D à ajouter.
static func build(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, index: int,
		s0: float, s1: float) -> Array:
	var labels := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([index, b._seed, "decor"])
	var th := b._theme
	if th.get("buildings", 0.0) > 0.0:
		_towers(b, env, glow, rng, s0, s1)
	if th.get("houses", 0.0) > 0.0:
		_houses(b, env, glow, rng, s0, s1)
	if th.get("industry", 0.0) > 0.0:
		_industry(b, env, glow, rng, s0, s1, th.get("water", 0) != 0)
	_tunnels(b, env, glow, s0, s1)
	for k in RouteMap.STAGES.size() - 1:
		var f := RouteMap.fork_s(k)
		_divider(b, env, glow, f, s0, s1)
		var pre := f - 600.0
		if pre >= s0 and pre < s1:
			labels.append_array(_fork_signs(b, env, glow, pre, k, true))
		if f >= s0 and f < s1:
			labels.append_array(_fork_signs(b, env, glow, f, k, false))
	return labels


## Noms des deux directions à la bifurcation k (gauche, droite).
static func fork_names(k: int, choices: Array) -> Array:
	var n := RouteMap.node_of(k, choices)
	if k == RouteMap.STAGES.size() - 2:
		return [RouteMap.ENDINGS[n], RouteMap.ENDINGS[n + 1]]
	var next: Array = RouteMap.STAGES[k + 1]
	return [RouteMap.THEMES[next[n]]["name"], RouteMap.THEMES[next[n + 1]]["name"]]


# --- Ville -------------------------------------------------------------------

static func _towers(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, rng: RandomNumberGenerator,
		s0: float, s1: float) -> void:
	for side in [-1.0, 1.0]:
		var s := s0 + rng.randf_range(0.0, 10.0)
		while s < s1:
			var w := rng.randf_range(10.0, 18.0)
			var d := rng.randf_range(10.0, 16.0)
			var h := rng.randf_range(18.0, 64.0)
			var x: float = side * rng.randf_range(19.0, 40.0)
			if b._station_flat(s, x) <= 0.0 and not b.in_tunnel(s):
				var g := b.ground_height(s, x)
				var yaw := b.track.yaw_at(s)
				var tone := rng.randf_range(0.05, 0.09)
				b._box(env, b._road_pos(s, x, g), yaw, Vector3(w, h - g, d), Color(tone, tone, tone * 1.25), 0.05)
				var col := WINDOW_WARM if rng.randf() < 0.6 else WINDOW_COOL
				var face_x: float = x - side * (w * 0.5 + 0.06)
				var y := 3.0
				while y < h - 2.0:
					var ws := s - d * 0.5 + 1.6
					while ws < s + d * 0.5 - 1.0:
						if rng.randf() < 0.32:
							_window(b, glow, ws, face_x, g + y, Vector2(1.0, 1.3), col, 0.75)
						ws += 2.6
					y += 3.4
				if h > 40.0:
					Halo.add(b._halo, b._road_pos(s, x, g + h + 1.0), 1.6, BEACON, 0.6)
			s += d + rng.randf_range(4.0, 14.0)


static func _houses(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, rng: RandomNumberGenerator,
		s0: float, s1: float) -> void:
	for side in [-1.0, 1.0]:
		var s := s0 + rng.randf_range(0.0, 8.0)
		while s < s1:
			if rng.randf() < 0.7:
				var x: float = side * rng.randf_range(14.0, 26.0)
				if b._station_flat(s, x) <= 0.0:
					var g := b.ground_height(s, x)
					var yaw := b.track.yaw_at(s)
					var wall := Color(0.24, 0.21, 0.19) * rng.randf_range(0.8, 1.2)
					b._box(env, b._road_pos(s, x, g), yaw, Vector3(7.0, 3.2, 8.0), wall, 0.15)
					# Toit à deux pans, faîtage parallèle à la route.
					var roof := Color(0.22, 0.08, 0.07) * rng.randf_range(0.7, 1.1)
					var eave_l := b._road_pos(s - 4.2, x - 3.8, g + 3.2)
					var eave_r := b._road_pos(s - 4.2, x + 3.8, g + 3.2)
					var ridge := b._road_pos(s - 4.2, x, g + 5.4)
					var fwd := b.track.forward_at(s) * 8.4
					var lit := b.lamp_light(s, x) * 0.5
					b._quad(env, [eave_l, ridge, ridge + fwd, eave_l + fwd], [roof, roof, roof, roof], [lit, lit, lit, lit])
					b._quad(env, [ridge, eave_r, eave_r + fwd, ridge + fwd], [roof, roof, roof, roof], [lit, lit, lit, lit])
					var face_x: float = x - side * 3.56
					for k in rng.randi_range(0, 2):
						_window(b, glow, s + rng.randf_range(-2.5, 2.5), face_x, g + 1.6, Vector2(1.1, 1.0), WINDOW_WARM, 0.85)
					if rng.randf() < 0.3:
						Halo.add(b._halo, b._road_pos(s + 3.0, face_x, g + 2.4), 1.2, WINDOW_WARM, 0.4)
			s += rng.randf_range(14.0, 22.0)


# --- Port et usines ----------------------------------------------------------

static func _industry(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, rng: RandomNumberGenerator,
		s0: float, s1: float, port: bool) -> void:
	var colors := [Color(0.42, 0.14, 0.08), Color(0.1, 0.22, 0.4), Color(0.12, 0.3, 0.18),
			Color(0.45, 0.45, 0.47), Color(0.5, 0.35, 0.1)]
	var land_side := -1.0 if port else 1.0
	# Conteneurs empilés côté terre.
	var s := s0 + rng.randf_range(0.0, 6.0)
	while s < s1:
		var x: float = land_side * rng.randf_range(14.0, 22.0)
		if b._station_flat(s, x) <= 0.0 and rng.randf() < 0.7:
			var g := b.ground_height(s, x)
			var yaw := b.track.yaw_at(s)
			for level in rng.randi_range(1, 3):
				b._box(env, b._road_pos(s, x, g + level * 2.6), yaw, Vector3(2.4, 2.6, 12.0),
						colors[rng.randi_range(0, colors.size() - 1)], 0.2)
		s += 13.0
	# Port : une grue de quai tous les 300 m, côté eau. Usines : halls et cheminées.
	if port:
		for cs in b._every(300.0, 120.0, s0, s1):
			var yaw := b.track.yaw_at(cs)
			var steel := Color(0.55, 0.36, 0.1)
			for leg in [14.0, 26.0]:
				b._box(env, b._road_pos(cs, leg, -1.6), yaw, Vector3(1.2, 34.0, 1.2), steel, 0.1)
			b._box(env, b._road_pos(cs, 14.0, 32.0), yaw, Vector3(54.0, 2.0, 2.0), steel, 0.1)
			Halo.add(b._halo, b._road_pos(cs, -12.0, 34.0), 1.6, BEACON, 0.6)
			Halo.add(b._halo, b._road_pos(cs, 40.0, 34.0), 1.6, BEACON, 0.6)
	else:
		for fs in b._every(260.0, 60.0, s0, s1):
			var x := 38.0
			var g := b.ground_height(fs, x)
			var yaw := b.track.yaw_at(fs)
			b._box(env, b._road_pos(fs, x, g), yaw, Vector3(24.0, 13.0, 40.0), Color(0.12, 0.12, 0.13), 0.1)
			var face_x := x - 12.06
			for ws in range(-16, 17, 4):
				_window(b, glow, fs + ws, face_x, g + 9.0, Vector2(2.6, 1.2), WINDOW_COOL, 0.6)
			for cx in [x - 4.0, x + 6.0]:
				b._box(env, b._road_pos(fs + 12.0, cx, g + 13.0), yaw, Vector3(2.2, 22.0, 2.2), Color(0.2, 0.18, 0.17), 0.05)
				Halo.add(b._halo, b._road_pos(fs + 12.0, cx, g + 35.5), 1.4, BEACON, 0.6)
			# Torchère.
			Halo.add(b._halo, b._road_pos(fs - 14.0, x + 10.0, g + 26.0), 4.0, Color(1.0, 0.5, 0.12), 0.55)


# --- Tunnels -----------------------------------------------------------------

static func _tunnels(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, s0: float, s1: float) -> void:
	var wall := Color(0.3, 0.29, 0.28)
	var rock := Color(0.1, 0.1, 0.11)
	var lamp := Color(1.0, 0.62, 0.28)
	for i in b._steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		if not b.in_tunnel(sa):
			continue
		var la := b.lamp_light(sa, 8.0)
		var lb := b.lamp_light(sb, 8.0)
		for side in [-1.0, 1.0]:
			var x: float = 8.6 * side
			b._quad(env, [b._road_pos(sa, x, 0.0), b._road_pos(sb, x, 0.0), b._road_pos(sb, x, 6.2), b._road_pos(sa, x, 6.2)],
					[wall, wall, wall, wall], [la, lb, lb, la])
			b._quad(env, [b._road_pos(sa, x, 6.2), b._road_pos(sb, x, 6.2), b._road_pos(sb, 3.0 * side, 7.0),
					b._road_pos(sa, 3.0 * side, 7.0)], [wall, wall, wall, wall], [la * 0.6, lb * 0.6, lb * 0.6, la * 0.6])
		b._quad(env, [b._road_pos(sa, -3.0, 7.0), b._road_pos(sb, -3.0, 7.0), b._road_pos(sb, 3.0, 7.0),
				b._road_pos(sa, 3.0, 7.0)], [rock, rock, rock, rock], [0.0, 0.0, 0.0, 0.0])
		if posmod(int(sa), 8) == 0:
			var yaw := b.track.yaw_at(sa)
			for side in [-1.0, 1.0]:
				b._glow_box(glow, b._road_pos(sa, 4.0 * side, 6.75), yaw, Vector3(0.6, 0.12, 1.4), lamp, 1.0)
		# Entrée : cadre de béton éclairé dans un flanc de montagne en gradins.
		if not b.in_tunnel(sa - Track.STEP):
			var yaw := b.track.yaw_at(sa)
			for side in [-1.0, 1.0]:
				b._box(env, b._road_pos(sa, 9.4 * side, 0.0), yaw, Vector3(1.6, 8.6, 1.6), wall, 0.7)
				for step in 4:
					var w := 70.0 - step * 14.0
					b._box(env, b._road_pos(sa + step * 6.0, (10.2 + w * 0.5) * side, -2.0), yaw,
							Vector3(w, 12.0 + step * 7.0, 6.0), rock * (1.0 + step * 0.15), 0.03)
			b._box(env, b._road_pos(sa, 0.0, 7.0), yaw, Vector3(20.4, 1.6, 1.6), wall, 0.7)
			b._box(env, b._road_pos(sa + 3.0, 0.0, 8.6), yaw, Vector3(20.4, 18.0, 6.0), rock, 0.03)
			Halo.add(b._halo, b._road_pos(sa, 0.0, 7.9) + b.track.forward_at(sa) * -1.0, 2.0, lamp, 0.5)


# --- Bifurcations -------------------------------------------------------------

## Terre-plein central entre fork + DIVIDER_START et fork + DIVIDER_END, avec
## son nez à chevrons jaunes.
static func _divider(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, f: float, s0: float, s1: float) -> void:
	var a := f + RouteMap.DIVIDER_START
	var e := f + RouteMap.DIVIDER_END
	if e <= s0 or a >= s1:
		return
	var concrete := Color(0.55, 0.55, 0.53)
	var hw := RouteMap.DIVIDER_HALF_WIDTH
	var s := maxf(a, s0)
	while s < minf(e, s1):
		var yaw := b.track.yaw_at(s + 2.0)
		b._box(env, b._road_pos(s + 2.0, 0.0, 0.0), yaw, Vector3(hw * 2.0, 0.9, 4.0), concrete, b.lamp_light(s, 0.0))
		if posmod(int(s - a), 12) == 0:
			b._glow_box(glow, b._road_pos(s, 0.0, 0.92), yaw, Vector3(0.3, 0.08, 0.2), Color(1.0, 0.6, 0.1), 1.0)
		s += 4.0
	if a >= s0 and a < s1:
		var yaw := b.track.yaw_at(a)
		var back := b.track.forward_at(a) * -0.3
		# Panneau à chevrons et balises clignotantes (halos).
		b._box(env, b._road_pos(a, 0.0, 0.0), yaw, Vector3(0.2, 2.2, 0.2), Color(0.3, 0.3, 0.3), 0.3)
		b._glow_box(glow, b._road_pos(a, 0.0, 1.0) + back, yaw, Vector3(2.0, 1.1, 0.05), Color(1.0, 0.82, 0.1), 1.0)
		for i in 3:
			b._glow_box(glow, b._road_pos(a, -0.6 + i * 0.6, 1.05) + back * 1.2, yaw, Vector3(0.18, 0.9, 0.05),
					Color(0.05, 0.05, 0.05), 1.0)
		for side in [-1.0, 1.0]:
			Halo.add(b._halo, b._road_pos(a, 1.0 * side, 2.3), 1.5, Color(1.0, 0.75, 0.1), 0.7)


## Panneaux de direction au-dessus de la route : pré-annonce à 600 m (avec son
## propre portique) ou sous le portique de la station.
static func _fork_signs(b: RoadBuilder, env: SurfaceTool, glow: SurfaceTool, s: float, k: int,
		own_gantry: bool) -> Array:
	var yaw := b.track.yaw_at(s)
	var names := fork_names(k, b.choices)
	var back := b.track.forward_at(s) * -0.5
	var h := 7.0 if own_gantry else 4.9
	if own_gantry:
		var metal := Color(0.3, 0.31, 0.34)
		for side in [-1.0, 1.0]:
			b._box(env, b._road_pos(s, 9.0 * side, 0.0), yaw, Vector3(0.5, 8.6, 0.5), metal, 0.5)
		b._box(env, b._road_pos(s, 0.0, 8.4), yaw, Vector3(18.4, 0.4, 0.4), metal, 0.5)
	var labels := []
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var col: Color = LEFT_SIGN if i == 0 else RIGHT_SIGN
		var x := 4.3 * side
		b._glow_box(glow, b._road_pos(s, x, h) + back, yaw, Vector3(8.2, 1.5, 0.06), col, 0.55)
		b._box(env, b._road_pos(s, x, h - 0.1), yaw, Vector3(8.4, 1.7, 0.2), Color(0.04, 0.04, 0.05), 0.1)
		var label := Label3D.new()
		label.text = ("< " + names[i]) if i == 0 else (names[i] + " >")
		label.font = Hud.arcade_font()
		label.font_size = 32
		label.pixel_size = 0.013
		label.outline_size = 0
		label.modulate = Color(1, 1, 1)
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		label.transform = b.track.transform_at(s, x, h + 0.75)
		label.position += back * 1.3
		labels.append(label)
	return labels


## Fenêtre lumineuse : un quad vertical face à la route, centré en (s, x, y).
static func _window(b: RoadBuilder, glow: SurfaceTool, s: float, x: float, y: float, size: Vector2,
		color: Color, strength: float) -> void:
	var fwd := b.track.forward_at(s) * (size.x * 0.5)
	var c := b._road_pos(s, x, y)
	var up := Vector3.UP * (size.y * 0.5)
	var p := [c - fwd - up, c - fwd + up, c + fwd + up, c + fwd - up]
	for i in [0, 1, 2, 0, 2, 3]:
		glow.set_color(Color(color.r, color.g, color.b, strength))
		glow.set_uv(Vector2(0, 1))
		glow.add_vertex(p[i])

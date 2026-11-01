class_name RoadBuilder
extends RefCounted
## Construit la route par tronçons de CHUNK_LENGTH mètres : chaussée, accotements,
## glissières, terrain, arbres, lampadaires et leurs reflets sur la route mouillée.
## Tout est en géométrie low-poly à couleurs de sommet ; la lumière des
## lampadaires est précalculée dans l'alpha des couleurs (voir ps1_lit.gdshader).

const CHUNK_LENGTH := 100.0
const LAMP_SPACING := 48.0
const LAMP_SIGMA := 9.0          # étalement de la flaque de lumière (m)
const LAMP_POOL_X := 5.0         # centre de la flaque, côté lampadaire
const LAMP_POLE_X := 9.2
const LAMP_HEIGHT := 9.0
const LAMP_COLOR := Color(1.0, 0.62, 0.28)
const GROUND_COLUMNS := [8.0, 11.0, 16.0, 24.0, 34.0, 46.0, 60.0, 80.0]
const ROAD_COLUMNS := [-6.0, -3.0, 0.0, 3.0, 6.0]

const STATION_SITE_BACK := 22.0   # la station est juste avant le portique
const STATION_SITE_HALF := 34.0   # demi-longueur de l'aire de la station
const STATION_LIGHT := Color(0.85, 0.95, 1.0)
const SIGN_COLOR := Color(1.0, 0.45, 0.12)

var track: Track
## Positions (s) des stations-service et de l'arrivée (portiques).
var stations := PackedFloat32Array()
var arrival_s := -1.0
var road_material: ShaderMaterial
var env_material: ShaderMaterial
var glow_material: ShaderMaterial

var _seed := 1
var _noise := FastNoiseLite.new()


func _init(p_track: Track, seed: int = 1) -> void:
	track = p_track
	_seed = seed
	_noise.seed = seed
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	var lit := load("res://shaders/ps1_lit.gdshader")
	road_material = ShaderMaterial.new()
	road_material.shader = lit
	road_material.set_shader_parameter("albedo_tex", make_road_texture())
	road_material.set_shader_parameter("affine_strength", 0.3)
	env_material = ShaderMaterial.new()
	env_material.shader = lit
	env_material.set_shader_parameter("affine_strength", 0.0)
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://shaders/ps1_glow.gdshader")


# --- Lumière précalculée ----------------------------------------------------

## Le lampadaire numéro k existe-t-il (certains sont en panne), et de quel côté ?
## Renvoie 0 si éteint, sinon -1 (gauche) ou 1 (droite).
func lamp_side(k: int) -> int:
	if _hash(k) < 0.12:
		return 0
	return 1 if posmod(k, 2) == 0 else -1


## Intensité de la lumière des lampadaires au point (s, x), 0..~1.
func lamp_light(s: float, x: float) -> float:
	var k0 := int(floor(s / LAMP_SPACING))
	var total := 0.0
	for k in range(k0 - 1, k0 + 3):
		var side := lamp_side(k)
		if side == 0:
			continue
		var ds := s - float(k) * LAMP_SPACING
		var dx := x - side * LAMP_POOL_X
		total += exp(-(ds * ds + dx * dx * 1.6) / (2.0 * LAMP_SIGMA * LAMP_SIGMA))
	# L'auvent de la station inonde la route et l'aire de lumière.
	var site := _station_site_offset(s)
	if site < INF:
		var sx := x - 22.0
		total += 1.3 * exp(-(site * site * 0.5 + sx * sx * 0.25) / (2.0 * 14.0 * 14.0))
	for g in _gantries_near(s):
		var dg: float = s - g
		total += 0.8 * exp(-(dg * dg + x * x * 0.3) / (2.0 * 7.0 * 7.0))
	return clampf(total, 0.0, 1.0)


## Distance (m, signée) au centre de l'aire de station la plus proche, INF si loin.
func _station_site_offset(s: float) -> float:
	for st in stations:
		var d := s - (st - STATION_SITE_BACK)
		if absf(d) < STATION_SITE_HALF + 30.0:
			return d
	return INF


func _gantries_near(s: float) -> Array:
	var out := []
	for st in stations:
		if absf(s - st) < 40.0:
			out.append(st)
	if arrival_s > 0.0 and absf(s - arrival_s) < 40.0:
		out.append(arrival_s)
	return out


## Poids (0..1) de l'aire plate et goudronnée de la station au point (s, x).
func _station_flat(s: float, x: float) -> float:
	var site := _station_site_offset(s)
	if site == INF or x < 8.0:
		return 0.0
	return smoothstep(STATION_SITE_HALF + 12.0, STATION_SITE_HALF, absf(site)) * smoothstep(56.0, 46.0, x)


## Hauteur du terrain par rapport à la route, à x mètres du centre.
func ground_height(s: float, x: float) -> float:
	var ax := absf(x)
	if ax <= 8.0:
		return 0.0
	if ax <= 11.0:
		return lerpf(0.0, -1.0, (ax - 8.0) / 3.0)
	var p := track.point_at(s) + track.right_at(s) * x
	var relief := smoothstep(11.0, 80.0, ax) * 22.0
	var h := -1.0 + (_noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5) * relief
	return lerpf(h, 0.0, _station_flat(s, x))


# --- Construction ------------------------------------------------------------

func build_chunk(index: int) -> MeshInstance3D:
	var s0 := float(index) * CHUNK_LENGTH
	var s1 := s0 + CHUNK_LENGTH
	track.ensure(s1 + LAMP_SPACING)
	var road := _new_tool()
	var env := _new_tool()
	var glow := _new_tool()
	_build_road(road, s0, s1)
	_build_shoulders_and_ground(env, s0, s1)
	_build_rails(env, s0, s1)
	_build_lamps(env, glow, s0, s1)
	_build_trees(env, index, s0, s1)
	var labels := []
	for st in stations:
		if st - STATION_SITE_BACK - STATION_SITE_HALF < s1 and st + 10.0 >= s0:
			_build_station(env, glow, st, s0, s1)
		if st >= s0 and st < s1:
			labels.append(_build_gantry(env, glow, st, "STATION %d" % (stations.find(st) + 1)))
		var sign_s := st - 1000.0
		if sign_s >= s0 and sign_s < s1:
			labels.append(_build_sign(env, sign_s, "STATION\n1 km"))
	if arrival_s >= s0 and arrival_s < s1:
		labels.append(_build_gantry(env, glow, arrival_s, "AUBE"))

	var mesh := ArrayMesh.new()
	for part in [[road, road_material], [env, env_material], [glow, glow_material]]:
		var arrays: Array = part[0].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_VERTEX].is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Chunk%d" % index
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in labels:
		mi.add_child(l)
	return mi


# --- Stations et portiques ---------------------------------------------------

## Station-service à droite, juste avant le portique : auvent lumineux, pompes,
## boutique, totem. Seules les pièces dont le pied tombe dans [s0, s1) sont
## construites, pour ne rien dessiner deux fois d'un tronçon à l'autre.
func _build_station(env: SurfaceTool, glow: SurfaceTool, st: float, s0: float, s1: float) -> void:
	var c := st - STATION_SITE_BACK
	var pieces := []
	# Auvent : piliers, toit, sous-face lumineuse.
	for ps in [c - 10.0, c + 10.0]:
		for px in [15.0, 29.0]:
			pieces.append(["box", ps, px, 0.0, Vector3(0.5, 5.6, 0.5), Color(0.75, 0.75, 0.78), 0.9])
	pieces.append(["roof", c, 22.0])
	# Pompes.
	for ps in [c - 6.0, c, c + 6.0]:
		pieces.append(["box", ps, 22.0, 0.0, Vector3(0.8, 1.6, 1.2), Color(0.8, 0.18, 0.12), 0.9])
		pieces.append(["glow", ps, 21.55, 1.0, Vector3(0.05, 0.35, 0.6), STATION_LIGHT, 0.8])
	# Boutique et sa vitrine.
	pieces.append(["box", c + 4.0, 41.0, 0.0, Vector3(9.0, 4.0, 22.0), Color(0.55, 0.53, 0.5), 0.5])
	pieces.append(["glow", c + 4.0, 36.45, 0.6, Vector3(0.05, 2.0, 16.0), Color(1.0, 0.85, 0.55), 0.9])
	# Totem lumineux au bord de la route.
	pieces.append(["box", c - 30.0, 11.5, 0.0, Vector3(0.4, 11.0, 0.4), Color(0.3, 0.3, 0.32), 0.4])
	pieces.append(["glow", c - 30.0, 11.5, 11.0, Vector3(0.3, 2.6, 3.4), SIGN_COLOR, 1.0])
	for p in pieces:
		var ps: float = p[1]
		if ps < s0 or ps >= s1:
			continue
		var yaw := track.yaw_at(ps)
		match p[0]:
			"box":
				_box(env, _road_pos(ps, p[2], p[3]), yaw, p[4], p[5], p[6])
			"glow":
				_glow_box(glow, _road_pos(ps, p[2], p[3]), yaw, p[4], p[5], p[6])
			"roof":
				_box(env, _road_pos(ps, p[2], 5.6), yaw, Vector3(18.0, 0.8, 28.0), Color(0.9, 0.9, 0.92), 0.7)
				# Bandeau orange sur la tranche de l'auvent, côté route.
				_glow_box(glow, _road_pos(ps, 12.95, 5.65), yaw, Vector3(0.1, 0.7, 28.0), SIGN_COLOR, 0.9)
				# Sous-face : un grand aplat lumineux tourné vers le bas.
				_glow_box(glow, _road_pos(ps, 22.0, 5.55), yaw, Vector3(17.0, 0.02, 27.0), STATION_LIGHT, 0.55)


## Portique au-dessus de la route (point de passage), avec son texte.
func _build_gantry(env: SurfaceTool, glow: SurfaceTool, s: float, text: String) -> Label3D:
	var yaw := track.yaw_at(s)
	var metal := Color(0.35, 0.36, 0.4)
	for side in [-1.0, 1.0]:
		_box(env, _road_pos(s, 9.0 * side, 0.0), yaw, Vector3(0.6, 7.2, 0.6), metal, 0.8)
	_box(env, _road_pos(s, 0.0, 6.4), yaw, Vector3(18.6, 1.6, 0.8), Color(0.08, 0.09, 0.12), 0.4)
	# Rangée de feux en damier sous la poutre.
	for i in 12:
		var x := -8.25 + i * 1.5
		var col := Color(1.0, 0.75, 0.25) if i % 2 == 0 else Color(1.0, 1.0, 0.95)
		_glow_box(glow, _road_pos(s, x, 6.1) + track.forward_at(s) * -0.45, yaw, Vector3(0.6, 0.25, 0.05), col, 1.0)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = Color(1.0, 0.86, 0.55)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.transform = track.transform_at(s, 0.0, 7.2)
	label.position += track.forward_at(s) * -0.45
	return label


## Panneau d'annonce sur le bas-côté droit.
func _build_sign(env: SurfaceTool, s: float, text: String) -> Label3D:
	var yaw := track.yaw_at(s)
	_box(env, _road_pos(s, 10.0, 0.0), yaw, Vector3(0.2, 3.0, 0.2), Color(0.3, 0.3, 0.32), 0.3)
	_box(env, _road_pos(s, 10.0, 3.0), yaw, Vector3(3.6, 2.0, 0.15), Color(0.1, 0.25, 0.55), 0.6)
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = Color(0.95, 0.95, 1.0)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.transform = track.transform_at(s, 10.0, 4.0)
	label.position += track.forward_at(s) * -0.1
	return label


func _new_tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _steps(s0: float, s1: float) -> int:
	return int(round((s1 - s0) / Track.STEP))


func _vertex(st: SurfaceTool, pos: Vector3, color: Color, light: float, uv := Vector2.ZERO) -> void:
	st.set_color(Color(color.r, color.g, color.b, light))
	st.set_uv(uv)
	st.set_normal(Vector3.UP)
	st.add_vertex(pos)


## Quadrilatère a-b-c-d (sens horaire vu de la face visible).
func _quad(st: SurfaceTool, p: Array, colors: Array, lights: Array, uvs: Array = []) -> void:
	var n: Vector3 = (p[3] - p[0]).cross(p[1] - p[0]).normalized()
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(colors[i].r, colors[i].g, colors[i].b, lights[i]))
		st.set_uv(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
		st.set_normal(n)
		st.add_vertex(p[i])


func _road_pos(s: float, x: float, h: float = 0.0) -> Vector3:
	return track.point_at(s) + track.right_at(s) * x + Vector3.UP * h


func _build_road(st: SurfaceTool, s0: float, s1: float) -> void:
	var tint := Color(0.5, 0.5, 0.56)
	for i in _steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		for c in ROAD_COLUMNS.size() - 1:
			var xa: float = ROAD_COLUMNS[c]
			var xb: float = ROAD_COLUMNS[c + 1]
			var pts := [_road_pos(sa, xa), _road_pos(sb, xa), _road_pos(sb, xb), _road_pos(sa, xb)]
			var lights := [lamp_light(sa, xa), lamp_light(sb, xa), lamp_light(sb, xb), lamp_light(sa, xb)]
			var uvs := [
				Vector2((xa + 6.0) / 12.0, sa / 12.0), Vector2((xa + 6.0) / 12.0, sb / 12.0),
				Vector2((xb + 6.0) / 12.0, sb / 12.0), Vector2((xb + 6.0) / 12.0, sa / 12.0)]
			_quad(st, pts, [tint, tint, tint, tint], lights, uvs)


func _build_shoulders_and_ground(st: SurfaceTool, s0: float, s1: float) -> void:
	var gravel := Color(0.22, 0.21, 0.2)
	var grass_near := Color(0.07, 0.11, 0.08)
	var grass_far := Color(0.04, 0.06, 0.07)
	for i in _steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		for side in [-1.0, 1.0]:
			# Accotement de 6 à 8 m.
			var xs := [6.0 * side, 8.0 * side]
			_strip(st, sa, sb, xs[0], xs[1], 0.0, 0.0, gravel, gravel, side)
			# Terrain.
			for c in GROUND_COLUMNS.size() - 1:
				var xa: float = GROUND_COLUMNS[c] * side
				var xb: float = GROUND_COLUMNS[c + 1] * side
				var ca := grass_near.lerp(grass_far, float(c) / (GROUND_COLUMNS.size() - 1))
				var cb := grass_near.lerp(grass_far, float(c + 1) / (GROUND_COLUMNS.size() - 1))
				_strip(st, sa, sb, xa, xb, 0.0, 0.0, ca, cb, side, true)


## Bande de terrain entre xa et xb (xa plus près de la route), sens selon le côté.
func _strip(st: SurfaceTool, sa: float, sb: float, xa: float, xb: float, ha: float, hb: float,
		ca: Color, cb: Color, side: float, use_ground := false) -> void:
	var haa := ground_height(sa, xa) if use_ground else ha
	var hab := ground_height(sb, xa) if use_ground else ha
	var hba := ground_height(sa, xb) if use_ground else hb
	var hbb := ground_height(sb, xb) if use_ground else hb
	var p := [_road_pos(sa, xa, haa), _road_pos(sb, xa, hab), _road_pos(sb, xb, hbb), _road_pos(sa, xb, hba)]
	var l := [lamp_light(sa, xa), lamp_light(sb, xa), lamp_light(sb, xb), lamp_light(sa, xb)]
	var c := [ca, ca, cb, cb]
	if use_ground:
		# Aire de la station : goudron clair au lieu de l'herbe.
		var tarmac := Color(0.3, 0.3, 0.33)
		var pts := [[sa, xa], [sb, xa], [sb, xb], [sa, xb]]
		for i in 4:
			c[i] = c[i].lerp(tarmac, _station_flat(pts[i][0], pts[i][1]))
	if side < 0.0:
		p = [p[0], p[3], p[2], p[1]]
		l = [l[0], l[3], l[2], l[1]]
		c = [c[0], c[3], c[2], c[1]]
	_quad(st, p, c, l)


func _build_rails(st: SurfaceTool, s0: float, s1: float) -> void:
	var metal := Color(0.45, 0.47, 0.5)
	var post := Color(0.25, 0.25, 0.27)
	for i in _steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		for side in [-1.0, 1.0]:
			var x: float = 8.0 * side
			var lo := 0.45
			var hi := 0.78
			var a0 := _road_pos(sa, x, lo)
			var b0 := _road_pos(sb, x, lo)
			var b1 := _road_pos(sb, x, hi)
			var a1 := _road_pos(sa, x, hi)
			var la := lamp_light(sa, x)
			var lb := lamp_light(sb, x)
			var face := [a0, b0, b1, a1] if side > 0.0 else [a0, a1, b1, b0]
			var lights := [la, lb, lb, la] if side > 0.0 else [la, la, lb, lb]
			_quad(st, face, [metal, metal, metal, metal], lights)
			if i % 2 == 0:
				_box(st, _road_pos(sa, x + 0.15 * side, 0.0), track.yaw_at(sa), Vector3(0.12, 0.8, 0.12), post, la)


func _build_lamps(env: SurfaceTool, glow: SurfaceTool, s0: float, s1: float) -> void:
	var pole := Color(0.2, 0.21, 0.23)
	var k0 := int(ceil(s0 / LAMP_SPACING))
	var k1 := int(floor((s1 - 0.001) / LAMP_SPACING))
	for k in range(k0, k1 + 1):
		var side := lamp_side(k)
		var s := float(k) * LAMP_SPACING
		var yaw := track.yaw_at(s)
		var light_side := side if side != 0 else (1 if posmod(k, 2) == 0 else -1)
		var px := LAMP_POLE_X * light_side
		var on := 0.6 if side != 0 else 0.08
		# Mât et bras.
		_box(env, _road_pos(s, px, 0.0), yaw, Vector3(0.22, LAMP_HEIGHT, 0.22), pole, on)
		var arm_x := (LAMP_POLE_X + 6.5) * 0.5 * light_side
		_box(env, _road_pos(s, arm_x, LAMP_HEIGHT - 0.2), yaw, Vector3(LAMP_POLE_X - 6.5, 0.15, 0.15), pole, on)
		if side == 0:
			continue
		# Ampoule.
		_glow_box(glow, _road_pos(s, 6.5 * side, LAMP_HEIGHT - 0.45), yaw, Vector3(0.9, 0.25, 0.5), LAMP_COLOR, 1.0)
		# Reflet sur la route mouillée, étiré vers la caméra (derrière, s plus petit).
		_reflection(glow, s, LAMP_POOL_X * side * 0.9, 18.0, 1.6, LAMP_COLOR, 0.55)


## Reflet allongé couché sur la chaussée : intense près de la source (s_src),
## s'éteint sur `length` mètres vers l'arrière.
func _reflection(st: SurfaceTool, s_src: float, x: float, length: float, width: float,
		color: Color, strength: float) -> void:
	var n := int(ceil(length / Track.STEP))
	for i in n:
		var sa := s_src - i * Track.STEP
		var sb := sa - Track.STEP
		var ga := 1.0 - float(i) / n
		var gb := 1.0 - float(i + 1) / n
		for half in [-1.0, 1.0]:
			var xc := x
			var xe: float = x + half * width * 0.5
			var p := [_road_pos(sa, xc, 0.03), _road_pos(sa, xe, 0.03), _road_pos(sb, xe, 0.03), _road_pos(sb, xc, 0.03)]
			var uvs := [Vector2(0, ga), Vector2(0, 0), Vector2(0, 0), Vector2(0, gb)]
			_quad(st, p, [color, color, color, color], [strength, strength, strength, strength], uvs)


func _build_trees(st: SurfaceTool, index: int, s0: float, s1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(index, _seed))
	var s := s0
	while s < s1:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.55:
				var x: float = side * rng.randf_range(12.0, 62.0)
				var ts := s + rng.randf_range(0.0, 6.0)
				if _station_flat(ts, x) > 0.0 or _station_flat(ts, x + 8.0) > 0.0:
					continue
				var h := rng.randf_range(6.0, 13.0)
				var base := _road_pos(ts, x, ground_height(ts, x) - 0.5)
				var shade := rng.randf_range(0.7, 1.2)
				_tree(st, base, h, Color(0.035, 0.07, 0.06) * shade, lamp_light(ts, x) * 0.7)
		s += 6.0


func _tree(st: SurfaceTool, base: Vector3, height: float, color: Color, light: float) -> void:
	var sides := 5
	var tiers := [[0.25, 0.75, height * 0.32], [0.55, 1.0, height * 0.22]]
	for t in tiers:
		var y0: float = height * t[0]
		var y1: float = height * t[1]
		var r: float = t[2]
		var apex := base + Vector3.UP * y1
		var top_light := light * 0.5
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := base + Vector3(cos(a0) * r, y0, sin(a0) * r)
			var p1 := base + Vector3(cos(a1) * r, y0, sin(a1) * r)
			var n := (p1 - p0).cross(apex - p0).normalized() * -1.0
			for v in [[p0, light], [apex, top_light], [p1, light]]:
				st.set_color(Color(color.r, color.g, color.b, v[1]))
				st.set_uv(Vector2.ZERO)
				st.set_normal(n)
				st.add_vertex(v[0])


## Pavé posé au sol (base au centre de la face du bas), orienté selon la route.
func _box(st: SurfaceTool, base: Vector3, yaw: float, size: Vector3, color: Color, light: float) -> void:
	var b := Basis(Vector3.UP, -yaw)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := []
	for y in [0.0, size.y]:
		for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			c.append(base + b * Vector3(corner.x, y, corner.y))
	var cols := [color, color, color, color]
	var lights := [light, light, light, light]
	# Côtés puis dessus (le dessous ne se voit jamais).
	_quad(st, [c[0], c[1], c[5], c[4]], cols, lights)
	_quad(st, [c[1], c[2], c[6], c[5]], cols, lights)
	_quad(st, [c[2], c[3], c[7], c[6]], cols, lights)
	_quad(st, [c[3], c[0], c[4], c[7]], cols, lights)
	_quad(st, [c[4], c[5], c[6], c[7]], cols, lights)


func _glow_box(st: SurfaceTool, base: Vector3, yaw: float, size: Vector3, color: Color, strength: float) -> void:
	var b := Basis(Vector3.UP, -yaw)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := []
	for y in [0.0, size.y]:
		for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			c.append(base + b * Vector3(corner.x, y, corner.y))
	var cols := [color, color, color, color]
	var lights := [strength, strength, strength, strength]
	var uvs := [Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)]
	for f in [[0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0], [0, 1, 2, 3]]:
		_quad(st, [c[f[0]], c[f[1]], c[f[2]], c[f[3]]], cols, lights, uvs)


## Texture d'asphalte 32×64 : grain, lignes de rive continues, deux lignes de
## voie en tirets (motif de 12 m : 4,5 m de trait, 7,5 m de vide).
static func make_road_texture() -> ImageTexture:
	var w := 48
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in h:
		for x in w:
			var g := 0.32 + rng.randf_range(-0.06, 0.06)
			img.set_pixel(x, y, Color(g, g, g * 1.04))
	var paint := Color(0.92, 0.9, 0.82)
	for y in h:
		for x in [1, w - 2]:
			img.set_pixel(x, y, paint)
		if y < int(h * 0.375):
			for lane in [w / 3, 2 * w / 3]:
				img.set_pixel(lane, y, paint)
	return ImageTexture.create_from_image(img)


func _hash(k: int) -> float:
	return float(hash(Vector2i(k, _seed * 31 + 5)) % 10000) / 10000.0

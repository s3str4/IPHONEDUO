class_name RoadBuilder
extends RefCounted
## Construit la route par tronçons de CHUNK_LENGTH mètres : chaussée, accotements,
## glissières, terrain, arbres, lampadaires et leurs reflets sur la route mouillée.
## Tout est en géométrie low-poly à couleurs de sommet ; la lumière des
## lampadaires est précalculée dans l'alpha des couleurs (voir night_surface.gdshader) :
## elle éclaire au loin, les lumières proches étant calculées par pixel.
##
## Chaque région suit l'ambiance de son tronçon (RouteMap.THEMES) : lampadaires
## sodium ou LED, sol, arbres, eau, tunnels, et les décors de Scenery.

const CHUNK_LENGTH := 100.0
## Écart de référence entre lampadaires (ambiance « autoroute »).
const LAMP_SPACING := 48.0
## Tunnels : longueur et écart (m) dans les ambiances qui en ont.
const TUNNEL_PERIOD := 760.0
const TUNNEL_OFFSET := 260.0
## Construction par étapes : le terrain d'un tronçon en autant de tranches.
const GROUND_SLICES := 8
const LAMP_SIGMA := 9.0          # étalement de la flaque de lumière (m)
const LAMP_POOL_X := 5.0         # centre de la flaque, côté lampadaire
const LAMP_POLE_X := 9.2
const LAMP_HEIGHT := 9.0
const LAMP_COLOR := Color(1.0, 0.3, 0.72)
const GROUND_COLUMNS := [8.0, 11.0, 16.0, 24.0, 34.0, 46.0, 60.0, 80.0]
const ROAD_COLUMNS := [-6.0, -3.0, 0.0, 3.0, 6.0]

const STATION_SITE_BACK := 22.0   # la station est juste avant le portique
const STATION_SITE_HALF := 34.0   # demi-longueur de l'aire de la station
const STATION_LIGHT := Color(0.85, 0.95, 1.0)
const SIGN_COLOR := Color(1.0, 0.45, 0.12)
const PYLON_SPACING := 150.0
const PYLON_X := -36.0
const PYLON_HEIGHT := 26.0
const BILLBOARD_SPACING := 900.0
const BRIDGE_SPACING := 1700.0
## Panneaux publicitaires : quelques indices pour l'histoire (M2).
const BILLBOARDS := [
	["MOTEL DE L'AUBE\n12 km", Color(0.9, 0.2, 0.35)],
	["RADIO NUIT\n98.4 FM", Color(0.2, 0.5, 0.95)],
	["CAFÉ\n24 H / 24", Color(0.95, 0.6, 0.15)],
	["VOUS N'ÊTES\nPAS SEUL", Color(0.25, 0.8, 0.6)],
	["LA MER\n> 40 km", Color(0.3, 0.75, 0.95)],
	["ELLE VOUS\nATTEND", Color(0.85, 0.3, 0.9)],
]

var track: Track
## Choix connus aux bifurcations : ils décident des ambiances.
var choices: Array = []
## Événements étranges de la partie (décors qui en dépendent), ou null.
var events: EventDirector
## Positions (s) des stations-service et de l'arrivée (portiques).
var stations := PackedFloat32Array()
var arrival_s := -1.0
var road_material: ShaderMaterial
var env_material: ShaderMaterial
var glow_material: ShaderMaterial
var ground_material: ShaderMaterial
var cone_material: ShaderMaterial

var _seed := 1
## Matériaux par couleur de lampadaire (la lumière précalculée en prend la teinte).
var _materials := {}
var water_material: ShaderMaterial
## Lampadaires du tronçon en construction (lamp_light est appelé par sommet).
var _lamp_cache := []
var _lamp_cache_from := 0.0
var _lamp_cache_to := 0.0
## Ambiance du tronçon en construction.
var _theme: Dictionary
var _memo_height := {}
var _memo_light := {}
## Terrain et cônes de lumière du tronçon en construction.
var _ground: SurfaceTool
var _cones: SurfaceTool
## Halos du tronçon en cours de construction.
var _halo: SurfaceTool
var _noise := FastNoiseLite.new()


func _init(p_track: Track, seed: int = 1) -> void:
	track = p_track
	_seed = seed
	_noise.seed = seed
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	var surface := load("res://shaders/night_surface.gdshader")
	road_material = ShaderMaterial.new()
	road_material.shader = surface
	road_material.set_shader_parameter("albedo_tex", load("res://assets/textures/road.png"))
	road_material.set_shader_parameter("wet", 0.9)
	# Reflets plus discrets : la route mouillée gênait la lecture (retour de test).
	road_material.set_shader_parameter("reflectivity", 0.5)
	road_material.set_shader_parameter("specular_strength", 0.05)
	road_material.set_shader_parameter("marking", 1.0)
	road_material.set_shader_parameter("marking_glow", Vector3(0.35, 0.75, 0.95))
	road_material.set_shader_parameter("ripples", 0.25)
	env_material = ShaderMaterial.new()
	env_material.shader = surface
	env_material.set_shader_parameter("wet", 0.25)
	env_material.set_shader_parameter("specular_strength", 0.25)
	ground_material = env_material.duplicate()
	ground_material.set_shader_parameter("wet", 0.1)
	# Synthwave : terrain sombre parcouru d'une grille néon.
	ground_material.set_shader_parameter("grid", 1.0)
	ground_material.set_shader_parameter("albedo_color", Color(0.45, 0.4, 0.55))
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://shaders/night_glow.gdshader")
	cone_material = ShaderMaterial.new()
	cone_material.shader = load("res://shaders/night_cone.gdshader")
	water_material = ShaderMaterial.new()
	water_material.shader = surface
	water_material.set_shader_parameter("wet", 1.0)
	water_material.set_shader_parameter("reflectivity", 1.0)
	water_material.set_shader_parameter("specular_strength", 1.2)
	water_material.set_shader_parameter("ripples", 0.6)
	_materials[RouteMap.THEMES["autoroute"]["lamp_color"]] = _tinted(RouteMap.THEMES["autoroute"]["lamp_color"])


## Matériaux route / décor / terrain teintés par la lumière des lampadaires.
func _tinted(c: Color) -> Array:
	var out := []
	for m in [road_material, env_material, ground_material]:
		var d: ShaderMaterial = m.duplicate()
		d.set_shader_parameter("baked_tint", Vector3(c.r, c.g, c.b))
		out.append(d)
	return out


## Ambiance du tronçon qui contient s.
func theme_at(s: float) -> Dictionary:
	return RouteMap.theme(RouteMap.stage_at(s), choices)


## Matériaux [route, décor, terrain] de l'ambiance (teinte de ses lampadaires).
func _materials_for(theme: Dictionary) -> Array:
	var c: Color = theme.get("lamp_color", LAMP_COLOR)
	if not _materials.has(c):
		_materials[c] = _tinted(c)
	return _materials[c]


# --- Lumière précalculée ----------------------------------------------------

## Le lampadaire numéro k existe-t-il (certains sont en panne), et de quel côté ?
## Renvoie 0 si éteint, sinon -1 (gauche) ou 1 (droite).
func lamp_side(k: int, stage: int = 0) -> int:
	if _hash(k + stage * 100003) < 0.12:
		return 0
	return 1 if posmod(k, 2) == 0 else -1


## Positions des lampadaires dans [s0, s1) : [s, côté (0 = en panne)].
func lamps_between(s0: float, s1: float) -> Array:
	var out := []
	var stage := RouteMap.stage_at(s0)
	while stage < RouteMap.STAGES.size():
		var r0 := RouteMap.region_start(stage)
		var r1 := RouteMap.region_start(stage + 1) if stage + 1 < RouteMap.STAGES.size() else INF
		var spacing: float = RouteMap.theme(stage, choices).get("lamps", LAMP_SPACING)
		if spacing > 0.0:
			var k := int(ceil((maxf(s0, r0) - r0) / spacing))
			while r0 + k * spacing < minf(s1, r1):
				var ls := r0 + k * spacing
				# Pas de lampadaire dans un tunnel ni sous un pont (sa tête toucherait le tablier).
				if not in_tunnel(ls) and not _under_bridge(ls, stage):
					out.append([ls, lamp_side(k, stage)])
				k += 1
		if r1 >= s1:
			break
		stage += 1
	return out


## Intensité de la lumière des lampadaires au point (s, x), 0..~1.
func lamp_light(s: float, x: float) -> float:
	var total := 0.0
	if in_tunnel(s):
		# Tunnel : rampe continue au plafond, qui pulse au rythme des lampes.
		return 0.55 + 0.3 * cos(s * TAU / 8.0) * (1.0 - absf(x) / 12.0)
	var lamps := _lamp_cache if s >= _lamp_cache_from and s < _lamp_cache_to \
			else lamps_between(s - 3.0 * LAMP_SIGMA, s + 3.0 * LAMP_SIGMA)
	for lamp in lamps:
		var side: int = lamp[1]
		var ds: float = s - lamp[0]
		if side == 0 or absf(ds) > 3.0 * LAMP_SIGMA:
			continue
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


func _under_bridge(s: float, stage: int) -> bool:
	if not RouteMap.theme(stage, choices).get("bridges", true):
		return false
	var nearest := roundf((s - 620.0) / BRIDGE_SPACING) * BRIDGE_SPACING + 620.0
	return absf(s - nearest) < 12.0


## La route est-elle sous un tunnel en s ?
func in_tunnel(s: float) -> bool:
	var stage := RouteMap.stage_at(s)
	if RouteMap.theme(stage, choices).get("tunnels", 0.0) <= 0.0:
		return false
	var r0 := RouteMap.region_start(stage)
	var r1 := RouteMap.fork_s(stage) if stage < RouteMap.STAGES.size() - 1 else arrival_s
	var d := s - r0 - TUNNEL_OFFSET
	if d < 0.0 or s > r1 - 600.0:
		return false
	return fmod(d, TUNNEL_PERIOD) < TUNNEL_PERIOD * RouteMap.theme(stage, choices).get("tunnels", 0.0)


## Côté de l'eau en s (-1, 1) ou 0.
func water_side(s: float) -> int:
	return int(theme_at(s).get("water", 0))


## Hauteur du terrain par rapport à la route, à x mètres du centre.
func ground_height(s: float, x: float) -> float:
	var ax := absf(x)
	if ax <= 8.0:
		return 0.0
	if ax <= 11.0:
		return lerpf(0.0, -1.0, (ax - 8.0) / 3.0)
	var p := track.point_at(s) + track.right_at(s) * x
	if water_side(s) != 0 and signf(x) == water_side(s) and _station_flat(s, x) <= 0.0:
		return -1.6
	var relief := smoothstep(11.0, 80.0, ax) * 12.0
	var h := -1.0 + (_noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5) * relief
	return lerpf(h, 0.0, _station_flat(s, x))


# --- Lumières proches (calculées par pixel) -----------------------------------

## Sources lumineuses entre s0 et s1 : [position, couleur, portée, intensité]
## (intensité négative : balise clignotante). Voir LightField.
func light_sources(s0: float, s1: float) -> Array:
	var out := []
	for lamp in lamps_between(s0, s1):
		if lamp[1] != 0:
			var c: Color = theme_at(lamp[0]).get("lamp_color", LAMP_COLOR)
			# Les LED blanches paraissent plus vives que le sodium : un peu moins fort.
			var power := 5.0 if c.b > 0.8 else 7.0
			out.append([_road_pos(lamp[0], 6.5 * lamp[1], LAMP_HEIGHT - 0.6), c, 36.0, power])
	var ts := ceilf(s0 / 8.0) * 8.0
	while ts < s1:
		if in_tunnel(ts) and ts < s0 + 160.0:
			out.append([_road_pos(ts, 0.0, 6.4), LAMP_COLOR, 14.0, 4.0])
		ts += 8.0
	for st in stations + PackedFloat32Array([arrival_s]):
		if st < s0 - 60.0 or st > s1 + 60.0:
			continue
		out.append([_road_pos(st, 0.0, 6.2), Color(1.0, 0.85, 0.6), 22.0, 5.0])
		if st == arrival_s:
			continue
		var empty := events != null and is_equal_approx(st, events.plan["station_vide"])
		var c := st - STATION_SITE_BACK
		for ps in [c - 9.0, c + 9.0]:
			out.append([_road_pos(ps, 20.0, 5.0), Color(0.35, 0.55, 1.0) if empty else STATION_LIGHT, 32.0, 7.0])
		out.append([_road_pos(c - 30.0, 11.5, 12.0), Color(0.3, 0.5, 1.0) if empty else SIGN_COLOR, 24.0, 4.0])
	for k in RouteMap.STAGES.size() - 1:
		var nose := RouteMap.fork_s(k) + RouteMap.DIVIDER_START
		if nose >= s0 and nose < s1:
			out.append([_road_pos(nose, 0.0, 2.0), Color(1.0, 0.75, 0.1), 16.0, -5.0])
	if theme_at(s0).get("bridges", true):
		for br in _every(BRIDGE_SPACING, 620.0, s0, s1):
			if not _near_checkpoint(br, 200.0) and not in_tunnel(br):
				out.append([_road_pos(br, 0.0, 3.0), Color(0.85, 0.95, 1.0), 12.0, 1.2])
	if theme_at(s0).get("billboards", true):
		for bs in _every(BILLBOARD_SPACING, 330.0, s0, s1):
			if not _near_checkpoint(bs, 160.0) and not in_tunnel(bs) and not _near_panneau(bs):
				var entry: Array = BILLBOARDS[posmod(int(bs / BILLBOARD_SPACING), BILLBOARDS.size())]
				out.append([_road_pos(bs, 13.0, 6.0), entry[1], 20.0, 3.5])
	if events != null:
		for ps in events.panneau_at(s0, s1):
			out.append([_road_pos(ps, 13.0, 6.0), Color(0.95, 0.25, 0.5), 20.0, 3.5])
		var hs: float = events.plan["stoppeuse"]
		if hs >= s0 and hs < s1:
			out.append([_road_pos(hs + 1.5, 8.1, 2.6), Color(1.0, 0.95, 0.8), 10.0, 5.0])
	return out


# --- Construction ------------------------------------------------------------

func build_chunk(index: int) -> MeshInstance3D:
	var job := begin_chunk(index)
	while not step_chunk(job):
		pass
	return job["result"]


## Construction en plusieurs étapes, pour l'étaler sur plusieurs images quand
## aucun fil d'exécution n'est disponible (version web) : begin_chunk, puis
## step_chunk jusqu'à ce qu'il renvoie vrai ; le tronçon est dans job.result.
## Un seul tronçon à la fois par constructeur (l'état courant est partagé).
func begin_chunk(index: int) -> Dictionary:
	var s0 := float(index) * CHUNK_LENGTH
	var s1 := s0 + CHUNK_LENGTH
	track.ensure(s1 + LAMP_SPACING)
	_theme = theme_at(s0 + 1.0)
	_lamp_cache = lamps_between(s0 - 3.0 * LAMP_SIGMA - 1.0, s1 + 3.0 * LAMP_SIGMA + 1.0)
	_lamp_cache_from = s0 - 1.0
	_lamp_cache_to = s1 + 1.0
	_halo = _new_tool()
	_ground = _new_tool()
	_cones = _new_tool()
	_memo_height.clear()
	_memo_light.clear()
	return {"index": index, "s0": s0, "s1": s1, "phase": 0, "labels": [],
		"road": _new_tool(), "env": _new_tool(), "glow": _new_tool(), "water": _new_tool()}


func step_chunk(job: Dictionary) -> bool:
	var s0: float = job["s0"]
	var s1: float = job["s1"]
	var slice := CHUNK_LENGTH / GROUND_SLICES
	var env: SurfaceTool = job["env"]
	var glow: SurfaceTool = job["glow"]
	var labels: Array = job["labels"]
	var phase: int = job["phase"]
	if phase == 0:
		_build_road(job["road"], s0, s1)
	elif phase <= GROUND_SLICES:
		# Le terrain, l'étape la plus lourde, en tranches de 12,5 m.
		var a := s0 + (phase - 1) * slice
		_build_shoulders_and_ground(env, job["water"], a, a + slice)
	else:
		match phase - GROUND_SLICES:
			1:
				_build_rails(env, s0, s1)
				_build_delineators(glow, s0, s1)
				_build_neon_edges(glow, s0, s1)
				_build_lamps(env, glow, s0, s1)
			2:
				_build_trees(env, job["index"], s0, s1)
			3:
				_build_landmarks(env, glow, labels, s0, s1)
			4:
				labels.append_array(Scenery.build(self, env, glow, job["index"], s0, s1))
			_:
				job["result"] = _finish_chunk(job)
				return true
	job["phase"] += 1
	return false


## Stations, portiques, panneaux, pylônes, ponts, décors des événements.
func _build_landmarks(env: SurfaceTool, glow: SurfaceTool, labels: Array, s0: float, s1: float) -> void:
	for st in stations:
		if st - STATION_SITE_BACK - STATION_SITE_HALF < s1 and st + 10.0 >= s0:
			_build_station(env, glow, st, s0, s1)
		if st >= s0 and st < s1:
			labels.append(_build_gantry(env, glow, st, Lang.t("STATION %d") % (stations.find(st) + 1)))
		var sign_s := st - 1000.0
		if sign_s >= s0 and sign_s < s1:
			labels.append(_build_sign(env, sign_s, "STATION\n1 km"))
	if arrival_s >= s0 and arrival_s < s1:
		labels.append(_build_gantry(env, glow, arrival_s, "AUBE"))
	if _theme.get("pylons", true):
		_build_pylons(env, s0, s1)
	if events != null:
		for ps in events.panneau_at(s0, s1):
			labels.append(_build_billboard(env, glow, ps, -1))
		var hs: float = events.plan["stoppeuse"]
		if hs >= s0 and hs < s1:
			_build_hitchhiker(env, hs)
	if _theme.get("billboards", true):
		for bs in _every(BILLBOARD_SPACING, 330.0, s0, s1):
			if not _near_checkpoint(bs, 160.0) and not in_tunnel(bs) and not _near_panneau(bs):
				labels.append(_build_billboard(env, glow, bs, int(bs / BILLBOARD_SPACING)))
	if _theme.get("bridges", true):
		for br in _every(BRIDGE_SPACING, 620.0, s0, s1):
			if not _near_checkpoint(br, 200.0) and not in_tunnel(br):
				_build_bridge(env, glow, br)


func _finish_chunk(job: Dictionary) -> MeshInstance3D:
	# Terrain : sommets partagés et normales lissées.
	_ground.index()
	_ground.generate_normals()
	var mats := _materials_for(_theme)
	var mi := MeshInstance3D.new()
	mi.mesh = _assemble([[job["env"], mats[1]], [_ground, mats[2]], [job["glow"], glow_material],
			[_cones, cone_material], [_halo, Halo.material()]])
	mi.name = "Chunk%d" % job["index"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Route et eau à part : la caméra de réflexion ne doit pas les voir.
	var wet := MeshInstance3D.new()
	wet.mesh = _assemble([[job["road"], mats[0]], [job["water"], water_material]])
	wet.layers = 1 << (Reflection.WET_LAYER - 1)
	wet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(wet)
	for l in job["labels"]:
		if l != null:
			mi.add_child(l)
	return mi


func _assemble(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for part in parts:
		var arrays: Array = part[0].commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_VERTEX].is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	return mesh


# --- Décors : pylônes, panneaux, ponts ------------------------------------------

## Positions k·spacing + offset comprises dans [s0, s1).
func _every(spacing: float, offset: float, s0: float, s1: float) -> Array:
	var out := []
	var k := int(ceil((s0 - offset) / spacing))
	while k * spacing + offset < s1:
		out.append(k * spacing + offset)
		k += 1
	return out


func _near_checkpoint(s: float, margin: float) -> bool:
	for st in stations:
		if absf(s - st) < margin + STATION_SITE_HALF:
			return true
	return arrival_s > 0.0 and absf(s - arrival_s) < margin


## Ligne haute tension sur la gauche : pylônes, câbles, feu rouge au sommet.
func _build_pylons(env: SurfaceTool, s0: float, s1: float) -> void:
	var steel := Color(0.16, 0.17, 0.2)
	var k0 := int(ceil(s0 / PYLON_SPACING))
	var k1 := int(floor((s1 - 0.001) / PYLON_SPACING))
	for k in range(k0, k1 + 1):
		var s := k * PYLON_SPACING
		var yaw := track.yaw_at(s)
		var g := ground_height(s, PYLON_X)
		var base := _road_pos(s, PYLON_X, g)
		# Fût en treillis simplifié : 3 tronçons de plus en plus fins.
		var widths := [2.6, 1.6, 0.8]
		for i in 3:
			var h0 := PYLON_HEIGHT * i / 3.0
			_box(env, base + Vector3.UP * h0, yaw, Vector3(widths[i], PYLON_HEIGHT / 3.0, widths[i]), steel, 0.05)
		# Consoles.
		for arm_h in [PYLON_HEIGHT * 0.62, PYLON_HEIGHT * 0.86]:
			_box(env, base + Vector3.UP * arm_h, yaw, Vector3(9.0, 0.35, 0.35), steel, 0.05)
		Halo.add(_halo, base + Vector3.UP * (PYLON_HEIGHT + 0.6), 1.4, Color(1.0, 0.1, 0.05), 0.6)
		# Câbles jusqu'au pylône suivant, avec un peu de flèche.
		var s_next := s + PYLON_SPACING
		track.ensure(s_next + 1.0)
		var next_base := _road_pos(s_next, PYLON_X, ground_height(s_next, PYLON_X))
		for arm_h in [PYLON_HEIGHT * 0.62, PYLON_HEIGHT * 0.86]:
			for off in [-4.2, 4.2]:
				var segs := 6
				for j in segs:
					var ta := float(j) / segs
					var tb := float(j + 1) / segs
					var pa := _cable_point(base, next_base, s, s_next, off, arm_h, ta)
					var pb := _cable_point(base, next_base, s, s_next, off, arm_h, tb)
					_quad(env, [pa, pb, pb + Vector3.UP * 0.07, pa + Vector3.UP * 0.07],
							[steel, steel, steel, steel], [0.0, 0.0, 0.0, 0.0])


func _cable_point(a: Vector3, b: Vector3, sa: float, sb: float, off: float, h: float, t: float) -> Vector3:
	var p := a.lerp(b, t) + track.right_at(lerpf(sa, sb, t)) * off
	p.y += h - sin(t * PI) * 2.5
	return p


func _near_panneau(s: float) -> bool:
	return events != null and s > events.plan["panneau"] - 250.0 \
			and s < events.plan["panneau"] + 2.0 * EventDirector.PANNEAU_SPACING + 250.0


## L'auto-stoppeuse : ciré jaune, pouce levé, sur l'accotement droit, dans la
## lumière d'une lampe de chantier.
func _build_hitchhiker(env: SurfaceTool, s: float) -> void:
	var yaw := track.yaw_at(s)
	var coat := Color(0.85, 0.68, 0.12)
	var dark := Color(0.08, 0.08, 0.1)
	var x := 7.3
	_box(env, _road_pos(s, x - 0.12, 0.0), yaw, Vector3(0.16, 0.85, 0.2), dark, 0.9)
	_box(env, _road_pos(s, x + 0.12, 0.0), yaw, Vector3(0.16, 0.85, 0.2), dark, 0.9)
	_box(env, _road_pos(s, x, 0.85), yaw, Vector3(0.55, 0.75, 0.32), coat, 1.0)
	_box(env, _road_pos(s, x, 1.62), yaw, Vector3(0.24, 0.26, 0.24), Color(0.75, 0.6, 0.5), 1.0)
	_box(env, _road_pos(s, x, 1.84), yaw, Vector3(0.3, 0.12, 0.3), coat, 1.0)
	# Bras tendu vers la route, pouce levé.
	_box(env, _road_pos(s, x - 0.5, 1.35), yaw, Vector3(0.55, 0.12, 0.12), coat, 1.0)
	_box(env, _road_pos(s, x - 0.75, 1.4), yaw, Vector3(0.07, 0.16, 0.07), Color(0.75, 0.6, 0.5), 1.0)
	Halo.add(_halo, _road_pos(s + 1.5, x + 0.8, 2.6), 2.2, Color(1.0, 0.95, 0.8), 0.35)


## Panneau publicitaire éclairé sur la droite (k = -1 : « VOUS ÊTES ICI »).
func _build_billboard(env: SurfaceTool, glow: SurfaceTool, s: float, k: int) -> Label3D:
	var entry: Array = ["VOUS ÊTES\nICI", Color(0.95, 0.25, 0.5)] if k < 0 \
			else BILLBOARDS[posmod(k, BILLBOARDS.size())]
	var color: Color = entry[1]
	var yaw := track.yaw_at(s)
	var x := 15.0
	var g := ground_height(s, x)
	for px in [x - 2.5, x + 2.5]:
		_box(env, _road_pos(s, px, g), yaw, Vector3(0.3, 6.0 - g, 0.3), Color(0.2, 0.2, 0.22), 0.2)
	# Panneau : fond coloré lumineux, cadre sombre.
	_box(env, _road_pos(s, x, 5.6), yaw, Vector3(8.4, 4.4, 0.25), Color(0.05, 0.05, 0.06), 0.1)
	_glow_box(glow, _road_pos(s, x, 5.8) + track.forward_at(s) * -0.14, yaw, Vector3(7.8, 3.8, 0.02), color, 0.55)
	Halo.add(_halo, _road_pos(s, x, 8.0) + track.forward_at(s) * -0.8, 5.5, color, 0.22)
	var label := Label3D.new()
	label.text = Lang.t(entry[0])
	label.font = Hud.text_font(true)
	label.font_size = 96
	label.pixel_size = 0.016
	label.modulate = Color(1.0, 1.0, 0.95)
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.6)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.transform = track.transform_at(s, x, 7.7)
	label.position += track.forward_at(s) * -0.3
	return label


## Pont qui enjambe l'autoroute, avec ses lampadaires.
func _build_bridge(env: SurfaceTool, glow: SurfaceTool, s: float) -> void:
	var yaw := track.yaw_at(s)
	var concrete := Color(0.24, 0.235, 0.23)
	for side in [-1.0, 1.0]:
		_box(env, _road_pos(s, 10.5 * side, -1.0), yaw, Vector3(1.6, 8.0, 3.0), concrete, 0.25)
	# Tablier : très large pour enjamber aussi les bas-côtés.
	_box(env, _road_pos(s, 0.0, 7.0), yaw, Vector3(60.0, 1.4, 9.0), concrete, 0.2)
	_box(env, _road_pos(s, 0.0, 8.4), yaw, Vector3(60.0, 0.9, 0.3), concrete * 0.8, 0.2)
	# Lampes sous le tablier : on passe dans une bulle de lumière.
	for x in [-4.0, 0.0, 4.0]:
		_glow_box(glow, _road_pos(s, x, 6.9), yaw, Vector3(1.2, 0.05, 0.4), Color(0.85, 0.95, 1.0), 0.9)
		Halo.add(_halo, _road_pos(s, x, 6.7) + track.forward_at(s) * 4.6, 1.6, Color(0.85, 0.95, 1.0), 0.4)


# --- Stations et portiques ---------------------------------------------------

## Station-service à droite, juste avant le portique : auvent lumineux, pompes,
## boutique, totem. Seules les pièces dont le pied tombe dans [s0, s1) sont
## construites, pour ne rien dessiner deux fois d'un tronçon à l'autre.
func _build_station(env: SurfaceTool, glow: SurfaceTool, st: float, s0: float, s1: float) -> void:
	var c := st - STATION_SITE_BACK
	var pieces := []
	# La station vide : tout baigne dans une lumière bleue, froide.
	var empty := events != null and is_equal_approx(st, events.plan["station_vide"])
	var station_light := Color(0.35, 0.55, 1.0) if empty else STATION_LIGHT
	var sign_color := Color(0.3, 0.5, 1.0) if empty else SIGN_COLOR
	# Auvent : piliers, toit, sous-face lumineuse.
	for ps in [c - 10.0, c + 10.0]:
		for px in [15.0, 29.0]:
			pieces.append(["box", ps, px, 0.0, Vector3(0.5, 5.6, 0.5), Color(0.75, 0.75, 0.78), 0.9])
	pieces.append(["roof", c, 22.0])
	# Pompes.
	for ps in [c - 6.0, c, c + 6.0]:
		pieces.append(["box", ps, 22.0, 0.0, Vector3(0.8, 1.6, 1.2), Color(0.8, 0.18, 0.12), 0.9])
		pieces.append(["glow", ps, 21.55, 1.0, Vector3(0.05, 0.35, 0.6), station_light, 0.8])
	# Boutique et sa vitrine.
	pieces.append(["box", c + 4.0, 41.0, 0.0, Vector3(9.0, 4.0, 22.0), Color(0.55, 0.53, 0.5), 0.5])
	pieces.append(["glow", c + 4.0, 36.45, 0.6, Vector3(0.05, 2.0, 16.0), Color(1.0, 0.85, 0.55), 0.9])
	# Totem lumineux au bord de la route.
	pieces.append(["box", c - 30.0, 11.5, 0.0, Vector3(0.4, 11.0, 0.4), Color(0.3, 0.3, 0.32), 0.4])
	pieces.append(["glow", c - 30.0, 11.5, 11.0, Vector3(0.3, 2.6, 3.4), sign_color, 1.0])
	pieces.append(["halo", c - 30.0, 11.5, 12.3, 5.0, sign_color, 0.45])
	for ps in [c - 9.0, c, c + 9.0]:
		pieces.append(["halo", ps, 22.0, 5.2, 4.0, station_light, 0.3])
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
			"halo":
				Halo.add(_halo, _road_pos(ps, p[2], p[3]), p[4], p[5], p[6])
			"roof":
				_box(env, _road_pos(ps, p[2], 5.6), yaw, Vector3(18.0, 0.8, 28.0), Color(0.9, 0.9, 0.92), 0.7)
				# Bandeau orange sur la tranche de l'auvent, côté route.
				_glow_box(glow, _road_pos(ps, 12.95, 5.65), yaw, Vector3(0.1, 0.7, 28.0), sign_color, 0.9)
				# Sous-face : un grand aplat lumineux tourné vers le bas.
				_glow_box(glow, _road_pos(ps, 22.0, 5.55), yaw, Vector3(17.0, 0.02, 27.0), station_light, 0.55)


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
		Halo.add(_halo, _road_pos(s, x, 6.2) + track.forward_at(s) * -0.6, 1.1, col, 0.45)
	var label := Label3D.new()
	label.text = Lang.t(text)
	label.font = Hud.arcade_font()
	label.font_size = 64
	label.pixel_size = 0.016
	label.outline_size = 0
	label.modulate = Color(1.0, 0.86, 0.55)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.transform = track.transform_at(s, 0.0, 7.2)
	label.position += track.forward_at(s) * -0.45
	return label


## Panneau d'annonce sur le bas-côté droit.
func _build_sign(env: SurfaceTool, s: float, text: String) -> Label3D:
	var yaw := track.yaw_at(s)
	_box(env, _road_pos(s, 10.0, 0.0), yaw, Vector3(0.2, 3.0, 0.2), Color(0.3, 0.3, 0.32), 0.3)
	_box(env, _road_pos(s, 10.0, 3.0), yaw, Vector3(3.6, 2.0, 0.15), Color(0.1, 0.25, 0.55), 0.6)
	var label := Label3D.new()
	label.text = Lang.t(text)
	label.font = Hud.text_font(true)
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 0
	label.modulate = Color(0.95, 0.95, 1.0)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
func _quad(st: SurfaceTool, p: Array, colors: Array, lights: Array, uvs: Array = [], flat := true) -> void:
	var n: Vector3 = (p[3] - p[0]).cross(p[1] - p[0]).normalized()
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(colors[i].r, colors[i].g, colors[i].b, lights[i]))
		st.set_uv(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
		if flat:
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
			var lights := [_light_memo(sa, xa), _light_memo(sb, xa), _light_memo(sb, xb), _light_memo(sa, xb)]
			var uvs := [
				Vector2((xa + 6.0) / 12.0, sa / 12.0), Vector2((xa + 6.0) / 12.0, sb / 12.0),
				Vector2((xb + 6.0) / 12.0, sb / 12.0), Vector2((xb + 6.0) / 12.0, sa / 12.0)]
			_quad(st, pts, [tint, tint, tint, tint], lights, uvs)


func _build_shoulders_and_ground(st: SurfaceTool, water: SurfaceTool, s0: float, s1: float) -> void:
	var gravel := Color(0.22, 0.21, 0.2)
	var grass_near: Color = _theme.get("ground", Color(0.07, 0.11, 0.08))
	var grass_far := grass_near * 0.6 + Color(0.0, 0.0, 0.02)
	var wside := water_side(s0 + 1.0)
	var tunnel_chunk := in_tunnel(s0) and in_tunnel(s1 - 1.0)
	for i in _steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		for side in [-1.0, 1.0]:
			# Accotement de 6 à 8 m.
			var xs := [6.0 * side, 8.0 * side]
			_strip(st, sa, sb, xs[0], xs[1], 0.0, 0.0, gravel, gravel, side)
			if tunnel_chunk:
				continue
			# Eau (lac, mer, port) : talus jusqu'à 11 m, puis une nappe sombre.
			if side == wside and _station_flat(sa, 30.0 * side) <= 0.0:
				_strip(st, sa, sb, 8.0 * side, 11.0 * side, 0.0, 0.0, grass_near, gravel * 0.6, side, true)
				_strip(water, sa, sb, 11.0 * side, 90.0 * side, -1.6, -1.6, Color(0.015, 0.025, 0.045),
						Color(0.01, 0.015, 0.03), side)
				continue
			# Terrain.
			for c in GROUND_COLUMNS.size() - 1:
				var xa: float = GROUND_COLUMNS[c] * side
				var xb: float = GROUND_COLUMNS[c + 1] * side
				var ca := grass_near.lerp(grass_far, float(c) / (GROUND_COLUMNS.size() - 1))
				var cb := grass_near.lerp(grass_far, float(c + 1) / (GROUND_COLUMNS.size() - 1))
				_strip(st, sa, sb, xa, xb, 0.0, 0.0, ca, cb, side, true)


## Hauteur et lumière d'un point de la grille, calculées une seule fois par
## tronçon (chaque point est partagé par quatre carreaux).
func _height_memo(s: float, x: float) -> float:
	var key := Vector2(s, x)
	if not _memo_height.has(key):
		_memo_height[key] = ground_height(s, x)
	return _memo_height[key]


func _light_memo(s: float, x: float) -> float:
	var key := Vector2(s, x)
	if not _memo_light.has(key):
		_memo_light[key] = lamp_light(s, x)
	return _memo_light[key]


## Bande de terrain entre xa et xb (xa plus près de la route), sens selon le côté.
func _strip(st: SurfaceTool, sa: float, sb: float, xa: float, xb: float, ha: float, hb: float,
		ca: Color, cb: Color, side: float, use_ground := false) -> void:
	var haa := _height_memo(sa, xa) if use_ground else ha
	var hab := _height_memo(sb, xa) if use_ground else ha
	var hba := _height_memo(sa, xb) if use_ground else hb
	var hbb := _height_memo(sb, xb) if use_ground else hb
	var p := [_road_pos(sa, xa, haa), _road_pos(sb, xa, hab), _road_pos(sb, xb, hbb), _road_pos(sa, xb, hba)]
	var l := [_light_memo(sa, xa), _light_memo(sb, xa), _light_memo(sb, xb), _light_memo(sa, xb)]
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
	# Terrain : normales lissées après coup (voir build_chunk).
	if use_ground:
		_quad(_ground, p, c, l, [], false)
	else:
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


## Synthwave : un tube néon le long de chaque bord de la chaussée, magenta à
## gauche, cyan à droite.
const NEON_LEFT := Color(1.0, 0.25, 0.72)
const NEON_RIGHT := Color(0.25, 0.85, 1.0)


func _build_neon_edges(glow: SurfaceTool, s0: float, s1: float) -> void:
	var uvs := [Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)]
	for i in _steps(s0, s1):
		var sa := s0 + i * Track.STEP
		var sb := sa + Track.STEP
		for side in [-1.0, 1.0]:
			var c := NEON_RIGHT if side > 0.0 else NEON_LEFT
			var x0: float = side * 6.02
			var x1: float = side * 6.18
			var p := [_road_pos(sa, x0, 0.02), _road_pos(sb, x0, 0.02), _road_pos(sb, x1, 0.02), _road_pos(sa, x1, 0.02)]
			_quad(glow, p if side > 0.0 else [p[0], p[3], p[2], p[1]], [c, c, c, c], [1.6, 1.6, 1.6, 1.6], uvs)


## Balises réfléchissantes sur les glissières, tous les 25 m : blanches à
## droite, orange à gauche, comme sur l'autoroute. De loin, elles dessinent le
## virage qui arrive (lisibilité de nuit, sous la pluie).
const DELINEATOR_SPACING := 25.0


func _build_delineators(glow: SurfaceTool, s0: float, s1: float) -> void:
	for s in _every(DELINEATOR_SPACING, 0.0, s0, s1):
		if in_tunnel(s) or _near_checkpoint(s, 30.0):
			continue
		var yaw := track.yaw_at(s)
		for side in [-1.0, 1.0]:
			var c := Color(1.0, 0.95, 0.85) if side > 0.0 else Color(1.0, 0.55, 0.15)
			_glow_box(glow, _road_pos(s, 7.9 * side, 0.58), yaw, Vector3(0.07, 0.24, 0.12), c, 2.2)


func _build_lamps(env: SurfaceTool, glow: SurfaceTool, s0: float, s1: float) -> void:
	var pole := Color(0.2, 0.21, 0.23)
	var lamp_color: Color = _theme.get("lamp_color", LAMP_COLOR)
	for lamp in lamps_between(s0, s1):
		var s: float = lamp[0]
		var side: int = lamp[1]
		var yaw := track.yaw_at(s)
		var light_side := side if side != 0 else (1 if posmod(int(s), 2) == 0 else -1)
		var px := LAMP_POLE_X * light_side
		var on := 0.6 if side != 0 else 0.08
		# Mât et bras.
		_box(env, _road_pos(s, px, 0.0), yaw, Vector3(0.22, LAMP_HEIGHT, 0.22), pole, on)
		var arm_x := (LAMP_POLE_X + 6.5) * 0.5 * light_side
		_box(env, _road_pos(s, arm_x, LAMP_HEIGHT - 0.2), yaw, Vector3(LAMP_POLE_X - 6.5, 0.15, 0.15), pole, on)
		if side == 0:
			continue
		# Ampoule.
		_glow_box(glow, _road_pos(s, 6.5 * side, LAMP_HEIGHT - 0.45), yaw, Vector3(0.9, 0.25, 0.5), lamp_color, 1.0)
		Halo.add(_halo, _road_pos(s, 6.5 * side, LAMP_HEIGHT - 0.4), 2.6, lamp_color, 0.5)
		# Cône de lumière dans la pluie.
		_cone(_cones, _road_pos(s, 6.5 * side, LAMP_HEIGHT - 0.6), _road_pos(s, 5.6 * side, 0.0), 0.35, 4.2,
				lamp_color, 0.32 * absf(_theme.get("rain", 1.0)) + 0.08)


## Cône de lumière de `top` (rayon r0) à `bottom` (rayon r1) ; UV.y va de 0
## (en haut) à 1 (au sol), les normales pointent vers l'extérieur.
func _cone(st: SurfaceTool, top: Vector3, bottom: Vector3, r0: float, r1: float, color: Color, strength: float) -> void:
	var sides := 12
	var axis := (bottom - top).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var quad := [[top + d0 * r0, d0, Vector2(float(i) / sides, 0.0)], [bottom + d0 * r1, d0, Vector2(float(i) / sides, 1.0)],
				[bottom + d1 * r1, d1, Vector2(float(i + 1) / sides, 1.0)], [top + d1 * r0, d1, Vector2(float(i + 1) / sides, 0.0)]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(color.r, color.g, color.b, strength))
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


func _build_trees(st: SurfaceTool, index: int, s0: float, s1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(index, _seed))
	var density: float = _theme.get("trees", 0.55)
	var foliage := Color(0.5, 0.55, 0.6) if _theme.get("snow", false) else Color(0.035, 0.07, 0.06)
	# Forêt : trois arbres par pas, jusqu'au bord de la route.
	var near_x := 10.0 if density >= 0.9 else 12.0
	var per_step := 3 if density >= 0.9 else 1
	var wside := water_side(s0 + 1.0)
	var s := s0
	while s < s1:
		for side in [-1.0, 1.0]:
			for n in per_step:
				if rng.randf() >= density:
					continue
				var far := 62.0 if n == 0 else 30.0
				var x: float = side * rng.randf_range(near_x, far)
				var ts := s + rng.randf_range(0.0, 6.0)
				if _station_flat(ts, x) > 0.0 or _station_flat(ts, x + 8.0) > 0.0 \
						or side == wside or in_tunnel(ts):
					continue
				var h := rng.randf_range(6.0, 13.0)
				var base := _road_pos(ts, x, ground_height(ts, x) - 0.5)
				var shade := rng.randf_range(0.7, 1.2)
				_tree(st, base, h, foliage * shade, lamp_light(ts, x) * 0.7)
		s += 6.0


func _tree(st: SurfaceTool, base: Vector3, height: float, color: Color, light: float) -> void:
	# Sapin en trois étages de branches (8 pans), plus sombre vers le bas.
	var sides := 8
	var tiers := [[0.15, 0.62, height * 0.34], [0.38, 0.84, height * 0.26], [0.6, 1.0, height * 0.17]]
	var trunk := Color(0.09, 0.06, 0.04)
	_box(st, base, 0.0, Vector3(0.35, height * 0.2, 0.35), trunk, light * 0.5)
	for t in tiers:
		var y0: float = height * t[0]
		var y1: float = height * t[1]
		var r: float = t[2]
		var apex := base + Vector3.UP * y1
		var low := color * 0.7
		for i in sides:
			var a0: float = TAU * (i + t[0]) / sides
			var a1: float = TAU * (i + 1 + t[0]) / sides
			var p0 := base + Vector3(cos(a0) * r, y0, sin(a0) * r)
			var p1 := base + Vector3(cos(a1) * r, y0, sin(a1) * r)
			# Normales penchées vers l'extérieur : ombrage doux d'un cône.
			var n0 := Vector3(cos(a0), 0.55, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.55, sin(a1)).normalized()
			var na := (n0 + n1).normalized()
			for v in [[p0, n0, low], [apex, na, color], [p1, n1, low]]:
				st.set_color(Color(v[2].r, v[2].g, v[2].b, light))
				st.set_uv(Vector2.ZERO)
				st.set_normal(v[1])
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


func _hash(k: int) -> float:
	return float(hash(Vector2i(k, _seed * 31 + 5)) % 10000) / 10000.0

class_name VehicleMesh
extends RefCounted
## Géométrie low-poly des véhicules (voiture du joueur et trafic).
## Repère local : -Z vers l'avant, +X à droite, origine au sol au centre.
## Chaque véhicule a trois surfaces : la carrosserie (night_car : l'alpha des
## couleurs dit « laqué » (1) ou mat (0)), les lumières (night_glow, additives)
## et leurs halos.

enum Kind { SPORT, SEDAN, TRUCK }

const GLASS_COLOR := Color(0.03, 0.035, 0.05, 1.0)
const TYRE_COLOR := Color(0.035, 0.035, 0.035, 0.0)
const TAIL_COLOR := Color(1.0, 0.08, 0.05)
const HEAD_COLOR := Color(1.0, 0.92, 0.7)

## Demi-longueur et demi-largeur de chaque gabarit (collisions).
const HALF_LENGTH := {Kind.SPORT: 2.2, Kind.SEDAN: 2.3, Kind.TRUCK: 6.2}
const HALF_WIDTH := {Kind.SPORT: 0.95, Kind.SEDAN: 0.95, Kind.TRUCK: 1.25}

## Halos du véhicule en cours de construction.
static var _halo: SurfaceTool
static var _options := {}


## Construit le maillage d'un véhicule. `beam` : faisceau des phares au sol.
## options (sportive du joueur) : "aileron" (bool), "jantes" (bool, chromées),
## "neon" (Color, néon sous caisse).
static func build(kind: Kind, color: Color, body_material: Material, glow_material: Material,
		beam := false, lights := true, options := {}) -> ArrayMesh:
	_options = options
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	_halo = SurfaceTool.new()
	_halo.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Kind.SPORT:
			_sport(body, glow, color)
		Kind.SEDAN:
			_sedan(body, glow, color)
		Kind.TRUCK:
			_truck(body, glow, color)
	if beam:
		_headlight_beam(glow)
	var mesh := ArrayMesh.new()
	body.commit(mesh)
	mesh.surface_set_material(0, body_material)
	# Feux éteints (la voiture fantôme) : ni lumières ni halos.
	if lights:
		glow.commit(mesh)
		mesh.surface_set_material(1, glow_material)
		_halo.commit(mesh)
		mesh.surface_set_material(2, Halo.material())
	return mesh


## Sections de la coque de la sportive, d'avant en arrière :
## [z, demi-largeur, bas de caisse, ligne de ceinture, dessus au centre].
const SPORT_BODY := [
	[-2.32, 0.74, 0.34, 0.50, 0.53], [-2.18, 0.86, 0.29, 0.58, 0.61], [-1.6, 0.94, 0.27, 0.64, 0.69],
	[-0.6, 0.97, 0.26, 0.71, 0.76], [0.6, 0.99, 0.26, 0.79, 0.83], [1.6, 1.0, 0.27, 0.86, 0.9],
	[2.2, 0.98, 0.3, 0.86, 0.9], [2.33, 0.93, 0.37, 0.8, 0.84]]
## Habitacle vitré : [z, demi-largeur à la base, base, demi-largeur en haut, toit].
const SPORT_CABIN := [
	[-0.62, 0.86, 0.75, 0.86, 0.77], [-0.05, 0.86, 0.79, 0.66, 1.16], [0.95, 0.88, 0.83, 0.68, 1.14],
	[1.4, 0.9, 0.87, 0.9, 0.89]]


static func _sport(body: SurfaceTool, glow: SurfaceTool, color: Color) -> void:
	# Coin de fromage années 80, en surfaces lissées : nez bas et effilé,
	# flancs galbés, arrière large et haut, habitacle bombé.
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for sec in SPORT_BODY:
		rings.append(_body_ring(sec[0], sec[1], sec[2], sec[3], sec[4]))
	_loft(shell, rings, color, true, true)
	var cabin := []
	for sec in SPORT_CABIN:
		cabin.append(_cabin_ring(sec[0], sec[1], sec[2], sec[3], sec[4]))
	_loft(shell, cabin, GLASS_COLOR, false)
	shell.index()
	shell.generate_normals()
	# Désindexer : la carrosserie reçoit ensuite des sommets sans index.
	shell.deindex()
	body.append_from(shell.commit(), 0, Transform3D.IDENTITY)
	# Ouïes latérales (les « râpes à fromage »).
	for side in [-1.0, 1.0]:
		for k in 4:
			_box(body, Vector3(side * 0.985, 0.5 + k * 0.075, 1.05), Vector3(0.03, 0.03, 1.4), Color(0.02, 0.02, 0.02, 0.3))
		# Rétroviseur.
		_box(body, Vector3(side * 0.97, 0.93, -0.45), Vector3(0.14, 0.09, 0.2), color)
	# Phares escamotables, levés la nuit.
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * 0.52, 0.62, -1.85), Vector3(0.46, 0.13, 0.3), color)
		_glow_quad(glow, Vector3(side * 0.52, 0.62, -2.01), Vector2(0.4, 0.09), HEAD_COLOR, 1.0)
	# Arrière : grille noire et bandeau de feux sur toute la largeur.
	_box(body, Vector3(0.0, 0.62, 2.335), Vector3(1.8, 0.36, 0.02), Color(0.03, 0.03, 0.035, 0.5))
	_glow_quad(glow, Vector3(0.0, 0.71, 2.36), Vector2(1.66, 0.09), TAIL_COLOR, 1.0)
	for side in [-1.0, 1.0]:
		Halo.add(_halo, Vector3(side * 0.7, 0.71, 2.42), 0.7, TAIL_COLOR, 0.5)
	_round_wheels(body, 0.92, [-1.45, 1.5])
	# Lame avant et diffuseur arrière à ailettes, noirs.
	var trim := Color(0.03, 0.03, 0.035, 0.4)
	_box(body, Vector3(0.0, 0.31, -2.2), Vector3(1.6, 0.05, 0.25), trim)
	_box(body, Vector3(0.0, 0.33, 2.2), Vector3(1.7, 0.12, 0.3), trim)
	for k in 5:
		_box(body, Vector3(-0.6 + k * 0.3, 0.38, 2.24), Vector3(0.03, 0.12, 0.28), trim)
	if _options.get("aileron", false):
		# Aileron : deux montants et un plan profilé au-dessus du capot arrière.
		for side in [-1.0, 1.0]:
			_box(body, Vector3(side * 0.62, 1.0, 2.02), Vector3(0.06, 0.2, 0.16), trim)
		_prism(body, [
			Vector3(-0.95, 1.08, 1.86), Vector3(0.95, 1.08, 1.86), Vector3(0.95, 1.11, 2.2), Vector3(-0.95, 1.11, 2.2),
			Vector3(-0.95, 1.13, 1.9), Vector3(0.95, 1.13, 1.9), Vector3(0.95, 1.2, 2.22), Vector3(-0.95, 1.2, 2.22)],
			color)
		for side in [-1.0, 1.0]:
			_box(body, Vector3(side * 0.96, 1.12, 2.05), Vector3(0.02, 0.18, 0.42), trim)
	if _options.has("neon"):
		# Néon sous caisse : une nappe lumineuse au sol, qui s'éteint vers les bords.
		var neon: Color = _options["neon"]
		for half in [[-1.25, 0.0], [0.0, 1.25]]:
			for zr in [[-2.6, 0.0], [0.0, 2.6]]:
				var x0: float = half[0]
				var x1: float = half[1]
				var z0: float = zr[0]
				var z1: float = zr[1]
				var p := [Vector3(x0, 0.04, z0), Vector3(x0, 0.04, z1), Vector3(x1, 0.04, z1), Vector3(x1, 0.04, z0)]
				for i in [0, 1, 2, 0, 2, 3]:
					var edge := absf(p[i].x) > 1.0 or absf(p[i].z) > 2.0
					glow.set_color(Color(neon.r, neon.g, neon.b, 0.9))
					glow.set_uv(Vector2(0, 0.0 if edge else 1.0))
					glow.add_vertex(p[i])


## Section de coque : bas de caisse, flanc, épaulement arrondi, dessus bombé.
static func _body_ring(z: float, hw: float, bottom: float, belt: float, top: float) -> Array:
	var half := [Vector2(hw * 0.93, bottom), Vector2(hw, bottom + 0.1), Vector2(hw, belt - 0.07),
			Vector2(hw - 0.05, belt - 0.01), Vector2(hw - 0.14, belt + (top - belt) * 0.45),
			Vector2(hw * 0.5, top - 0.005), Vector2(0.0, top)]
	return _mirror_ring(half, z)


static func _cabin_ring(z: float, base_hw: float, base: float, top_hw: float, roof: float) -> Array:
	var half := [Vector2(base_hw, base), Vector2(lerpf(base_hw, top_hw, 0.75), lerpf(base, roof, 0.85)),
			Vector2(top_hw * 0.6, roof - 0.01), Vector2(0.0, roof)]
	return _mirror_ring(half, z)


## Demi-profil (de droite en bas jusqu'au centre en haut) -> anneau complet.
static func _mirror_ring(half: Array, z: float) -> Array:
	var ring := []
	for p in half:
		ring.append(Vector3(p.x, p.y, z))
	for i in range(half.size() - 2, -1, -1):
		ring.append(Vector3(-half[i].x, half[i].y, z))
	return ring


## Surface passant par les anneaux successifs ; `caps` ferme l'avant et
## l'arrière ; `dark_sills` assombrit le bas de caisse (premier et dernier
## points de chaque anneau).
static func _loft(st: SurfaceTool, rings: Array, color: Color, caps: bool, dark_sills := false) -> void:
	var sill := Color(0.04, 0.04, 0.045, 0.4)
	for r in rings.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		for i in a.size() - 1:
			for k in [[a, i], [b, i], [b, i + 1], [a, i], [b, i + 1], [a, i + 1]]:
				var idx: int = k[1]
				var dark := dark_sills and (idx == 0 or idx == a.size() - 1)
				st.set_color(sill if dark else color)
				st.add_vertex(k[0][idx])
	if caps:
		for ring in [rings[0], rings[-1]]:
			var c := Vector3.ZERO
			for v in ring:
				c += v
			c /= ring.size()
			for i in ring.size() - 1:
				for v in [c, ring[i], ring[i + 1]]:
					st.set_color(sill if dark_sills else color)
					st.add_vertex(v)


## Roues rondes (octogones) avec jante claire.
static func _round_wheels(body: SurfaceTool, x: float, zs: Array) -> void:
	for wx in [-x, x]:
		for wz in zs:
			var c := Vector3(wx, 0.33, wz)
			for i in 10:
				var a0 := TAU * i / 10.0
				var a1 := TAU * (i + 1) / 10.0
				var p0 := Vector3(0, sin(a0) * 0.33, cos(a0) * 0.33)
				var p1 := Vector3(0, sin(a1) * 0.33, cos(a1) * 0.33)
				for side in [-0.15, 0.15]:
					var o := Vector3(side, 0, 0)
					for v in [c + o, c + o + p0, c + o + p1]:
						body.set_color(TYRE_COLOR)
						body.set_normal(Vector3(signf(side), 0, 0))
						body.add_vertex(v)
					# Jante : un disque plus petit, gris métal (ou chromé), côté extérieur.
					if side * wx > 0.0:
						var r := Vector3(signf(side) * 0.01, 0, 0)
						var rim := Color(0.7, 0.72, 0.78, 1.0) if _options.get("jantes", false) else Color(0.2, 0.2, 0.22, 0.8)
						for v in [c + o + r, c + o + r + p0 * 0.62, c + o + r + p1 * 0.62]:
							body.set_color(rim)
							body.set_normal(Vector3(signf(side), 0, 0))
							body.add_vertex(v)
				var n := (p0 + p1).normalized()
				for v in [c + p0 + Vector3(-0.15, 0, 0), c + p0 + Vector3(0.15, 0, 0), c + p1 + Vector3(0.15, 0, 0),
						c + p0 + Vector3(-0.15, 0, 0), c + p1 + Vector3(0.15, 0, 0), c + p1 + Vector3(-0.15, 0, 0)]:
					body.set_color(TYRE_COLOR)
					body.set_normal(n)
					body.add_vertex(v)


## Berline (trafic) : coque à trois volumes, en surfaces lissées.
const SEDAN_BODY := [
	[-2.32, 0.82, 0.32, 0.66, 0.7], [-2.2, 0.9, 0.28, 0.76, 0.8], [-1.2, 0.93, 0.27, 0.86, 0.9],
	[1.3, 0.93, 0.27, 0.88, 0.92], [2.2, 0.91, 0.29, 0.88, 0.92], [2.32, 0.86, 0.34, 0.82, 0.86]]
const SEDAN_CABIN := [
	[-1.15, 0.86, 0.88, 0.86, 0.9], [-0.55, 0.86, 0.9, 0.72, 1.42], [0.85, 0.86, 0.91, 0.72, 1.42],
	[1.35, 0.86, 0.91, 0.86, 0.93]]


static func _sedan(body: SurfaceTool, glow: SurfaceTool, color: Color) -> void:
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for sec in SEDAN_BODY:
		rings.append(_body_ring(sec[0], sec[1], sec[2], sec[3], sec[4]))
	_loft(shell, rings, Color(color.r, color.g, color.b, 0.7), true, true)
	var cabin := []
	for sec in SEDAN_CABIN:
		cabin.append(_cabin_ring(sec[0], sec[1], sec[2], sec[3], sec[4]))
	_loft(shell, cabin, GLASS_COLOR, false)
	shell.index()
	shell.generate_normals()
	shell.deindex()
	body.append_from(shell.commit(), 0, Transform3D.IDENTITY)
	_round_wheels(body, 0.86, [-1.5, 1.5])
	_lights(glow, 0.65, 0.72, 2.34, 0.55, 0.6, -2.34)


static func _truck(body: SurfaceTool, glow: SurfaceTool, color: Color) -> void:
	# Remorque.
	_box(body, Vector3(0, 2.25, 1.6), Vector3(2.5, 3.1, 9.2), color)
	# Cabine.
	_box(body, Vector3(0, 1.7, -4.4), Vector3(2.4, 2.6, 2.4), color * 0.7)
	_box(body, Vector3(0, 2.4, -5.62), Vector3(2.2, 0.9, 0.05), GLASS_COLOR)
	_box(body, Vector3(0, 0.55, 0), Vector3(2.3, 0.4, 12.0), TYRE_COLOR)
	_wheels(body, 1.1, [-4.4, 3.2, 4.6])
	_lights(glow, 1.05, 0.9, 6.21, 0.3, 0.8, -5.66)
	# Feux de gabarit orange en haut de la remorque.
	for side in [-1.0, 1.0]:
		_glow_quad(glow, Vector3(side * 1.15, 3.7, 6.21), Vector2(0.15, 0.1), Color(1.0, 0.55, 0.1), 1.0)


static func _wheels(body: SurfaceTool, x: float, zs: Array) -> void:
	for wx in [-x, x]:
		for wz in zs:
			_box(body, Vector3(wx, 0.33, wz), Vector3(0.32, 0.66, 0.68), TYRE_COLOR)
			# Jante claire côté extérieur.
			_box(body, Vector3(wx + signf(wx) * 0.165, 0.33, wz), Vector3(0.02, 0.3, 0.3), Color(0.3, 0.3, 0.32, 0.6))


## Feux arrière (x, hauteur, z) + phares avant, et reflet des feux sur la route.
static func _lights(glow: SurfaceTool, tail_x: float, tail_y: float, tail_z: float,
		head_x: float, head_y: float, head_z: float) -> void:
	for side in [-1.0, 1.0]:
		_glow_quad(glow, Vector3(side * tail_x, tail_y, tail_z), Vector2(0.5, 0.14), TAIL_COLOR, 1.0)
		Halo.add(_halo, Vector3(side * tail_x, tail_y, tail_z + 0.08), 0.75, TAIL_COLOR, 0.5)
		_glow_quad(glow, Vector3(side * head_x, head_y, head_z), Vector2(0.4, 0.1), HEAD_COLOR, 1.0)


static func _prism(st: SurfaceTool, c: Array, color: Color) -> void:
	var center := Vector3.ZERO
	for p in c:
		center += p
	center /= c.size()
	for f in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		var p := [c[f[0]], c[f[1]], c[f[2]], c[f[3]]]
		var n: Vector3 = (p[3] - p[0]).cross(p[1] - p[0]).normalized()
		var face_center: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
		if n.dot(face_center - center) < 0.0:
			n = -n
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(color.r, color.g, color.b, color.a))
			st.set_normal(n)
			st.add_vertex(p[i])


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c := []
	for y in [-h.y, h.y]:
		for corner in [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]:
			c.append(center + Vector3(corner.x, y, corner.y))
	_prism(st, c, color)


## Rectangle lumineux vertical, face vers l'arrière ou l'avant.
static func _glow_quad(st: SurfaceTool, center: Vector3, size: Vector2, color: Color, strength: float) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var p := [center + Vector3(-hx, -hy, 0), center + Vector3(-hx, hy, 0),
			center + Vector3(hx, hy, 0), center + Vector3(hx, -hy, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(color.r, color.g, color.b, strength))
		st.set_uv(Vector2(0, 1))
		st.add_vertex(p[i])


## Faisceau des phares couché sur la route : un trapèze additif qui s'élargit
## et s'éteint vers l'avant (pas de vraie lumière : moins cher sur iPhone).
static func _headlight_beam(st: SurfaceTool) -> void:
	var rows := [[-2.3, 1.0, 0.0], [-7.0, 2.2, 0.5], [-16.0, 3.8, 0.35], [-28.0, 5.2, 0.15], [-42.0, 6.5, 0.0]]
	var color := HEAD_COLOR
	for r in rows.size() - 1:
		var a: Array = rows[r]
		var b: Array = rows[r + 1]
		var p := [Vector3(-a[1], 0.04, a[0]), Vector3(-b[1], 0.04, b[0]), Vector3(b[1], 0.04, b[0]), Vector3(a[1], 0.04, a[0])]
		var g := [a[2], b[2], b[2], a[2]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(color.r, color.g, color.b, 0.13))
			st.set_uv(Vector2(0, g[i]))
			st.add_vertex(p[i])

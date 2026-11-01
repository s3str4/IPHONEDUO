class_name VehicleMesh
extends RefCounted
## Géométrie low-poly des véhicules (voiture du joueur et trafic).
## Repère local : -Z vers l'avant, +X à droite, origine au sol au centre.
## Chaque véhicule a deux surfaces : la carrosserie (ps1_lit) et les lumières
## (ps1_glow, additives).

enum Kind { SPORT, SEDAN, TRUCK }

const GLASS_COLOR := Color(0.05, 0.06, 0.09)
const TYRE_COLOR := Color(0.04, 0.04, 0.04)
const TAIL_COLOR := Color(1.0, 0.08, 0.05)
const HEAD_COLOR := Color(1.0, 0.92, 0.7)

## Demi-longueur et demi-largeur de chaque gabarit (collisions).
const HALF_LENGTH := {Kind.SPORT: 2.2, Kind.SEDAN: 2.3, Kind.TRUCK: 6.2}
const HALF_WIDTH := {Kind.SPORT: 0.95, Kind.SEDAN: 0.95, Kind.TRUCK: 1.25}

## Halos du véhicule en cours de construction.
static var _halo: SurfaceTool


## Construit le maillage d'un véhicule. `beam` : faisceau des phares au sol.
static func build(kind: Kind, color: Color, body_material: Material, glow_material: Material,
		beam := false, lights := true) -> ArrayMesh:
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


static func _sport(body: SurfaceTool, glow: SurfaceTool, color: Color) -> void:
	# Coin de fromage années 80 : nez bas et effilé, arrière large et haut.
	_prism(body, [
		Vector3(-0.86, 0.3, -2.25), Vector3(0.86, 0.3, -2.25), Vector3(0.99, 0.3, 2.3), Vector3(-0.99, 0.3, 2.3),
		Vector3(-0.84, 0.58, -2.2), Vector3(0.84, 0.58, -2.2), Vector3(0.99, 0.9, 2.3), Vector3(-0.99, 0.9, 2.3)],
		color)
	# Habitacle : pare-brise très incliné, lunette arrière courte.
	_prism(body, [
		Vector3(-0.86, 0.72, -0.6), Vector3(0.86, 0.72, -0.6), Vector3(0.9, 0.86, 1.25), Vector3(-0.9, 0.86, 1.25),
		Vector3(-0.6, 1.17, 0.05), Vector3(0.6, 1.17, 0.05), Vector3(0.66, 1.15, 0.95), Vector3(-0.66, 1.15, 0.95)],
		GLASS_COLOR)
	# Ouïes latérales (les « râpes à fromage »).
	for side in [-1.0, 1.0]:
		for k in 4:
			_box(body, Vector3(side * 0.995, 0.5 + k * 0.08, 1.05), Vector3(0.02, 0.035, 1.5), color * 0.35)
		# Rétroviseur.
		_box(body, Vector3(side * 0.98, 0.95, -0.5), Vector3(0.16, 0.1, 0.18), color)
	# Phares escamotables, levés la nuit.
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * 0.55, 0.66, -1.85), Vector3(0.5, 0.14, 0.32), color)
		_glow_quad(glow, Vector3(side * 0.55, 0.66, -2.02), Vector2(0.42, 0.1), HEAD_COLOR, 1.0)
	# Arrière : grille noire et bandeau de feux sur toute la largeur.
	_box(body, Vector3(0.0, 0.62, 2.31), Vector3(1.9, 0.42, 0.02), Color(0.03, 0.03, 0.035))
	_glow_quad(glow, Vector3(0.0, 0.72, 2.33), Vector2(1.76, 0.1), TAIL_COLOR, 1.0)
	for side in [-1.0, 1.0]:
		Halo.add(_halo, Vector3(side * 0.7, 0.72, 2.4), 0.7, TAIL_COLOR, 0.5)
	for side in [-1.0, 1.0]:
		_glow_strip(glow, side * 0.55, 2.4, 2.8, 0.5, TAIL_COLOR, 0.22)
	_wheels(body, 0.9, [-1.45, 1.5])


static func _sedan(body: SurfaceTool, glow: SurfaceTool, color: Color) -> void:
	_box(body, Vector3(0, 0.62, 0), Vector3(1.85, 0.75, 4.6), color)
	_prism(body, [
		Vector3(-0.85, 1.0, -1.0), Vector3(0.85, 1.0, -1.0), Vector3(0.85, 1.0, 1.4), Vector3(-0.85, 1.0, 1.4),
		Vector3(-0.75, 1.5, -0.5), Vector3(0.75, 1.5, -0.5), Vector3(0.75, 1.5, 1.1), Vector3(-0.75, 1.5, 1.1)],
		GLASS_COLOR)
	_wheels(body, 0.86, [-1.5, 1.5])
	_lights(glow, 0.65, 0.75, 2.31, 0.55, 0.62, -2.31)


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
			_box(body, Vector3(wx + signf(wx) * 0.165, 0.33, wz), Vector3(0.02, 0.3, 0.3), Color(0.26, 0.26, 0.28))


## Feux arrière (x, hauteur, z) + phares avant, et reflet des feux sur la route.
static func _lights(glow: SurfaceTool, tail_x: float, tail_y: float, tail_z: float,
		head_x: float, head_y: float, head_z: float) -> void:
	for side in [-1.0, 1.0]:
		_glow_quad(glow, Vector3(side * tail_x, tail_y, tail_z), Vector2(0.5, 0.14), TAIL_COLOR, 1.0)
		Halo.add(_halo, Vector3(side * tail_x, tail_y, tail_z + 0.08), 0.75, TAIL_COLOR, 0.5)
		_glow_quad(glow, Vector3(side * head_x, head_y, head_z), Vector2(0.4, 0.1), HEAD_COLOR, 1.0)
		_glow_strip(glow, side * tail_x, tail_z + 0.1, 2.8, 0.45, TAIL_COLOR, 0.25)


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
		# Ombrage de face figé, façon PS1 : dessus clair, flancs moyens, avant et
		# arrière plus sombres. Donne du volume sans lumière dynamique.
		var shade := 0.58 + 0.42 * maxf(n.y, 0.0) + 0.16 * absf(n.x) - 0.25 * maxf(-n.y, 0.0)
		var shaded := color * shade
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(shaded.r, shaded.g, shaded.b, 1.0))
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


## Traînée lumineuse couchée sur la route derrière le véhicule.
static func _glow_strip(st: SurfaceTool, x: float, z0: float, length: float, width: float, color: Color, strength: float) -> void:
	var y := 0.03
	var hw := width * 0.5
	var p := [Vector3(x, y, z0), Vector3(x - hw, y, z0), Vector3(x - hw, y, z0 + length), Vector3(x, y, z0 + length),
			Vector3(x, y, z0), Vector3(x + hw, y, z0), Vector3(x + hw, y, z0 + length), Vector3(x, y, z0 + length)]
	var g := [1.0, 0.0, 0.0, 0.0]
	for q in [0, 4]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(color.r, color.g, color.b, strength))
			st.set_uv(Vector2(0, g[i]))
			st.add_vertex(p[q + i])


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

class_name CarView
extends Node3D
## Voiture low-poly générée par code, phares et feux arrière.
## Repère local : -Z vers l'avant, +X à droite, origine au sol au centre.

const BODY_COLOR := Color(0.62, 0.07, 0.06)
const GLASS_COLOR := Color(0.05, 0.06, 0.09)
const TYRE_COLOR := Color(0.04, 0.04, 0.04)
const TAIL_COLOR := Color(1.0, 0.08, 0.05)
const HEAD_COLOR := Color(1.0, 0.92, 0.7)

var material: ShaderMaterial

var _brake_glow := 0.0
var _tail_material: ShaderMaterial


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ps1_lit.gdshader")
	material.set_shader_parameter("affine_strength", 0.0)
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = load("res://shaders/ps1_glow.gdshader")

	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Caisse basse, nez plongeant.
	_prism(body, [
		Vector3(-0.95, 0.25, -2.2), Vector3(0.95, 0.25, -2.2), Vector3(0.95, 0.25, 2.2), Vector3(-0.95, 0.25, 2.2),
		Vector3(-0.92, 0.58, -2.15), Vector3(0.92, 0.58, -2.15), Vector3(0.95, 0.8, 2.2), Vector3(-0.95, 0.8, 2.2)],
		BODY_COLOR)
	# Habitacle.
	_prism(body, [
		Vector3(-0.85, 0.7, -0.7), Vector3(0.85, 0.7, -0.7), Vector3(0.85, 0.78, 1.3), Vector3(-0.85, 0.78, 1.3),
		Vector3(-0.62, 1.18, -0.05), Vector3(0.62, 1.18, -0.05), Vector3(0.66, 1.16, 0.95), Vector3(-0.66, 1.16, 0.95)],
		GLASS_COLOR)
	# Aileron.
	_prism(body, [
		Vector3(-0.9, 0.95, 1.85), Vector3(0.9, 0.95, 1.85), Vector3(0.9, 0.95, 2.25), Vector3(-0.9, 0.95, 2.25),
		Vector3(-0.9, 1.02, 1.85), Vector3(0.9, 1.02, 1.85), Vector3(0.9, 1.02, 2.25), Vector3(-0.9, 1.02, 2.25)],
		BODY_COLOR * 0.8)
	for wx in [-0.88, 0.88]:
		for wz in [-1.4, 1.45]:
			_box(body, Vector3(wx, 0.33, wz), Vector3(0.32, 0.66, 0.68), TYRE_COLOR)
	var mesh := ArrayMesh.new()
	body.commit(mesh)
	mesh.surface_set_material(0, material)

	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_glow_quad(glow, Vector3(side * 0.62, 0.62, 2.21), Vector2(0.5, 0.14), TAIL_COLOR, 1.0)
		_glow_quad(glow, Vector3(side * 0.6, 0.48, -2.21), Vector2(0.4, 0.1), HEAD_COLOR, 1.0)
		# Reflet des feux sur la route mouillée.
		_glow_strip(glow, side * 0.62, 2.3, 2.8, 0.45, TAIL_COLOR, 0.25)
	_headlight_beam(glow)
	glow.commit(mesh)
	mesh.surface_set_material(1, _tail_material)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)



## Lumière ambiante reçue (lampadaires) et freinage : appelé à chaque image.
func set_lighting(lamp: float, braking: bool, delta: float) -> void:
	material.set_shader_parameter("baked_light", 0.18 + lamp * 0.9)
	_brake_glow = lerpf(_brake_glow, 1.0 if braking else 0.0, 1.0 - exp(-12.0 * delta))
	_tail_material.set_shader_parameter("intensity", 0.75 + _brake_glow * 1.2)


func _prism(st: SurfaceTool, c: Array, color: Color) -> void:
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
			st.set_color(Color(color.r, color.g, color.b, 1.0))
			st.set_normal(n)
			st.add_vertex(p[i])


func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c := []
	for y in [-h.y, h.y]:
		for corner in [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]:
			c.append(center + Vector3(corner.x, y, corner.y))
	_prism(st, c, color)


## Rectangle lumineux vertical, face vers l'arrière ou l'avant.
func _glow_quad(st: SurfaceTool, center: Vector3, size: Vector2, color: Color, strength: float) -> void:
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
func _headlight_beam(st: SurfaceTool) -> void:
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


## Traînée lumineuse couchée sur la route derrière la voiture.
func _glow_strip(st: SurfaceTool, x: float, z0: float, length: float, width: float, color: Color, strength: float) -> void:
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

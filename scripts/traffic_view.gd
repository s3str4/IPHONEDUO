class_name TrafficView
extends Node3D
## Affiche les véhicules de Traffic : un réservoir de MeshInstance3D réutilisés,
## un maillage par gabarit et couleur.

const POOL_SIZE := 28
const COLORS := [
	Color(0.55, 0.56, 0.6), Color(0.12, 0.2, 0.42), Color(0.75, 0.72, 0.62), Color(0.1, 0.32, 0.22)]
const TRUCK_COLORS := [Color(0.7, 0.7, 0.72), Color(0.45, 0.12, 0.1), Color(0.18, 0.3, 0.5), Color(0.8, 0.62, 0.2)]

var _meshes := {}
var _ghost_mesh: ArrayMesh
## Rivaux : sportives aux couleurs néon.
var _rival_meshes: Array[ArrayMesh] = []
const RIVAL_COLORS := [Color(0.85, 0.1, 0.45), Color(0.05, 0.55, 0.75), Color(0.85, 0.65, 0.05), Color(0.8, 0.8, 0.85), Color(0.45, 0.1, 0.8)]
var _pool: Array[MeshInstance3D] = []
var _body_material: ShaderMaterial
var _glow_material: ShaderMaterial
## Clignotants (un par côté, partagés), et l'heure pour les faire clignoter.
var _blinkers: Array = []
var _blink_mesh: ArrayMesh
var _time := 0.0


func _ready() -> void:
	_body_material = ShaderMaterial.new()
	_body_material.shader = load("res://shaders/night_car.gdshader")
	_body_material.set_shader_parameter("fill", 0.15)
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = load("res://shaders/night_glow.gdshader")
	# Feux arrière vifs : le trafic se repère de loin.
	_glow_material.set_shader_parameter("intensity", 1.4)
	_ghost_mesh = VehicleMesh.build(VehicleMesh.Kind.SPORT, Color(0.35, 0.05, 0.05), _body_material, _glow_material, false, false)
	for c in RIVAL_COLORS:
		_rival_meshes.append(VehicleMesh.build(VehicleMesh.Kind.SPORT, c, _body_material, _glow_material, false, true, {"aileron": true}))
	for kind in [VehicleMesh.Kind.SPORT, VehicleMesh.Kind.SEDAN, VehicleMesh.Kind.TRUCK]:
		var palette: Array = TRUCK_COLORS if kind == VehicleMesh.Kind.TRUCK else COLORS
		for i in palette.size():
			_meshes[Vector2i(kind, i)] = VehicleMesh.build(kind, palette[i], _body_material, _glow_material)
	_blink_mesh = _make_blinker()
	for i in POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)
		var pair := []
		for side in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			b.mesh = _blink_mesh
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.visible = false
			mi.add_child(b)
			pair.append(b)
		_blinkers.append(pair)


func sync(traffic: Traffic, track: Track, delta := 0.016) -> void:
	_time += delta
	var i := 0
	var all := traffic.vehicles.duplicate()
	if traffic.ghost != null:
		all.append(traffic.ghost)
	for v in all:
		if i >= _pool.size():
			break
		if v.s < track.start_s() or v.s > track.end_s():
			continue
		var mi := _pool[i]
		if v == traffic.ghost:
			mi.mesh = _ghost_mesh
		elif v.rival:
			mi.mesh = _rival_meshes[v.variant % _rival_meshes.size()]
		else:
			mi.mesh = _meshes[Vector2i(v.kind, v.variant % 4)]
		mi.transform = track.transform_at(v.s, v.x)
		# Léger cap pendant les changements de voie.
		mi.rotate_object_local(Vector3.UP, -clampf(v.target_x - v.x, -1.0, 1.0) * 0.08)
		mi.visible = true
		# Clignotant du côté où il va, pendant l'annonce et le changement de voie.
		var dir := signf(v.target_x - v.x)
		var on := absf(v.target_x - v.x) > 0.2 and fmod(_time, 0.5) < 0.28
		for k in 2:
			var b: MeshInstance3D = _blinkers[i][k]
			var side := -1.0 if k == 0 else 1.0
			b.visible = on and side == dir
			b.position = Vector3(side * (v.half_width() - 0.08), 0.75 if v.kind != VehicleMesh.Kind.TRUCK else 1.0,
					v.half_length() + 0.03)
		i += 1
	for k in range(i, _pool.size()):
		_pool[k].visible = false


## Feu orange de clignotant (vers l'arrière), avec son halo.
func _make_blinker() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	VehicleMesh._glow_quad(st, Vector3.ZERO, Vector2(0.22, 0.12), Color(1.0, 0.55, 0.05), 3.0)
	var halo := SurfaceTool.new()
	halo.begin(Mesh.PRIMITIVE_TRIANGLES)
	Halo.add(halo, Vector3(0, 0, 0.05), 0.9, Color(1.0, 0.5, 0.05), 1.2)
	var mesh := st.commit()
	halo.commit(mesh)
	mesh.surface_set_material(0, _glow_material)
	mesh.surface_set_material(1, Halo.material())
	return mesh

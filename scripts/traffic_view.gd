class_name TrafficView
extends Node3D
## Affiche les véhicules de Traffic : un réservoir de MeshInstance3D réutilisés,
## un maillage par gabarit et couleur.

const POOL_SIZE := 28
const COLORS := [
	Color(0.55, 0.56, 0.6), Color(0.12, 0.2, 0.42), Color(0.75, 0.72, 0.62), Color(0.1, 0.32, 0.22)]
const TRUCK_COLORS := [Color(0.7, 0.7, 0.72), Color(0.45, 0.12, 0.1), Color(0.18, 0.3, 0.5), Color(0.8, 0.62, 0.2)]

var _meshes := {}
var _pool: Array[MeshInstance3D] = []
var _body_material: ShaderMaterial
var _glow_material: ShaderMaterial


func _ready() -> void:
	_body_material = ShaderMaterial.new()
	_body_material.shader = load("res://shaders/ps1_lit.gdshader")
	_body_material.set_shader_parameter("affine_strength", 0.0)
	_body_material.set_shader_parameter("baked_light", 0.3)
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = load("res://shaders/ps1_glow.gdshader")
	_glow_material.set_shader_parameter("intensity", 0.9)
	for kind in [VehicleMesh.Kind.SPORT, VehicleMesh.Kind.SEDAN, VehicleMesh.Kind.TRUCK]:
		var palette: Array = TRUCK_COLORS if kind == VehicleMesh.Kind.TRUCK else COLORS
		for i in palette.size():
			_meshes[Vector2i(kind, i)] = VehicleMesh.build(kind, palette[i], _body_material, _glow_material)
	for i in POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)


func sync(traffic: Traffic, track: Track) -> void:
	var i := 0
	for v in traffic.vehicles:
		if i >= _pool.size():
			break
		if v.s < track.start_s() or v.s > track.end_s():
			continue
		var mi := _pool[i]
		mi.mesh = _meshes[Vector2i(v.kind, v.variant % 4)]
		mi.transform = track.transform_at(v.s, v.x)
		# Léger cap pendant les changements de voie.
		mi.rotate_object_local(Vector3.UP, -clampf(v.target_x - v.x, -1.0, 1.0) * 0.08)
		mi.visible = true
		i += 1
	for k in range(i, _pool.size()):
		_pool[k].visible = false

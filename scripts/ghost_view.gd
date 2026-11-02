class_name GhostView
extends Node3D
## L'hologramme du fantôme du record : la sportive du joueur en lumière cyan.

var _mesh: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/night_ghost.gdshader")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = VehicleMesh.build(VehicleMesh.Kind.SPORT, Color.WHITE, _material, _material, false, false)
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Place le fantôme ; il s'efface quand il est tout près de la caméra (sinon
## il remplit l'écran quand on le rattrape).
func show_at(track: Track, s: float, x: float, player_s: float) -> void:
	if s < track.start_s() or s > track.end_s():
		visible = false
		return
	visible = true
	transform = track.transform_at(s, x)
	var d := absf(s - player_s)
	_material.set_shader_parameter("strength", clampf((d - 2.0) / 10.0, 0.15, 1.0))

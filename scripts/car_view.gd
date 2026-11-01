class_name CarView
extends Node3D
## Voiture du joueur : sportive rouge, faisceau des phares, feux arrière qui
## s'intensifient au freinage.

const BODY_COLOR := Color(0.78, 0.08, 0.06)

var material: ShaderMaterial

var _brake_glow := 0.0
var _tail_material: ShaderMaterial


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ps1_lit.gdshader")
	material.set_shader_parameter("affine_strength", 0.0)
	# Lumière précalculée neutre : la teinte sodium saturait le rouge.
	material.set_shader_parameter("baked_tint", Vector3(1.3, 1.1, 0.9))
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = load("res://shaders/ps1_glow.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = VehicleMesh.build(VehicleMesh.Kind.SPORT, BODY_COLOR, material, _tail_material, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Lumière ambiante reçue (lampadaires) et freinage : appelé à chaque image.
func set_lighting(lamp: float, braking: bool, delta: float) -> void:
	material.set_shader_parameter("baked_light", 0.22 + lamp * 0.6)
	_brake_glow = lerpf(_brake_glow, 1.0 if braking else 0.0, 1.0 - exp(-12.0 * delta))
	_tail_material.set_shader_parameter("intensity", 0.75 + _brake_glow * 1.2)

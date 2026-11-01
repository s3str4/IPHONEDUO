class_name CarView
extends Node3D
## Voiture du joueur : sportive rouge, faisceau des phares, feux arrière qui
## s'intensifient au freinage.

const BODY_COLOR := Color(0.6, 0.035, 0.03)

var material: ShaderMaterial

var _brake_glow := 0.0
var _tail_material: ShaderMaterial


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/night_car.gdshader")
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = load("res://shaders/night_glow.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = VehicleMesh.build(VehicleMesh.Kind.SPORT, BODY_COLOR, material, _tail_material, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Lumière ambiante reçue (lampadaires) et freinage : appelé à chaque image.
func set_lighting(lamp: float, braking: bool, delta: float) -> void:
	material.set_shader_parameter("fill", 0.08 + lamp * 0.25)
	_brake_glow = lerpf(_brake_glow, 1.0 if braking else 0.0, 1.0 - exp(-12.0 * delta))
	_tail_material.set_shader_parameter("intensity", 0.75 + _brake_glow * 1.2)

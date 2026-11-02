class_name CarView
extends Node3D
## Voiture du joueur : sportive rouge, faisceau des phares, feux arrière qui
## s'intensifient au freinage.

## Teintes de carrosserie : la rouge, puis une par fin découverte (dans l'ordre
## des fins : la mer, la ville, le barrage, la montagne, nulle part).
const PAINTS := [
	["ROUGE NUIT", Color(0.6, 0.035, 0.03)], ["BLEU MER", Color(0.03, 0.12, 0.45)],
	["BLANC VILLE", Color(0.72, 0.72, 0.74)], ["VERT BARRAGE", Color(0.04, 0.26, 0.12)],
	["OR MONTAGNE", Color(0.55, 0.38, 0.07)], ["NOIR NULLE PART", Color(0.025, 0.025, 0.03)],
]
const BODY_COLOR := Color(0.6, 0.035, 0.03)

var material: ShaderMaterial

var _brake_glow := 0.0
var _tail_material: ShaderMaterial
var _mesh_instance: MeshInstance3D
var _paint := 0
var _options := {}


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/night_car.gdshader")
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = load("res://shaders/night_glow.gdshader")
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	set_paint(0)


func set_paint(index: int) -> void:
	_paint = clampi(index, 0, PAINTS.size() - 1)
	_rebuild()


## Options du garage : {"aileron": bool, "jantes": bool, "neon": Color}.
func set_options(options: Dictionary) -> void:
	_options = options
	_rebuild()


## Couleur du néon sous caisse, ou noir s'il n'y en a pas (pour l'éclairage).
func neon_color() -> Color:
	return _options.get("neon", Color.BLACK)


func _rebuild() -> void:
	var c: Color = PAINTS[_paint][1]
	_mesh_instance.mesh = VehicleMesh.build(VehicleMesh.Kind.SPORT, c, material, _tail_material, true, true, _options)


## Lumière ambiante reçue (lampadaires) et freinage : appelé à chaque image.
func set_lighting(lamp: float, braking: bool, delta: float) -> void:
	material.set_shader_parameter("fill", 0.08 + lamp * 0.25)
	_brake_glow = lerpf(_brake_glow, 1.0 if braking else 0.0, 1.0 - exp(-12.0 * delta))
	_tail_material.set_shader_parameter("intensity", 0.75 + _brake_glow * 1.2)

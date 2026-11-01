extends CPUParticles3D
## Pluie ou neige : particules émises devant la caméra, dans le repère du
## monde. La voiture les traverse à pleine vitesse, ce qui donne l'effet de
## défilement. set_weather() bascule selon l'ambiance (et coupe sous tunnel).

@export var amount_of_drops := 1300

var _quad := QuadMesh.new()
var _mat := StandardMaterial3D.new()
var _snow := false


func _ready() -> void:
	amount = amount_of_drops
	local_coords = false
	lifetime = 0.8
	preprocess = 0.8
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(12.0, 7.0, 26.0)
	position = Vector3(0.0, 2.0, -31.0)
	gravity = Vector3.ZERO
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mat.billboard_keep_scale = true
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_quad.material = _mat
	mesh = _quad
	_apply(false)
	emitting = true


## amount : 0 (sec) à 1 (pluie battante) ; snow : flocons au lieu de gouttes.
func set_weather(amount_ratio: float, snow: bool) -> void:
	if snow != _snow:
		_apply(snow)
	var on := amount_ratio > 0.01
	if emitting != on:
		emitting = on
	amount_ratio = clampf(amount_ratio, 0.0, 1.0)
	_mat.albedo_color.a = (0.8 if snow else 0.36) * amount_ratio


func _apply(snow: bool) -> void:
	_snow = snow
	if snow:
		_quad.size = Vector2(0.09, 0.09)
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mat.albedo_color = Color(0.92, 0.94, 1.0, 0.8)
		direction = Vector3(0.3, -1.0, 0.2)
		spread = 25.0
		initial_velocity_min = 3.0
		initial_velocity_max = 6.0
	else:
		_quad.size = Vector2(0.025, 1.0)
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_mat.albedo_color = Color(0.62, 0.68, 0.85, 0.36)
		direction = Vector3(0.15, -1.0, 0.0)
		spread = 4.0
		initial_velocity_min = 26.0
		initial_velocity_max = 32.0

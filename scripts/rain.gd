extends CPUParticles3D
## Pluie : traits verticaux émis devant la caméra, dans le repère du monde. La
## voiture les traverse à pleine vitesse, ce qui donne l'effet de défilement.

@export var amount_of_drops := 1300


func _ready() -> void:
	amount = amount_of_drops
	local_coords = false
	lifetime = 0.8
	preprocess = 0.8
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(12.0, 7.0, 26.0)
	position = Vector3(0.0, 2.0, -31.0)
	direction = Vector3(0.15, -1.0, 0.0)
	spread = 4.0
	gravity = Vector3.ZERO
	initial_velocity_min = 26.0
	initial_velocity_max = 32.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.62, 0.68, 0.85, 0.36)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = mat
	mesh = quad
	emitting = true

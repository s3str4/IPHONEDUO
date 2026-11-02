class_name CarView
extends Node3D
## Voiture du joueur : sportive, faisceau des phares, feux arrière qui
## s'intensifient au freinage, caisse qui plonge, se cabre et penche, gerbes
## d'eau des roues arrière sur route mouillée, étincelles aux chocs.

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
var _pitch := 0.0
var _roll := 0.0
var _pitch_v := 0.0
var _roll_v := 0.0
var _clock := 0.0
var _spray: MeshInstance3D
var _spray_material := ShaderMaterial.new()
var _sparks: CPUParticles3D


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/night_car.gdshader")
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = load("res://shaders/night_glow.gdshader")
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	set_paint(0)
	_make_sprays()
	_make_sparks()


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


## Mouvements de caisse (ressort amorti) : tangage selon l'accélération
## (m/s², positive = accélère), roulis selon la vitesse latérale (m/s).
func animate(accel: float, lateral: float, speed: float, delta: float) -> void:
	if delta <= 0.0:
		return
	# Pas de temps borné : une image très longue ferait diverger le ressort.
	delta = minf(delta, 1.0 / 30.0)
	_clock += delta
	var target_pitch := clampf(accel * 0.0045, -0.05, 0.04)
	# Roulis vers l'extérieur du mouvement : à gauche, le flanc droit s'écrase.
	var target_roll := clampf(lateral * 0.011, -0.07, 0.07)
	# Ressort amorti : la caisse dépasse un peu sa position puis se pose.
	_pitch_v += ((target_pitch - _pitch) * 90.0 - _pitch_v * 12.0) * delta
	_roll_v += ((target_roll - _roll) * 70.0 - _roll_v * 10.0) * delta
	_pitch = clampf(_pitch + _pitch_v * delta, -0.08, 0.08)
	_roll = clampf(_roll + _roll_v * delta, -0.1, 0.1)
	var buzz := sin(_clock * 37.0) * 0.004 * clampf(speed / 70.0, 0.0, 1.0)
	_mesh_instance.rotation = Vector3(_pitch, 0.0, _roll)
	_mesh_instance.position = Vector3(0.0, buzz + absf(_roll) * 0.15, 0.0)


## Gerbes d'eau : intensité 0..1 (vitesse × humidité), teintées par la lumière.
func set_spray(amount: float, light: float) -> void:
	var lit := 0.5 + light * 0.9
	_spray_material.set_shader_parameter("amount", amount)
	_spray_material.set_shader_parameter("tint", Vector3(0.62, 0.68, 0.8) * lit)
	_spray.visible = amount > 0.02


## Gerbe d'étincelles du côté touché (-1 gauche, 1 droite, 0 devant).
func sparks(side: float) -> void:
	_sparks.position = Vector3(side * 0.95, 0.4, -1.6 if side == 0.0 else 0.3)
	_sparks.restart()
	_sparks.emitting = true


## Deux nappes en « queue de coq » derrière les roues arrière : une feuille
## qui monte et s'élargit vers l'arrière.
func _make_sprays() -> void:
	_spray_material.shader = load("res://shaders/night_spray.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var rows := 6
		for r in rows:
			var a := float(r) / rows
			var b := float(r + 1) / rows
			var pa := _spray_row(side, a)
			var pb := _spray_row(side, b)
			for k in [[pa[0], Vector2(0, a)], [pb[0], Vector2(0, b)], [pb[1], Vector2(1, b)],
					[pa[0], Vector2(0, a)], [pb[1], Vector2(1, b)], [pa[1], Vector2(1, a)]]:
				st.set_uv(k[1])
				st.add_vertex(k[0])
	_spray = MeshInstance3D.new()
	_spray.mesh = st.commit()
	_spray.material_override = _spray_material
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.layers = 1 << (Reflection.RAIN_LAYER - 1)
	_spray.visible = false
	add_child(_spray)


## Bords intérieur et extérieur de la nappe, à la fraction `f` de sa longueur.
func _spray_row(side: float, f: float) -> Array:
	var z := 1.55 + f * 5.5
	var half := 0.18 + f * 0.9
	var y := 0.08 + f * 0.75 - f * f * 0.35
	var center := side * (0.88 + f * 0.25)
	return [Vector3(center - half * 0.6, y * 0.5, z), Vector3(center + half * 0.6 * side * side, y, z)]


func _make_sparks() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.22)
	quad.material = mat
	_sparks = CPUParticles3D.new()
	_sparks.mesh = quad
	_sparks.amount = 48
	_sparks.lifetime = 0.5
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 0.6, 1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 14.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.particle_flag_align_y = true
	_sparks.emitting = false
	add_child(_sparks)


## Lumière ambiante reçue (lampadaires) et freinage : appelé à chaque image.
func set_lighting(lamp: float, braking: bool, delta: float) -> void:
	material.set_shader_parameter("fill", 0.08 + lamp * 0.25)
	_brake_glow = lerpf(_brake_glow, 1.0 if braking else 0.0, 1.0 - exp(-12.0 * delta))
	_tail_material.set_shader_parameter("intensity", 0.75 + _brake_glow * 1.2)

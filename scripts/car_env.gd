class_name CarEnv
extends SubViewport
## Reflets temps réel sur la carrosserie : une petite caméra grand angle,
## posée sur le toit de la voiture, filme ce qu'il y a devant et au-dessus
## (lampadaires, ponts, panneaux, gyrophares, ciel). Le vernis lit cette
## image selon le vecteur réfléchi (shaders/night_car.gdshader) : en roulant,
## les lumières glissent sur le capot, le toit et la lunette. Hors de son
## champ (les flancs), le vernis garde le reflet du ciel calculé.
##
## La voiture du joueur est sur sa propre couche (CAR_LAYER), que cette
## caméra ne voit pas : sinon elle se filmerait de l'intérieur.

const CAR_LAYER := 6
const FOV := 140.0
## Direction filmée : vers l'avant, relevée de PITCH degrés.
const PITCH := 40.0

var _camera := Camera3D.new()
var _enabled := true
var _frame := 0


func _ready() -> void:
	size = Vector2i(128, 128)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_DISABLED
	_camera.fov = FOV
	_camera.near = 0.3
	_camera.far = 260.0
	# Couche 1 seulement : ni la voiture, ni la pluie, ni la route mouillée.
	_camera.cull_mask = 1
	add_child(_camera)
	process_priority = 100
	RenderingServer.global_shader_parameter_set("car_env_tex", get_texture())
	RenderingServer.global_shader_parameter_set("car_env_tan", tan(deg_to_rad(FOV * 0.5)))


## Qualité : 0 éteint, 1 petite image, 2 normale.
func set_quality(q: int) -> void:
	size = Vector2i(96, 96) if q == 1 else Vector2i(128, 128)
	_enabled = q > 0
	render_target_update_mode = SubViewport.UPDATE_ONCE if _enabled else SubViewport.UPDATE_DISABLED
	RenderingServer.global_shader_parameter_set("car_env_on", 1.0 if q > 0 else 0.0)


## Suit la voiture (transformation de la carrosserie). L'image n'est refaite
## qu'une fois sur deux : à l'œil, ça ne se voit pas, et ça épargne le téléphone.
func follow(car: Transform3D) -> void:
	_frame += 1
	if _enabled and _frame % 2 == 0:
		render_target_update_mode = SubViewport.UPDATE_ONCE
	var fwd := -car.basis.z.normalized()
	var up := car.basis.y.normalized()
	var look := (fwd * cos(deg_to_rad(PITCH)) + up * sin(deg_to_rad(PITCH))).normalized()
	var origin := car.origin + up * 1.3
	_camera.global_transform = Transform3D(Basis.looking_at(look, up), origin)
	var b := _camera.global_transform.basis
	RenderingServer.global_shader_parameter_set("car_env_x", b.x)
	RenderingServer.global_shader_parameter_set("car_env_y", b.y)
	RenderingServer.global_shader_parameter_set("car_env_z", b.z)

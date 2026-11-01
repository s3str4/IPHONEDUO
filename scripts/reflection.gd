class_name Reflection
extends SubViewport
## Reflet miroir de la route mouillée : une caméra placée en miroir sous le
## plan de la route (au droit de la voiture) filme la scène ; la route et l'eau
## lisent cette image à leur propre position d'écran (night_surface.gdshader).
## La route et l'eau sont sur la couche 2, que cette caméra ne voit pas.

const WET_LAYER := 2
const RAIN_LAYER := 3

## Rapport de taille avec l'écran (le reflet est flou de toute façon).
@export var scale := 0.5

var source: Camera3D
var _camera := Camera3D.new()


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_DISABLED
	_camera.cull_mask = 1
	add_child(_camera)
	process_priority = 100
	RenderingServer.global_shader_parameter_set("reflection_tex", get_texture())
	RenderingServer.global_shader_parameter_set("reflection_on", 1.0)


## Place la caméra miroir pour le plan passant par `point`, de normale `normal`.
func follow(point: Vector3, normal: Vector3) -> void:
	if source == null:
		return
	var real := Vector2i(DisplayServer.window_get_size())
	size = Vector2i(maxi(16, int(real.x * scale)), maxi(16, int(real.y * scale)))
	_camera.fov = source.fov
	_camera.keep_aspect = source.keep_aspect
	_camera.near = source.near
	_camera.far = source.far
	var n := normal.normalized()
	var m := Basis(Vector3(1, 0, 0) - 2.0 * n.x * n, Vector3(0, 1, 0) - 2.0 * n.y * n, Vector3(0, 0, 1) - 2.0 * n.z * n)
	var t := source.global_transform
	# Base réfléchie (impropre) : l'image obtenue est exactement celle que la
	# caméra principale verrait de la scène retournée sous la route.
	_camera.global_transform = Transform3D(m * t.basis, point + m * (t.origin - point))
	RenderingServer.global_shader_parameter_set("mirror_plane", Vector4(n.x, n.y, n.z, -n.dot(point)))

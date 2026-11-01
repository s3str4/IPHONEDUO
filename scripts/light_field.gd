class_name LightField
extends RefCounted
## Les lumières proches de la caméra, transmises aux shaders par une petite
## texture de données (voir shaders/night_common.gdshaderinc) : les 16 plus
## proches parmi lampadaires, stations, portiques, ponts, panneaux, tunnels.
## Plus loin, la lumière précalculée dans les sommets prend le relais.

const MAX_LIGHTS := 16

var _image := Image.create(MAX_LIGHTS, 2, false, Image.FORMAT_RGBAF)
var _texture: ImageTexture
var _blink := 0.0


func _init() -> void:
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("lights_tex", _texture)


## sources : [[position, couleur, portée, intensité], ...] (RoadBuilder.light_sources).
func update(sources: Array, camera_pos: Vector3, delta: float) -> void:
	_blink += delta
	sources.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0].distance_squared_to(camera_pos) < b[0].distance_squared_to(camera_pos))
	var n := mini(sources.size(), MAX_LIGHTS)
	for i in n:
		var src: Array = sources[i]
		var p: Vector3 = src[0]
		var c: Color = src[1]
		var intensity: float = src[3]
		# Balises clignotantes (intensité négative = clignote).
		if intensity < 0.0:
			intensity = -intensity * (1.0 if fmod(_blink, 0.8) < 0.4 else 0.15)
		_image.set_pixel(i, 0, Color(p.x, p.y, p.z, src[2]))
		_image.set_pixel(i, 1, Color(c.r, c.g, c.b, intensity))
	_texture.update(_image)
	RenderingServer.global_shader_parameter_set("light_count", float(n))

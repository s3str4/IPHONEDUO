class_name Halo
extends RefCounted
## Halos lumineux face caméra (voir shaders/night_halo.gdshader).

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/night_halo.gdshader")
	return _material


## Ajoute un halo de `size` mètres de rayon centré en `center`.
static func add(st: SurfaceTool, center: Vector3, size: float, color: Color, strength: float) -> void:
	for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1)]:
		st.set_color(Color(color.r, color.g, color.b, strength))
		st.set_uv(corner)
		st.set_uv2(Vector2(size, 0.0))
		st.add_vertex(center)

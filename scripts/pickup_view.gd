class_name PickupView
extends Node3D
## Affiche les jetons (losanges cyan qui tournent) et les bonus de temps
## (losanges magenta plus gros), avec leur halo, par instanciation (MultiMesh).

const MAX_SHOWN := 64
const TOKEN_COLOR := Color(0.3, 0.95, 1.0)
const TIME_COLOR := Color(1.0, 0.3, 0.75)

var _tokens := MultiMeshInstance3D.new()
var _times := MultiMeshInstance3D.new()
var _time := 0.0


func _ready() -> void:
	for pair in [[_tokens, _diamond(0.44, TOKEN_COLOR, 1.6)], [_times, _diamond(0.7, TIME_COLOR, 2.8)]]:
		var mmi: MultiMeshInstance3D = pair[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[1]
		mm.instance_count = MAX_SHOWN
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Deux losanges croisés, lumineux, et un halo.
func _diamond(r: float, color: Color, halo_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var p := [Vector3(0, r * 1.3, 0), axis * r, Vector3(0, -r * 1.3, 0), -axis * r]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_color(Color(color.r, color.g, color.b, 2.4))
				st.set_uv(Vector2(0, 1))
				st.add_vertex(p[k])
	var halo := SurfaceTool.new()
	halo.begin(Mesh.PRIMITIVE_TRIANGLES)
	Halo.add(halo, Vector3.ZERO, halo_size, color, 0.9)
	var mesh := st.commit()
	halo.commit(mesh)
	var glow := ShaderMaterial.new()
	glow.shader = load("res://shaders/night_glow.gdshader")
	mesh.surface_set_material(0, glow)
	mesh.surface_set_material(1, Halo.material())
	return mesh


func sync(pickups: Pickups, track: Track, car_s: float, delta: float) -> void:
	_time += delta
	var counts := [0, 0]
	var limit := minf(car_s + 360.0, track.end_s())
	for it in pickups.visible_between(maxf(car_s - 10.0, track.start_s()), limit):
		var k := 0 if it.kind == Pickups.Kind.TOKEN else 1
		var mm: MultiMesh = (_tokens if k == 0 else _times).multimesh
		if counts[k] >= MAX_SHOWN:
			continue
		var t := track.transform_at(it.s, it.x, 1.0 + 0.12 * sin(_time * 3.0 + it.s * 0.1))
		t.basis = t.basis.rotated(t.basis.y.normalized(), _time * 2.5 + it.s * 0.05)
		mm.set_instance_transform(counts[k], t)
		counts[k] += 1
	_tokens.multimesh.visible_instance_count = counts[0]
	_times.multimesh.visible_instance_count = counts[1]

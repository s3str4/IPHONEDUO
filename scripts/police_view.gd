class_name PoliceView
extends Node3D
## La voiture de police à l'écran : garée phares éteints derrière la
## glissière tant qu'on ne l'a pas réveillée, puis lancée à vos trousses,
## rampe de gyrophares en alternance rouge et bleu (avec leurs halos ; la
## lumière portée sur la route est une source de LightField, voir Main).

const RED := Color(1.0, 0.08, 0.06)
const BLUE := Color(0.15, 0.35, 1.0)
## Période d'alternance des gyrophares (s).
const FLASH := 0.36

var _car: MeshInstance3D
var _red: MeshInstance3D
var _blue: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	var body := ShaderMaterial.new()
	body.shader = load("res://shaders/night_car.gdshader")
	body.set_shader_parameter("fill", 0.15)
	var glow := ShaderMaterial.new()
	glow.shader = load("res://shaders/night_glow.gdshader")
	glow.set_shader_parameter("intensity", 0.9)
	_car = MeshInstance3D.new()
	_car.mesh = VehicleMesh.build(VehicleMesh.Kind.SEDAN, Color(0.03, 0.045, 0.1), body, glow)
	_car.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_car)
	# Bandes blanches sur les flancs et rampe sur le toit.
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		VehicleMesh._box(trim, Vector3(side * 0.99, 0.62, 0.0), Vector3(0.03, 0.16, 3.2), Color(0.85, 0.86, 0.9, 1.0))
	VehicleMesh._box(trim, Vector3(0, 1.47, 0.1), Vector3(1.3, 0.1, 0.3), Color(0.05, 0.05, 0.06, 0.5))
	trim.generate_normals()
	var trim_mi := MeshInstance3D.new()
	trim_mi.mesh = trim.commit()
	trim_mi.material_override = body
	_car.add_child(trim_mi)
	_red = _lamp(-0.34, RED, glow)
	_blue = _lamp(0.34, BLUE, glow)
	visible = false


func _lamp(x: float, color: Color, glow: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(x, 1.6, 0.1)
	for z in [-0.16, 0.16]:
		VehicleMesh._glow_quad(st, c + Vector3(0, 0, z), Vector2(0.56, 0.16), color, 3.0)
	var halo := SurfaceTool.new()
	halo.begin(Mesh.PRIMITIVE_TRIANGLES)
	Halo.add(halo, c, 2.4, color, 1.4)
	var mesh := st.commit()
	halo.commit(mesh)
	mesh.surface_set_material(0, glow)
	mesh.surface_set_material(1, Halo.material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_car.add_child(mi)
	return mi


## Rouge allumé pendant la première moitié de la période, bleu ensuite.
static func red_on(t: float) -> bool:
	return fmod(t, FLASH) < FLASH * 0.5


## Place la voiture : en poursuite, sinon garée près du joueur (à moins de
## 600 m devant), sinon cachée.
func sync(police: Police, car: CarPhysics, track: Track, water_side: Callable, delta: float) -> void:
	_time += delta
	if police.active() or police.hold > 0.0:
		visible = true
		transform = track.transform_at(police.s, police.x)
		rotate_object_local(Vector3.UP, -clampf((police.ram_x if police.state == Police.State.RAM else police.x) - police.x, -1.0, 1.0) * 0.1)
		_red.visible = red_on(_time)
		_blue.visible = not _red.visible
		return
	_red.visible = false
	_blue.visible = false
	var stage := RouteMap.stage_at(car.s)
	visible = false
	if police.patrols.has(stage) and not police.woken(stage):
		var p: float = police.patrols[stage]
		if p > car.s - 30.0 and p < car.s + 600.0 and p >= track.start_s() and p <= track.end_s():
			var side := police.patrol_side(stage, water_side.call(p))
			visible = true
			transform = track.transform_at(p, side * Police.PATROL_X)
			# Garée en biais, le nez vers la route.
			rotate_object_local(Vector3.UP, side * 0.35)


## Sources de lumière des gyrophares pour LightField (vide hors poursuite).
func light_sources() -> Array:
	if not visible or not (_red.visible or _blue.visible):
		return []
	var on := _red if _red.visible else _blue
	var c: Color = RED if _red.visible else BLUE
	return [[_car.global_transform * Vector3(0, 2.2, 0.1), c, 34.0, 4.5]]

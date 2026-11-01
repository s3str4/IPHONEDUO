extends Node3D
## Prototype M0 : route infinie sous la pluie, voiture, pouce pour tourner.
##
## Arguments (après `--`) :
##   --seed=N           graine de la route
##   --autopilot        la voiture se conduit seule (captures, démos)
##   --capture=PATH     enregistre une image PNG puis quitte
##   --capture_at=SEC   instant de la capture (défaut 6)

const CHUNKS_BEHIND := 1
const CHUNKS_AHEAD := 4
const CAMERA_BACK := 8.0
const CAMERA_HEIGHT := 4.2

var track: Track
var builder: RoadBuilder
var car := CarPhysics.new()

var _chunks := {}
var _args := {}
var _time := 0.0
var _shake := 0.0
var _cam_x := 0.0

@onready var car_view: CarView = $Car
@onready var camera: Camera3D = $Camera
@onready var input: ThumbInput = $ThumbInput
@onready var speed_label: Label = $Hud/Speed
@onready var distance_label: Label = $Hud/Distance


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var seed := int(_args.get("seed", "1"))
	track = Track.new(seed)
	builder = RoadBuilder.new(track, seed)
	if _args.has("autopilot"):
		car.speed = 40.0
	_update_chunks()
	_place_car_and_camera(0.0)


func _physics_process(delta: float) -> void:
	var throttle := input.throttle
	var steer := input.steer
	if _args.has("autopilot"):
		throttle = 1.0
		steer = car.autopilot_steer(track, 2.0 * sin(_time * 0.2))
	car.step(track, throttle, steer, delta)
	if car.hit_rail:
		_shake = 0.35
	track.ensure(car.s + CHUNKS_AHEAD * RoadBuilder.CHUNK_LENGTH + 200.0)
	track.trim(car.s - (CHUNKS_BEHIND + 1) * RoadBuilder.CHUNK_LENGTH)


func _process(delta: float) -> void:
	_time += delta
	_update_chunks()
	_place_car_and_camera(delta)
	car_view.set_lighting(builder.lamp_light(car.s, car.x), input.throttle == 0.0 and not _args.has("autopilot"), delta)
	speed_label.text = "%d km/h" % int(round(car.speed_kmh()))
	distance_label.text = "%.1f km" % (car.s / 1000.0)
	if _args.has("capture") and _time >= float(_args.get("capture_at", "6")):
		get_viewport().get_texture().get_image().save_png(_args["capture"])
		get_tree().quit()


func _update_chunks() -> void:
	var current := int(floor(car.s / RoadBuilder.CHUNK_LENGTH))
	var wanted := {}
	for i in range(maxi(0, current - CHUNKS_BEHIND), current + CHUNKS_AHEAD + 1):
		wanted[i] = true
		if not _chunks.has(i):
			var chunk := builder.build_chunk(i)
			$Road.add_child(chunk)
			_chunks[i] = chunk
	for i in _chunks.keys():
		if not wanted.has(i):
			_chunks[i].queue_free()
			_chunks.erase(i)


func _place_car_and_camera(delta: float) -> void:
	var t := track.transform_at(car.s, car.x)
	car_view.transform = t
	car_view.rotate_object_local(Vector3.UP, -car.slip)
	car_view.rotate_object_local(Vector3.BACK, car.slip * 0.15)

	# Caméra derrière la voiture, qui suit à moitié ses écarts latéraux.
	var k := 1.0 - exp(-5.0 * delta) if delta > 0.0 else 1.0
	_cam_x = lerpf(_cam_x, car.x * 0.6, k)
	var cam_s := car.s - CAMERA_BACK
	var eye := track.transform_at(cam_s, _cam_x, CAMERA_HEIGHT).origin
	# Visée basse : en portrait le champ vertical est immense, on le donne à la
	# route devant plutôt qu'au ciel.
	var target := track.transform_at(car.s + 12.0, car.x * 0.4, -3.1).origin
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.25
	camera.look_at_from_position(eye, target, Vector3.UP)
	camera.fov = lerpf(60.0, 72.0, car.speed / CarPhysics.TOP_SPEED)

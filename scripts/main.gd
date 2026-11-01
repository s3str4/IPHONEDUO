extends Node3D
## Partie M1 : une nuit, un chemin, cinq étapes jusqu'à l'aube.
##
## Arguments (après `--`) :
##   --seed=N           graine de la route et du trafic
##   --autopilot        la voiture se conduit seule (captures, démos)
##   --start_s=M        démarre à M mètres (captures de l'aube, des stations)
##   --capture=PATH     enregistre une image PNG puis quitte
##   --capture_at=SEC   instant de la capture (défaut 6)

const CHUNKS_BEHIND := 1
const CHUNKS_AHEAD := 4
const CAMERA_BACK := 8.0
const CAMERA_HEIGHT := 4.2
const SAVE_PATH := "user://save.cfg"
const START_S := 30.0

const NIGHT_FOG := Color(0.05, 0.06, 0.12)
const DAWN_FOG := Color(0.42, 0.3, 0.34)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.12)
const DAWN_HORIZON := Color(0.55, 0.36, 0.38)
const NIGHT_ZENITH := Color(0.01, 0.012, 0.03)
const DAWN_ZENITH := Color(0.12, 0.16, 0.32)

## Rejouer depuis l'écran de fin saute l'écran de titre.
static var quick_restart := false

var track: Track
var builder: RoadBuilder
var car := CarPhysics.new()
var traffic: Traffic
var game := GameRun.new()

var _chunks := {}
var _args := {}
var _time := 0.0
var _shake := 0.0
var _cam_x := 0.0
var _end_time := 0.0
var _best := 0
var _sky_material: ShaderMaterial

@onready var car_view: CarView = $Car
@onready var traffic_view: TrafficView = $Traffic
@onready var camera: Camera3D = $Camera
@onready var input: ThumbInput = $ThumbInput
@onready var hud: Hud = $Hud
@onready var environment: Environment = $WorldEnvironment.environment


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var seed := int(_args.get("seed", "1"))
	track = Track.new(seed)
	builder = RoadBuilder.new(track, seed)
	builder.stations = RunConfig.stations()
	builder.arrival_s = RunConfig.arrival_s()
	traffic = Traffic.new(seed)
	_sky_material = environment.sky.sky_material
	_best = _load_best()

	game.station_reached.connect(_on_station)
	game.near_miss.connect(func(pts: int) -> void: hud.popup("FRÔLÉ  +%d" % pts, Hud.WHITE, 13, 210.0))
	game.chain_broken.connect(func() -> void: hud.popup("CHAÎNE PERDUE", Hud.RED, 11, 236.0))
	game.arrived.connect(_on_arrived)
	game.time_up.connect(_on_time_up)

	# Départ un peu après le début de la route : la caméra, derrière, doit
	# avoir de la route sous elle.
	car.s = START_S
	if _args.has("start_s"):
		car.s = float(_args["start_s"])
		track.ensure(car.s + 800.0)
		track.trim(car.s - 300.0)
	if _args.has("autopilot") or _args.has("start_s") or quick_restart:
		_start()
	else:
		hud.show_overlay("ROUTE DE NUIT",
				"Une nuit, une route.\nAtteins l'aube avant la fin du chrono.\n\nMeilleur score : %s" % Hud._group(_best),
				"pose ton pouce pour démarrer")
	_update_chunks()
	_place_car_and_camera(0.0)


func _start() -> void:
	hud.hide_overlay()
	game.start(car.s)
	if _args.has("autopilot") and car.speed == 0.0:
		car.speed = 40.0


func _physics_process(delta: float) -> void:
	if game.state == GameRun.State.WAITING:
		if input.throttle > 0.0:
			_start()
		else:
			return
	var throttle := input.throttle
	var steer := input.steer
	if _args.has("autopilot"):
		throttle = 1.0
		steer = car.autopilot_steer(track, traffic.best_lane(car))
		if traffic.free_gap(car, car.x) < 12.0 + maxf(0.0, car.speed - traffic.speed_ahead(car, car.x)) * 0.45:
			throttle = 0.0
	if game.state != GameRun.State.RUNNING:
		throttle = 0.0

	car.step(track, throttle, steer, delta)
	if car.hit_rail:
		_shake = 0.35
		game.on_crash(car.s)
	traffic.density = RunConfig.TRAFFIC_DENSITY[game.segment()]
	for e in traffic.update(car, delta):
		if e.type == "crash":
			_shake = 0.5
			game.on_crash(car.s)
		else:
			game.on_near_miss()
	game.update(car.s, absf(car.slip) > 0.12 and car.speed > 45.0, delta)

	track.ensure(car.s + CHUNKS_AHEAD * RoadBuilder.CHUNK_LENGTH + 200.0)
	track.trim(car.s - (CHUNKS_BEHIND + 1) * RoadBuilder.CHUNK_LENGTH)

	# Rejouer depuis l'écran de fin.
	if game.state in [GameRun.State.ARRIVED, GameRun.State.TIME_UP] and _time - _end_time > 2.0 \
			and input.throttle > 0.0 and not _args.has("autopilot"):
		quick_restart = true
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	_time += delta
	_update_chunks()
	_place_car_and_camera(delta)
	traffic_view.sync(traffic, track)
	car_view.set_lighting(builder.lamp_light(car.s, car.x), input.throttle == 0.0 and not _args.has("autopilot"), delta)
	hud.set_values(game.time_left, game.score, game.segment(), game.multiplier(), car.speed_kmh())
	_update_dawn()
	if _args.has("capture") and _time >= float(_args.get("capture_at", "6")):
		get_viewport().get_texture().get_image().save_png(_args["capture"])
		get_tree().quit()


## Le ciel s'éclaircit pendant toute la partie : c'est aussi la jauge d'avancement.
func _update_dawn() -> void:
	var p := clampf(car.s / RunConfig.arrival_s(), 0.0, 1.0)
	var d := smoothstep(0.25, 1.0, p)
	_sky_material.set_shader_parameter("dawn", d)
	_sky_material.set_shader_parameter("horizon", NIGHT_HORIZON.lerp(DAWN_HORIZON, d))
	_sky_material.set_shader_parameter("zenith", NIGHT_ZENITH.lerp(DAWN_ZENITH, d * d))
	RenderingServer.global_shader_parameter_set("ps1_fog_color", NIGHT_FOG.lerp(DAWN_FOG, d))
	environment.ambient_light_energy = lerpf(0.5, 1.6, d)


func _on_station(index: int, added: float) -> void:
	hud.popup("+%d s" % int(added), Hud.AMBER, 30, 150.0)
	hud.popup("STATION %d" % (index + 1), Hud.WHITE, 12, 196.0)


func _on_arrived(bonus: int) -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	hud.show_overlay("L'AUBE",
			"%s\n\nBonus de temps : %s\nFrôlages : %d   Chocs : %d\n\nSCORE  %s\n%s" % [
				RunConfig.DESTINATION.to_upper(), Hud._group(bonus), game.near_misses, game.crashes,
				Hud._group(int(game.score)), "NOUVEAU RECORD !" if record else "Record : %s" % Hud._group(_best)],
			"touche pour rejouer")


func _on_time_up() -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	hud.show_overlay("LA NUIT GAGNE",
			"Étape %d sur %d\n%.1f km parcourus\n\nSCORE  %s\n%s" % [
				game.segment() + 1, RunConfig.SEGMENT_COUNT, car.s / 1000.0, Hud._group(int(game.score)),
				"NOUVEAU RECORD !" if record else "Record : %s" % Hud._group(_best)],
			"touche pour rejouer")


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("scores", "best", 0))


## Enregistre le score s'il bat le record ; renvoie vrai si c'est un record.
func _save_best(score: int) -> bool:
	if score <= _best or _args.has("autopilot"):
		return false
	_best = score
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("scores", "best", score)
	cfg.save(SAVE_PATH)
	return true


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

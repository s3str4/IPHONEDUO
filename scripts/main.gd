extends Node3D
## Partie M1 : une nuit, un chemin, cinq étapes jusqu'à l'aube.
##
## Arguments (après `--`) :
##   --seed=N           graine de la route et du trafic
##   --autopilot        la voiture se conduit seule (captures, démos)
##   --start_s=M        démarre à M mètres (captures de l'aube, des stations)
##   --showcase         écran de titre sans interface (captures de la voiture)
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
## Construction des tronçons en tâche de fond (35 ms chacun : trop pour une
## image). Le fil a son propre tracé : même graine, donc même route, et rien
## n'est partagé avec la boucle de jeu.
var _worker_builder: RoadBuilder
var _building := -1
var _build_task_id := -1
## Tronçon construit par la tâche, pas encore récupéré par la boucle de jeu.
var _pending: MeshInstance3D
## Images où un tronçon visible manquait encore (rapporté à la capture).
var _late_frames := 0
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
	_worker_builder = RoadBuilder.new(Track.new(seed), seed)
	_worker_builder.stations = builder.stations
	_worker_builder.arrival_s = builder.arrival_s
	# Ressources partagées créées ici, avant toute tâche de fond.
	Hud.arcade_font()
	Halo.material()
	traffic = Traffic.new(seed)
	_sky_material = environment.sky.sky_material
	_best = _load_best()

	game.station_reached.connect(_on_station)
	game.near_miss.connect(func(pts: int) -> void: hud.popup("FRÔLÉ +%d" % pts, Hud.WHITE, 8, 210.0))
	game.chain_broken.connect(func() -> void: hud.popup("CHAÎNE PERDUE", Hud.RED, 8, 232.0))
	game.arrived.connect(_on_arrived)
	game.time_up.connect(_on_time_up)

	# Départ sous le premier lampadaire allumé (la caméra, derrière, doit aussi
	# avoir de la route sous elle) : la voiture est mise en valeur au titre.
	car.s = _first_lamp_after(START_S)
	if _args.has("start_s"):
		car.s = float(_args["start_s"])
		track.ensure(car.s + 800.0)
		track.trim(car.s - 300.0)
	if _args.has("showcase"):
		hud.visible = false
	elif _args.has("autopilot") or _args.has("start_s") or quick_restart:
		_start()
	else:
		hud.show_overlay("",
				"Une nuit. Une route.\nAtteins l'aube\navant la fin du chrono.\n\nRECORD %s" % Hud._group(_best),
				"POSE TON POUCE", true)
	_update_chunks(true)
	_place_car_and_camera(0.0)


func _exit_tree() -> void:
	if _building != -1:
		WorkerThreadPool.wait_for_task_completion(_build_task_id)
		_building = -1
	if _pending != null:
		_pending.free()
		_pending = null


func _first_lamp_after(s: float) -> float:
	var k := int(ceil(s / RoadBuilder.LAMP_SPACING))
	while builder.lamp_side(k) == 0:
		k += 1
	return k * RoadBuilder.LAMP_SPACING + 2.0


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
	hud.set_values(game.time_left, game.score, game.segment(), game.multiplier(), car.speed_kmh(), game.progress())
	_update_dawn()
	var cur := int(floor(car.s / RoadBuilder.CHUNK_LENGTH))
	for i in range(cur, cur + 3):
		if not _chunks.has(i):
			_late_frames += 1
			break
	if _args.has("capture") and _time >= float(_args.get("capture_at", "6")):
		print("tronçons en retard : %d images" % _late_frames)
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
	hud.popup("+%d" % int(added), Hud.AMBER, 32, 140.0)
	hud.popup("STATION %d" % (index + 1), Hud.WHITE, 8, 188.0)


func _on_arrived(bonus: int) -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	hud.show_overlay("L'AUBE",
			"%s\n\nBONUS TEMPS %s\nFRÔLAGES    %d\nCHOCS       %d\n\nSCORE %s\n\n%s" % [
				RunConfig.DESTINATION.to_upper(), Hud._group(bonus), game.near_misses, game.crashes,
				Hud._group(int(game.score)), "NOUVEAU RECORD !" if record else "RECORD %s" % Hud._group(_best)],
			"TOUCHE POUR REJOUER")


func _on_time_up() -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	hud.show_overlay("LA NUIT\nGAGNE",
			"\nÉTAPE %d SUR %d\n%.1f KM\n\nSCORE %s\n\n%s" % [
				game.segment() + 1, RunConfig.SEGMENT_COUNT, car.s / 1000.0, Hud._group(int(game.score)),
				"NOUVEAU RECORD !" if record else "RECORD %s" % Hud._group(_best)],
			"TOUCHE POUR REJOUER")


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


## Tient les tronçons autour de la voiture. `blocking` : tout construire tout
## de suite (au démarrage) ; sinon un tronçon à la fois, en tâche de fond, le
## plus proche d'abord.
func _update_chunks(blocking := false) -> void:
	var current := int(floor(car.s / RoadBuilder.CHUNK_LENGTH))
	var wanted := {}
	var missing := -1
	for i in range(maxi(0, current - CHUNKS_BEHIND), current + CHUNKS_AHEAD + 1):
		wanted[i] = true
		if not _chunks.has(i) and missing == -1:
			missing = i
		if blocking and not _chunks.has(i):
			_add_chunk(i, _worker_builder.build_chunk(i))
	if not blocking and missing != -1 and _building == -1:
		_building = missing
		_build_task_id = WorkerThreadPool.add_task(_build_in_background.bind(missing))
	for i in _chunks.keys():
		if not wanted.has(i):
			_chunks[i].queue_free()
			_chunks.erase(i)


func _build_in_background(index: int) -> void:
	_pending = _worker_builder.build_chunk(index)
	_worker_builder.track.trim((index - 2) * RoadBuilder.CHUNK_LENGTH)
	_on_chunk_built.call_deferred(index)


func _on_chunk_built(index: int) -> void:
	if _building == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_build_task_id)
	_building = -1
	var mi := _pending
	_pending = null
	if _chunks.has(index) or absf(index * RoadBuilder.CHUNK_LENGTH - car.s) > 800.0:
		mi.free()
		return
	_add_chunk(index, mi)


func _add_chunk(index: int, mi: MeshInstance3D) -> void:
	$Road.add_child(mi)
	_chunks[index] = mi


func _place_car_and_camera(delta: float) -> void:
	var t := track.transform_at(car.s, car.x)
	car_view.transform = t
	car_view.rotate_object_local(Vector3.UP, -car.slip)
	car_view.rotate_object_local(Vector3.BACK, car.slip * 0.15)

	if game.state == GameRun.State.WAITING:
		# Écran de titre : la caméra tourne lentement autour de la voiture arrêtée.
		var a := _time * 0.25 + 2.2
		var orbit := t.origin + t.basis * Vector3(sin(a) * 6.5, 1.7, cos(a) * 6.5)
		camera.look_at_from_position(orbit, t.origin + t.basis.y * 0.8, Vector3.UP)
		camera.fov = 62.0
		return

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

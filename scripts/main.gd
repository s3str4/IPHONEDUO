extends Node3D
## Une nuit jusqu'à l'aube : cinq étapes, quatre bifurcations, quinze
## ambiances, des événements étranges, Radio Nuit et cinq fins.
##
## Arguments (après `--`) :
##   --seed=N           graine de la route et du trafic
##   --autopilot        la voiture se conduit seule (captures, démos)
##   --path=0110        chemin du pilote automatique (0 gauche, 1 droite)
##   --start_s=M        démarre à M mètres (captures de l'aube, des stations) ;
##                      les bifurcations sautées suivent --path
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
const FOG_START := 40.0
const FOG_END := 260.0
## Avant une bifurcation, ses directions s'affichent sur cette distance (m).
const FORK_PROMPT := 1200.0

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
var _post_material: ShaderMaterial
var _events: EventDirector
var _path := [0, 0, 0, 0]
var _runs := 0
var _endings_seen := {}
## File de Radio Nuit : [texte, s au-delà duquel la réplique n'a plus de sens].
var _radio_queue := []
var _low_time_said := false
var _fork_said := false
var _prev_s := 0.0
## Brouillard et météo courants, qui glissent vers ceux de l'ambiance.
var _fog_scale := 1.0
var _fog_tint := NIGHT_FOG
var _rain := 1.0

@onready var car_view: CarView = $Car
@onready var traffic_view: TrafficView = $Traffic
@onready var camera: Camera3D = $Camera
@onready var input: ThumbInput = $ThumbInput
@onready var hud: Hud = $Hud
@onready var environment: Environment = $WorldEnvironment.environment
@onready var rain: CPUParticles3D = $Camera/Rain


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var seed := int(_args.get("seed", "1"))
	if _args.has("path"):
		_path.clear()
		for c in str(_args["path"]):
			_path.append(int(c))
	_load_save()
	_events = EventDirector.new(seed, _runs)
	track = Track.new(seed, true)
	builder = RoadBuilder.new(track, seed)
	builder.stations = RunConfig.stations()
	builder.arrival_s = RunConfig.arrival_s()
	builder.events = _events
	_worker_builder = RoadBuilder.new(Track.new(seed, true), seed)
	_worker_builder.stations = builder.stations
	_worker_builder.arrival_s = builder.arrival_s
	_worker_builder.events = EventDirector.new(seed, _runs)
	# Ressources partagées créées ici, avant toute tâche de fond.
	Hud.arcade_font()
	Halo.material()
	traffic = Traffic.new(seed)
	_sky_material = environment.sky.sky_material
	_post_material = $Post/Screen.material

	game.station_reached.connect(_on_station)
	game.near_miss.connect(func(pts: int) -> void: hud.popup("FRÔLÉ +%d" % pts, Hud.WHITE, 8, 210.0))
	game.chain_broken.connect(func() -> void: hud.popup("CHAÎNE PERDUE", Hud.RED, 8, 232.0))
	game.arrived.connect(_on_arrived)
	game.time_up.connect(_on_time_up)
	game.fork_taken.connect(_on_fork)
	game.region_entered.connect(_on_region)

	# Départ sous le premier lampadaire allumé (la caméra, derrière, doit aussi
	# avoir de la route sous elle) : la voiture est mise en valeur au titre.
	car.s = _first_lamp_after(START_S)
	if _args.has("start_s"):
		car.s = float(_args["start_s"])
		for k in RouteMap.STAGES.size() - 1:
			if RouteMap.fork_s(k) + RouteMap.DIVIDER_START <= car.s:
				game.choices.append(_path[k] if k < _path.size() else 0)
		_sync_choices()
		car.x = 4.0 if RouteMap.divider_fork(car.s) != -1 and game.choices.back() == 1 else car.x
		car.x = -4.0 if RouteMap.divider_fork(car.s) != -1 and game.choices.back() == 0 else car.x
		track.ensure(car.s + 800.0)
		track.trim(car.s - 300.0)
	_prev_s = car.s
	if _args.has("showcase"):
		hud.visible = false
	elif _args.has("autopilot") or _args.has("start_s") or quick_restart:
		_start()
	else:
		hud.show_overlay("",
				"Une nuit. Une route.\nAtteins l'aube\navant la fin du chrono.\n\nRECORD %s\nFINS %d/%d" % [
					Hud._group(_best), _endings_seen.size(), RouteMap.ENDINGS.size()],
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
	for lamp in builder.lamps_between(s, s + 400.0):
		if lamp[1] != 0:
			return lamp[0] + 2.0
	return s


func _start() -> void:
	hud.hide_overlay()
	game.start(car.s)
	if not _args.has("autopilot"):
		_runs += 1
		_write_save()
	if car.s < RouteMap.region_start(1):
		_say(Scenario.RADIO["start"])
		_say(Scenario.RADIO["call"])
	if _args.has("autopilot") and car.speed == 0.0:
		car.speed = 40.0


func _sync_choices() -> void:
	track.choices.assign(game.choices)
	builder.choices = game.choices.duplicate()


## Ajoute une réplique à la file de Radio Nuit ; elle est oubliée si la
## voiture a passé `until_s` avant qu'elle ait pu passer à l'antenne.
func _say(text: String, until_s := INF) -> void:
	_radio_queue.append([text, until_s])


func _physics_process(delta: float) -> void:
	if game.state == GameRun.State.WAITING:
		if input.throttle > 0.0:
			_start()
		else:
			return
	var throttle := input.throttle
	var steer := input.steer
	if _args.has("autopilot"):
		var cmd := Autopilot.drive(car, track, traffic, _path, Autopilot.Driver.GOOD)
		throttle = cmd[0]
		steer = cmd[1]
	if game.state != GameRun.State.RUNNING:
		throttle = 0.0

	car.step(track, throttle, steer, delta)
	if car.hit_rail:
		_shake = 0.5 if car.hit_divider else 0.35
		game.on_crash(car.s)
	var th := builder.theme_at(car.s)
	traffic.density = RunConfig.TRAFFIC_DENSITY[game.segment()] * th.get("traffic", 1.0)
	traffic.truck_ratio = th.get("trucks", 0.2)
	for e in traffic.update(car, delta):
		if e.type == "crash":
			_shake = 0.5
			game.on_crash(car.s)
		else:
			game.on_near_miss()
	_update_events()
	game.update(car.s, car.x, absf(car.slip) > 0.12 and car.speed > 45.0, delta)
	_prev_s = car.s

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
	_update_weather(delta)
	_update_fork_prompt()
	while not _radio_queue.is_empty() and not hud.radio_busy():
		var line: Array = _radio_queue.pop_front()
		if car.s < line[1]:
			hud.radio(line[0])
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
	RenderingServer.global_shader_parameter_set("ps1_fog_color", _fog_tint.lerp(DAWN_FOG, d * 0.8))
	environment.ambient_light_energy = lerpf(0.5, 1.6, d)


## Brouillard, pluie ou neige de l'ambiance, avec un fondu d'une région à l'autre.
func _update_weather(delta: float) -> void:
	var th := builder.theme_at(car.s)
	var k := 1.0 - exp(-0.7 * delta) if delta > 0.0 else 1.0
	_fog_scale = lerpf(_fog_scale, th.get("fog", 1.0), k)
	_fog_tint = _fog_tint.lerp(th.get("fog_tint", NIGHT_FOG), k)
	var tunnel := builder.in_tunnel(car.s)
	var weather: float = th.get("rain", 1.0)
	_rain = lerpf(_rain, 0.0 if tunnel else absf(weather), 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0)
	RenderingServer.global_shader_parameter_set("ps1_fog_start", FOG_START / _fog_scale)
	RenderingServer.global_shader_parameter_set("ps1_fog_end", FOG_END / _fog_scale)
	rain.set_weather(_rain, weather < 0.0)
	# Gouttes sur l'écran : seulement sous la pluie.
	_post_material.set_shader_parameter("rain", _rain if weather > 0.0 else 0.0)


## Directions de la prochaine bifurcation, affichées à son approche.
func _update_fork_prompt() -> void:
	var k := game.choices.size()
	if game.state == GameRun.State.RUNNING and k < RouteMap.STAGES.size() - 1:
		var f := RouteMap.fork_s(k)
		if car.s > f - FORK_PROMPT and car.s < f + RouteMap.DIVIDER_START:
			var names := Scenery.fork_names(k, game.choices)
			hud.fork_prompt(names[0], names[1])
			if not _fork_said:
				_fork_said = true
				_say(Scenario.RADIO["fork"], f + RouteMap.DIVIDER_START)
			return
	hud.fork_prompt("", "")


## Événements étranges franchis, tunnel trop long, chrono bas.
func _update_events() -> void:
	if game.state != GameRun.State.RUNNING:
		return
	for name in _events.crossed(_prev_s, car.s):
		game.set_flag(name)
		match name:
			"radio_live":
				var region: String = builder.theme_at(car.s)["name"]
				_say(Scenario.RADIO["radio_live"] % [int(car.speed_kmh()), region.to_lower()])
			"fantome":
				traffic.spawn_ghost(car)
				_say(Scenario.RADIO["fantome"])
			_:
				_say(Scenario.RADIO[name])
	# Le tunnel trop long : le premier tunnel de la dernière étape suspend le chrono.
	var last := RouteMap.STAGES.size() - 1
	var first_tunnel := RouteMap.region_start(last) + RoadBuilder.TUNNEL_OFFSET
	var frozen: bool = RouteMap.stage_at(car.s) == last and builder.theme_at(car.s).get("tunnels", 0.0) > 0.0 \
			and car.s >= first_tunnel and builder.in_tunnel(car.s) \
			and car.s < first_tunnel + RoadBuilder.TUNNEL_PERIOD
	if frozen and not game.flags.has("tunnel"):
		game.set_flag("tunnel")
		_say(Scenario.RADIO["tunnel"])
	game.clock_frozen = frozen
	if game.time_left < 12.0 and not _low_time_said:
		_low_time_said = true
		_say(Scenario.RADIO["low_time"])


func _on_station(index: int, added: float) -> void:
	hud.popup("+%d" % int(added), Hud.AMBER, 32, 140.0)
	hud.popup("STATION %d" % (index + 1), Hud.WHITE, 8, 188.0)


func _on_fork(_index: int, _side: int) -> void:
	_sync_choices()
	_fork_said = false


func _on_region(_stage: int, theme_id: String) -> void:
	hud.title_card(RouteMap.THEMES[theme_id]["name"])
	_say(Scenario.RADIO[theme_id])


func _on_arrived(bonus: int) -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	var first_time := not _endings_seen.has(game.ending)
	_endings_seen[game.ending] = true
	_write_save()
	hud.show_overlay(RouteMap.ENDINGS[game.ending],
			"%s\n\n%sSCORE %s\nBONUS TEMPS %s\nÉVÉNEMENTS %d/6\n%s" % [
				Scenario.ending_text(game.ending, game.flags),
				"NOUVELLE FIN ! " if first_time else "", Hud._group(int(game.score)), Hud._group(bonus),
				game.flags.size(), "NOUVEAU RECORD !" if record else "RECORD %s" % Hud._group(_best)],
			"TOUCHE POUR REJOUER")


func _on_time_up() -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	hud.show_overlay("LA NUIT\nGAGNE",
			"\nÉTAPE %d SUR %d\n%.1f KM\n\nSCORE %s\n\n%s" % [
				game.segment() + 1, RunConfig.SEGMENT_COUNT, car.s / 1000.0, Hud._group(int(game.score)),
				"NOUVEAU RECORD !" if record else "RECORD %s" % Hud._group(_best)],
			"TOUCHE POUR REJOUER")


## Sauvegarde : record, parties jouées, fins découvertes.
func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_best = int(cfg.get_value("scores", "best", 0))
	_runs = int(cfg.get_value("progress", "runs", 0))
	for e in cfg.get_value("progress", "endings", []):
		_endings_seen[int(e)] = true


func _write_save() -> void:
	if _args.has("autopilot"):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "best", _best)
	cfg.set_value("progress", "runs", _runs)
	cfg.set_value("progress", "endings", _endings_seen.keys())
	cfg.save(SAVE_PATH)


## Enregistre le score s'il bat le record ; renvoie vrai si c'est un record.
func _save_best(score: int) -> bool:
	if score <= _best or _args.has("autopilot"):
		return false
	_best = score
	_write_save()
	return true


## Tient les tronçons autour de la voiture. `blocking` : tout construire tout
## de suite (au démarrage) ; sinon un tronçon à la fois, en tâche de fond, le
## plus proche d'abord.
func _update_chunks(blocking := false) -> void:
	var current := int(floor(car.s / RoadBuilder.CHUNK_LENGTH))
	var wanted := {}
	var missing := -1
	# Au-delà d'une bifurcation pas encore prise, la route n'existe pas encore.
	var limit := track.limit_s()
	for i in range(maxi(0, current - CHUNKS_BEHIND), current + CHUNKS_AHEAD + 1):
		wanted[i] = true
		if (i + 1) * RoadBuilder.CHUNK_LENGTH + RoadBuilder.LAMP_SPACING + 2.0 > limit:
			break
		if not _chunks.has(i) and missing == -1:
			missing = i
		if blocking and not _chunks.has(i):
			_worker_builder.choices = game.choices.duplicate()
			_worker_builder.track.choices.assign(game.choices)
			_add_chunk(i, _worker_builder.build_chunk(i))
	if not blocking and missing != -1 and _building == -1:
		_building = missing
		_build_task_id = WorkerThreadPool.add_task(_build_in_background.bind(missing, game.choices.duplicate()))
	for i in _chunks.keys():
		if not wanted.has(i):
			_chunks[i].queue_free()
			_chunks.erase(i)


func _build_in_background(index: int, choices: Array) -> void:
	_worker_builder.choices = choices
	_worker_builder.track.choices.assign(choices)
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

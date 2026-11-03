class_name Main
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
##   --fps              affiche les images par seconde (essais sur iPhone)
##   --sliced           construit la route par étapes, comme la version web
##   --menu=garage      ouvre un écran du titre (garage, carnet, reglages)
##   --storm_at=SEC     premier éclair à cet instant (captures)
## Dans la version web, les mêmes options passent par l'adresse : ?fps&seed=3
##   --capture=PATH     enregistre une image PNG puis quitte
##   --capture_at=SEC   instant de la capture (défaut 6)

const CHUNKS_BEHIND := 1
const CHUNKS_AHEAD := 4
const CAMERA_BACK := 8.0
const CAMERA_HEIGHT := 4.2
const START_S := 30.0

const NIGHT_FOG := Color(0.13, 0.04, 0.2)
const DAWN_FOG := Color(0.55, 0.22, 0.4)
const NIGHT_HORIZON := Color(0.42, 0.07, 0.38)
const DAWN_HORIZON := Color(0.95, 0.38, 0.45)
const NIGHT_ZENITH := Color(0.03, 0.01, 0.09)
const DAWN_ZENITH := Color(0.2, 0.1, 0.38)
const FOG_START := 40.0
const FOG_END := 260.0
## Avant une bifurcation, ses directions s'affichent sur cette distance (m).
const FORK_PROMPT := 1200.0

## Rejouer depuis l'écran de fin saute l'écran de titre.
static var quick_restart := false
## Nuit du jour : même route et même trafic pour tout le monde ce jour-là.
static var daily_mode := false
## Écran à rouvrir après un rechargement (changement de langue).
static var reopen_menu := ""


## Date du jour, « AAAA-MM-JJ ».
static func today() -> String:
	return Time.get_date_string_from_system()


## Graine de la nuit du jour, tirée de la date.
static func daily_seed() -> int:
	return absi(hash("route-de-nuit-" + today())) % 1000000 + 1

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
## Version web sans threads : construction par étapes (voir _build_sliced).
var _sliced := OS.has_feature("web") and not OS.has_feature("threads")
var _job := {}
var _worst_chunk_usec := 0
const SLICE_BUDGET_USEC := 6000
var _args := {}
var _time := 0.0
var _shake := 0.0
var _cam_x := 0.0
var _end_time := 0.0
## Scène de fin : voir EndingScene. _anchor est le bout de la route (INF en course).
var _ending := {}
var _anchor := INF
var _ending_overlay: Array = []
var _overlay_at := INF
var _ambient_base := Color()
var _sky_material: ShaderMaterial
var _post_material: ShaderMaterial
var _events: EventDirector
var _path := [0, 0, 0, 0]
## Tout ce qui survit d'une partie à l'autre.
var save: SaveData
var menus: Menus
## File de Radio Nuit : [texte, s au-delà duquel la réplique n'a plus de sens].
var _radio_queue := []
var _low_time_said := false
var _fork_said := false
var _prev_s := 0.0
## Fantôme du record (voir Ghost) : celui qu'on affronte et celui qu'on enregistre.
var ghost: Ghost
var ghost_view: GhostView
var _ghost_rec: Ghost
var _ghost_lost := false
var _run_time := 0.0
var _seed := 1
## Préchauffage des effets rares (voir _warm_up_step), en images restantes.
var _warm_frames := 4
var _share: ShareCard
## Brouillard et météo courants, qui glissent vers ceux de l'ambiance.
var _fog_scale := 1.0
var _fog_tint := NIGHT_FOG
var _rain := 1.0

@onready var car_view: CarView = $Car
@onready var traffic_view: TrafficView = $Traffic
var police: Police
var police_view: PoliceView
var _patrol_said := {}
@onready var camera: Camera3D = $Camera
@onready var input: ThumbInput = $ThumbInput
@onready var hud: Hud = $Hud
@onready var environment: Environment = $WorldEnvironment.environment
@onready var rain: CPUParticles3D = $Camera/Rain
@onready var reflection: Reflection = $Reflection
var car_env: CarEnv

var _lights: LightField
var audio: AudioDirector
var _fps_label: Label
var _tutorial_done := false
var _tutorial_step := 0
var _tutorial_fork := false
var _turbo_explained := false
var _turbo_fov := 0.0
## Effets de choc et micro-ralentis (temps réel, en ms).
var _hit := 0.0
var _slowmo_until := 0
var _prev_speed := 0.0
## Orage : délai avant le prochain éclair, éclat en cours, tonnerre attendu.
var _storm_wait := 14.0
var _flash := 0.0
var _flash_time := -1.0
var _thunder_in := -1.0


## La langue doit être choisie avant que l'interface (enfant de Main) ne se
## construise : _init passe avant tous les _ready.
func _init() -> void:
	_args = _parse_args()
	Lang.apply(str(_args.get("lang", SaveData.load_or_new().language)))


## Options de lancement : ligne de commande, ou adresse sur la version web
## (?autopilot&path=0110&lang=en).
static func _parse_args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
		if query != "":
			raw = PackedStringArray(query.split("&"))
	for a in raw:
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func _ready() -> void:
	if _args.has("sliced"):
		_sliced = true
	if _args.has("storm_at"):
		_storm_wait = float(_args["storm_at"])
	var seed := daily_seed() if daily_mode else int(_args.get("seed", "1"))
	_seed = seed
	if _args.has("path"):
		_path.clear()
		for c in str(_args["path"]):
			_path.append(int(c))
	save = SaveData.load_or_new()
	_tutorial_done = save.runs > 0
	_events = EventDirector.new(seed, save.runs)
	track = Track.new(seed, true)
	builder = RoadBuilder.new(track, seed)
	builder.stations = RunConfig.stations()
	builder.arrival_s = RunConfig.arrival_s()
	builder.events = _events
	_worker_builder = RoadBuilder.new(Track.new(seed, true), seed)
	_worker_builder.stations = builder.stations
	_worker_builder.arrival_s = builder.arrival_s
	_worker_builder.events = EventDirector.new(seed, save.runs)
	# Ressources partagées créées ici, avant toute tâche de fond.
	Hud.arcade_font()
	Halo.material()
	traffic = Traffic.new(seed)
	police = Police.new(seed)
	police_view = PoliceView.new()
	add_child(police_view)
	ghost_view = GhostView.new()
	add_child(ghost_view)
	_ghost_rec = Ghost.new(seed)
	if save.ghost_on and (not _args.has("autopilot") or _args.has("ghost")):
		ghost = Ghost.load_for(seed)
	_sky_material = environment.sky.sky_material
	_ambient_base = ProjectSettings.get_setting("shader_globals/sky_ambient")["value"]
	_post_material = $Post/Screen.material
	if _args.has("nopost"):
		$Post.visible = false
	_lights = LightField.new()
	reflection.source = camera
	car_env = CarEnv.new()
	add_child(car_env)
	# Navigateur : reflet plus petit, Safari sur iPhone est moins rapide que l'app.
	menus = Menus.new()
	menus.save = save
	add_child(menus)
	menus.settings_changed.connect(_apply_settings)
	menus.language_changed.connect(func() -> void:
		_write_save()
		Lang.apply(save.language)
		reopen_menu = "reglages"
		get_tree().reload_current_scene())
	menus.color_chosen.connect(func(i: int) -> void:
		car_view.set_paint(i)
		_write_save())
	menus.closed.connect(func() -> void: _write_save())
	hud.journal_pressed.connect(menus.open_journal)
	hud.garage_pressed.connect(menus.open_garage)
	menus.garage_changed.connect(func() -> void:
		_apply_garage()
		_write_save())
	hud.share_pressed.connect(func() -> void:
		if _share != null:
			var how := _share.share()
			if not OS.has_feature("web"):
				hud.popup(how.get_file(), Hud.WHITE, 8, 120.0))
	hud.title_pressed.connect(func() -> void:
		get_tree().paused = false
		daily_mode = false
		quick_restart = false
		get_tree().reload_current_scene())
	hud.settings_pressed.connect(menus.open_settings)
	hud.daily_pressed.connect(func() -> void:
		daily_mode = true
		quick_restart = true
		get_tree().reload_current_scene())

	if _args.has("fps"):
		_fps_label = Label.new()
		_fps_label.position = Vector2(8, 452)
		_fps_label.add_theme_font_size_override("font_size", 10)
		hud.add_child(_fps_label)
	audio = AudioDirector.new()
	add_child(audio)
	# Diagnostic (?sanspluie) : pluie, vent et pneus muets, pour savoir si le
	# « grésillement » entendu est le bruit de la pluie.
	if _args.has("sanspluie"):
		audio.mute_weather = true
	# Diagnostic (?tone) : une note pure seule, pour tester la sortie audio.
	if _args.has("tone"):
		for bus in ["Bruitages", "Musique"]:
			AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 44100
		var data := PackedByteArray()
		data.resize(44100 * 2)
		for i in 44100:
			data.encode_s16(i * 2, int(sin(TAU * 441.0 * i / 44100.0) * 9000.0))
		wav.data = data
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = 44100
		var tone := AudioStreamPlayer.new()
		tone.stream = wav
		add_child(tone)
		tone.play()
	_apply_garage()
	_apply_settings()
	input.double_tapped.connect(func() -> void: hud.popup(audio.next_station(), Hud.PINK, 12, 250.0))
	hud.pause_pressed.connect(_set_paused.bind(true))
	input.swiped_up.connect(_try_turbo)
	game.turbo_ready.connect(func() -> void:
		audio.play("blip", -6.0, 1.4)
		if not _turbo_explained:
			_turbo_explained = true
			hud.hint("TURBO PRÊT : GLISSE LE POUCE VERS LE HAUT"))
	hud.resume_requested.connect(_set_paused.bind(false))
	game.near_miss.connect(func(_p: int) -> void:
		audio.play("whoosh", -4.0, randf_range(0.9, 1.15)))
	game.station_reached.connect(func(_i: int, _t: float) -> void: audio.play("chime", -6.0))

	game.station_reached.connect(_on_station)
	game.near_miss.connect(func(pts: int) -> void: hud.popup(Lang.t("FRÔLÉ +%d") % pts, Hud.WHITE, 8, 210.0))
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
				Lang.t("Atteins l'aube avant la fin du chrono.\nRECORD %s   |   FINS %d/%d") % [
					Hud._group(save.best), save.endings.size(), RouteMap.ENDINGS.size()],
				"POSE TON POUCE", true)
	# Captures : ouvrir directement un écran du titre (--menu=garage, carnet, reglages).
	match str(_args.get("menu", reopen_menu)):
		"garage":
			menus.open_garage()
		"carnet":
			menus.open_journal()
		"reglages":
			menus.open_settings()
	reopen_menu = ""
	if daily_mode and not _args.has("autopilot"):
		hud.popup(Lang.t("NUIT DU %s") % today().substr(8, 2) + "/" + today().substr(5, 2), Hud.LOU_BLUE, 12, 260.0)
	_update_chunks(true)
	_place_car_and_camera(0.0)


func _exit_tree() -> void:
	# Le ralenti est un réglage du moteur : il survivrait au rechargement de la scène.
	Engine.time_scale = 1.0
	if _building != -1:
		WorkerThreadPool.wait_for_task_completion(_build_task_id)
		_building = -1
	if _pending != null:
		_pending.free()
		_pending = null


## Choc : étincelles, flash, micro-ralenti.
func _impact(side: float, strength: float) -> void:
	car_view.sparks(side)
	_hit = maxf(_hit, strength)
	# Plus de micro-ralenti aux chocs : ressenti comme un freeze (retour de test).


## Micro-ralenti : le temps du jeu ralentit pendant `ms` millisecondes réelles.
func _slowmo(scale: float, ms: int) -> void:
	if _args.has("autopilot") and _args.has("capture"):
		return
	Engine.time_scale = scale
	_slowmo_until = Time.get_ticks_msec() + ms


func _try_turbo() -> void:
	if game.fire_turbo():
		audio.play("whoosh", 0.0, 0.6)
		hud.popup("TURBO", Hud.PINK, 18, 200.0)
		_shake = 0.2


## Pause : bouton, ou l'app passe en arrière-plan (appel, notification...).
func _set_paused(on: bool) -> void:
	if on and game.state != GameRun.State.RUNNING:
		return
	get_tree().paused = on
	hud.show_pause(on)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT] \
			and not _args.has("autopilot") and not _args.has("capture") and is_inside_tree():
		_set_paused(true)


## Conseils de la toute première partie.
func _update_tutorial() -> void:
	if _tutorial_done or game.state != GameRun.State.RUNNING or _args.has("autopilot"):
		return
	var steps := [[1.5, "GLISSE LE POUCE POUR TOURNER"], [7.0, "LÈVE LE POUCE POUR FREINER"],
			[13.0, "DOUBLE TAP : CHANGER DE RADIO"], [20.0, "CHAQUE STATION RAJOUTE DU TEMPS"]]
	while _tutorial_step < steps.size() and game.elapsed >= steps[_tutorial_step][0]:
		hud.hint(steps[_tutorial_step][1])
		_tutorial_step += 1
	if not _tutorial_fork and car.s > RouteMap.fork_s(0) - 900.0:
		_tutorial_fork = true
		hud.hint("AU TERRE-PLEIN, CHOISIS TON CÔTÉ")


func _first_lamp_after(s: float) -> float:
	for lamp in builder.lamps_between(s, s + 400.0):
		if lamp[1] != 0:
			return lamp[0] + 2.0
	return s


## Améliorations et options du garage, sur la voiture et dans les règles.
func _apply_garage() -> void:
	Garage.apply(save, car, game)
	var options := {"aileron": save.owned.has("aileron") and save.spoiler_on, "jantes": save.owned.has("jantes")}
	if save.owned.has("neon") and save.neon_on:
		options["neon"] = Garage.NEON_COLORS[save.neon_color]
	car_view.set_options(options)
	car_view.set_paint(save.car_color)


## Volumes, sensibilité du pouce, qualité graphique (réglages sauvegardés).
func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Musique"), linear_to_db(maxf(save.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Bruitages"), linear_to_db(maxf(save.sfx_volume, 0.0001)))
	input.steer_range = 0.16 / save.sensitivity
	# Sobre : pas de reflet ; normale : reflet réduit ; haute : reflet à mi-résolution
	# (réduit quand même dans le navigateur).
	var on := save.quality > 0
	reflection.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	RenderingServer.global_shader_parameter_set("reflection_on", 1.0 if on else 0.0)
	# Netteté : l'interface s'affiche à la résolution de l'écran (nette), la 3D
	# à une résolution réglable, agrandie ensuite (le vrai coût est là).
	car_env.set_quality(save.quality)
	var pixel := save.pixel_art or _args.has("pixel")
	_post_material.set_shader_parameter("pixel_art", 1.0 if pixel else 0.0)
	var s3d := render_scale()
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = s3d
	reflection.scale = (0.5 if save.quality == 2 and not OS.has_feature("web") else 0.35) * s3d


## Hauteur visée de l'image 3D (pixels) selon la qualité ; sur ordinateur et en
## capture, pleine résolution. --render_h=N force une hauteur (essais).
const RENDER_HEIGHT := [720, 860, 1000]


func render_scale() -> float:
	var h := float(DisplayServer.window_get_size().y)
	var target := float(_args.get("render_h", "0"))
	if target <= 0.0:
		if not OS.has_feature("web"):
			return 1.0
		target = RENDER_HEIGHT[save.quality]
		# Pixel art : l'image finale n'a que 240 lignes, inutile de calculer plus fin.
		if save.pixel_art:
			target = 540.0
	return clampf(target / maxf(h, 1.0), 0.25, 1.0)


func _start() -> void:
	if menus.is_open():
		return
	hud.hide_overlay()
	game.start(car.s)
	# Captures : poursuite lancée tout de suite, police juste derrière (--police_demo).
	if _args.has("police_demo"):
		police.patrols[RouteMap.stage_at(car.s)] = car.s + 1.0
		car.speed = 70.0
	if not _args.has("autopilot"):
		save.runs += 1
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
	_radio_queue.append([text, until_s, Scenario.STATION])


func _physics_process(delta: float) -> void:
	if game.state == GameRun.State.WAITING:
		if input.throttle > 0.0:
			_start()
		else:
			return
	var throttle := input.throttle
	var steer := input.steer
	if _args.has("autopilot"):
		var cmd := Autopilot.drive(car, track, traffic, _path, Autopilot.Driver.GOOD, police)
		throttle = cmd[0]
		steer = cmd[1]
		if cmd[2]:
			_try_turbo()
	# Turbo et aspiration.
	var drafting := traffic.drafting(car)
	if drafting and game.state == GameRun.State.RUNNING:
		game.on_draft(delta)
	car.boost = (RunConfig.TURBO_SPEED if game.is_boosting() else 1.0) * (RunConfig.DRAFT_SPEED if drafting else 1.0)
	car.accel_boost = RunConfig.TURBO_ACCEL if game.is_boosting() else 1.0
	# Contrôle de police : arrêté le temps du contrôle.
	if game.state != GameRun.State.RUNNING or police.hold > 0.0:
		throttle = 0.0

	var prev_speed := car.speed
	car.step(track, throttle, steer, delta)
	if _anchor < INF:
		EndingScene.brake(car, _anchor, delta, prev_speed)
	if car.hit_rail:
		_shake = 0.5 if car.hit_divider else 0.35
		game.on_crash(car.s)
		_impact(0.0 if car.hit_divider else signf(car.x), 0.7 if car.hit_divider else 0.4)
		audio.play("thud" if car.hit_divider else "crash", 0.0 if car.hit_divider else -6.0)
		Input.vibrate_handheld(150 if car.hit_divider else 60)
	var th := builder.theme_at(car.s)
	traffic.density = RunConfig.TRAFFIC_DENSITY[game.segment()] * th.get("traffic", 1.0) if _anchor == INF else 0.0
	traffic.truck_ratio = th.get("trucks", 0.2)
	for e in traffic.update(car, delta):
		if e.type == "crash":
			_shake = 0.5
			game.on_crash(car.s)
			_impact(0.0, 0.8)
			audio.play("crash", -2.0)
			Input.vibrate_handheld(90)
		else:
			game.on_near_miss()
	if game.state == GameRun.State.RUNNING:
		for e in police.update(car, traffic, delta, builder.water_side(car.s)):
			police.apply(e, game)
			_on_police(e)
	_update_events()
	if game.state == GameRun.State.RUNNING:
		_run_time += delta
		_ghost_rec.record(_run_time, car.s, car.x)
	game.update(car.s, car.x, absf(car.slip) > 0.12 and car.speed > 45.0, delta)
	_prev_s = car.s

	track.ensure(car.s + CHUNKS_AHEAD * RoadBuilder.CHUNK_LENGTH + 200.0)
	track.trim(car.s - (CHUNKS_BEHIND + 1) * RoadBuilder.CHUNK_LENGTH)

	# Rejouer depuis l'écran de fin.
	if game.state == GameRun.State.ARRIVED and _overlay_at < INF and input.throttle > 0.0 \
			and _time - _end_time > 1.0 and _time < _overlay_at:
		# Toucher pendant la scène : le texte arrive tout de suite.
		_overlay_at = _time
	if game.state in [GameRun.State.ARRIVED, GameRun.State.TIME_UP] and _time - maxf(_end_time, _overlay_at if _overlay_at < INF else 0.0) > 2.0 \
			and _ending_overlay.is_empty() and input.throttle > 0.0 and not _args.has("autopilot"):
		quick_restart = true
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	_time += delta
	var t_chunks := Time.get_ticks_usec()
	_update_chunks()
	_worst_chunk_usec = maxi(_worst_chunk_usec, Time.get_ticks_usec() - t_chunks)
	_place_car_and_camera(delta)
	traffic_view.sync(traffic, track, delta)
	police_view.sync(police, car, track, builder.water_side, delta)
	_update_ghost()
	_warm_up_step()
	var ram_side := 99
	if police.state == Police.State.RAM:
		var dx := police.ram_x - car.x
		ram_side = -1 if dx < -2.0 else (1 if dx > 2.0 else 0)
	hud.set_pursuit(police.active() or police.hold > 0.0, police.strikes, police.gap(car), ram_side, delta)
	audio.update_siren(police.active() or police.hold > 0.0, police.gap(car), police.speed - car.speed, delta)
	# Plus elle est près, plus les bords de l'écran clignotent rouge et bleu.
	var near := clampf(1.0 - absf(police.gap(car)) / 80.0, 0.0, 1.0) if police.active() or police.hold > 0.0 else 0.0
	var sc: Color = PoliceView.RED if PoliceView.red_on(_time) else PoliceView.BLUE
	_post_material.set_shader_parameter("siren", Color(sc.r, sc.g, sc.b, near * near))
	car_view.set_lighting(builder.lamp_light(car.s, car.x), input.throttle == 0.0 and not _args.has("autopilot"), delta)
	hud.set_values(game.time_left, game.score, game.segment(), game.multiplier(), car.speed_kmh(), game.progress())
	hud.set_turbo(game.turbo, game.turbo_left / game.turbo_duration)
	_update_dawn()
	_update_ending(delta)
	_sky_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / maxf(1.0, DisplayServer.window_get_size().y * get_viewport().scaling_3d_scale))
	_update_weather(delta)
	_update_storm(delta)
	_update_lighting(delta)
	_update_tutorial()
	_update_feel(delta)
	if _fps_label:
		_fps_label.text = "%d i/s" % Engine.get_frames_per_second()
	audio.update(car.speed, input.throttle if not _args.has("autopilot") else 1.0, _rain if builder.theme_at(car.s).get("rain", 1.0) > 0.0 else 0.0,
			builder.in_tunnel(car.s), delta)
	_update_fork_prompt()
	while not _radio_queue.is_empty() and not hud.radio_busy():
		var line: Array = _radio_queue.pop_front()
		if car.s < line[1]:
			hud.radio(line[0], line[2])
			audio.play("static", -16.0)
	var cur := int(floor(car.s / RoadBuilder.CHUNK_LENGTH))
	for i in range(cur, cur + 3):
		if not _chunks.has(i):
			_late_frames += 1
			break
	# Journal de la poursuite (captures : trouver le bon moment).
	if _args.has("police_log") and police.active() and Engine.get_process_frames() % 15 == 0:
		print("police t %.2f %s écart %.1f x %.1f/%.1f" % [_time, Police.State.keys()[police.state], police.gap(car), police.x, car.x])
	if _args.has("capture") and _time >= float(_args.get("capture_at", "6")):
		print("état %d  s %.1f  ancre %.1f  fin %d  t %.1f/%.1f" % [game.state, car.s, _anchor, game.ending, _time, _end_time])
		print("tronçons en retard : %d images ; pire construction dans une image : %.1f ms" % [
				_late_frames, _worst_chunk_usec / 1000.0])
		get_viewport().get_texture().get_image().save_png(_args["capture"])
		get_tree().quit()


## Durée de la scène de fin avant que le texte n'apparaisse (s).
const ENDING_SCENE_TIME := 7.0


## Arrivée : le bout de la route, le décor de la destination, le soleil en face.
func _begin_ending_scene() -> void:
	_anchor = EndingScene.anchor_s(RunConfig.arrival_s())
	track.ensure(_anchor + 400.0)
	_ending = EndingScene.build(game.ending, builder, track, _anchor)
	add_child(_ending["node"])
	var fwd: Vector3 = -(_ending["frame"] as Transform3D).basis.z
	_sky_material.set_shader_parameter("sun_azimuth", atan2(fwd.x, -fwd.z) + float(_ending["sun"]))
	_sky_material.set_shader_parameter("city_amount", 1.0 if game.ending == 1 else 0.0)
	traffic.vehicles.clear()
	traffic.ghost = null
	camera.far = 4000.0
	hud.cinema(true)
	audio.play_dawn()


## Après l'arrivée : la voiture s'arrête avant le bout de la route, le monde
## au-delà disparaît, le soleil se lève, la lumière se réchauffe.
func _update_ending(delta: float) -> void:
	if _anchor == INF:
		return
	var u := _time - _end_time
	for i in _chunks:
		_chunks[i].visible = i * RoadBuilder.CHUNK_LENGTH < _anchor
	_sky_material.set_shader_parameter("sun", lerpf(-0.12, 0.07, smoothstep(0.0, 12.0, u)))
	var warm := smoothstep(0.0, 6.0, u)
	_ambient_base = (ProjectSettings.get_setting("shader_globals/sky_ambient")["value"] as Color).lerp(
			Color(0.62, 0.5, 0.5), warm)
	_sky_material.set_shader_parameter("dawn", 1.0)
	_sky_material.set_shader_parameter("horizon", DAWN_HORIZON.lerp(Color(0.85, 0.55, 0.45), warm))
	_sky_material.set_shader_parameter("zenith", DAWN_ZENITH.lerp(Color(0.3, 0.42, 0.66), warm))
	RenderingServer.global_shader_parameter_set("fog_color", DAWN_FOG.lerp(Color(0.8, 0.56, 0.5), warm))
	if _time >= _overlay_at and not _ending_overlay.is_empty():
		var title: String = Lang.t(RouteMap.ENDINGS[game.ending])
		_make_share_card(title, Lang.t("J'AI VU L'AUBE"), PoliceView.BLUE.lerp(Hud.AMBER, 0.85),
				Lang.t("J'ai vu l'aube sur %s dans Route de Nuit : %s points.") % [title.to_lower(), Lang.group(int(game.score))])
		hud.show_overlay(_ending_overlay[0], _ending_overlay[1], _ending_overlay[2])
		_ending_overlay = []


## Plan final [œil, visée] en coordonnées du monde : œil près de la voiture,
## qui monte et recule doucement ; visée sur le décor de la destination.
func _ending_shot() -> Array:
	var f: Transform3D = _ending["frame"]
	var drift := smoothstep(0.0, 14.0, _time - _end_time)
	var local_car := f.affine_inverse() * car_view.global_position
	var eye_off: Vector3 = _ending["eye"]
	var eye := f * (local_car + eye_off + Vector3(0, drift * 1.5, drift * 3.0))
	return [eye, f * (_ending["focus"] as Vector3)]


## Le ciel s'éclaircit pendant toute la partie : c'est aussi la jauge d'avancement.
func _update_dawn() -> void:
	if _anchor < INF:
		return
	var p := clampf(car.s / RunConfig.arrival_s(), 0.0, 1.0)
	var d := smoothstep(0.25, 1.0, p)
	_sky_material.set_shader_parameter("dawn", d)
	_sky_material.set_shader_parameter("horizon", NIGHT_HORIZON.lerp(DAWN_HORIZON, d))
	_sky_material.set_shader_parameter("zenith", NIGHT_ZENITH.lerp(DAWN_ZENITH, d * d))
	RenderingServer.global_shader_parameter_set("fog_color", _fog_tint.lerp(DAWN_FOG, d * 0.8))
	environment.ambient_light_energy = lerpf(0.5, 1.6, d)


## Sensations : caisse vivante, gerbes d'eau, flash de choc, fin des ralentis.
func _update_feel(delta: float) -> void:
	if _slowmo_until > 0 and Time.get_ticks_msec() > _slowmo_until:
		Engine.time_scale = 1.0
		_slowmo_until = 0
	if delta <= 0.0:
		return
	var accel := (car.speed - _prev_speed) / delta
	_prev_speed = car.speed
	car_view.animate(accel, car.lateral, car.speed, delta)
	var th := builder.theme_at(car.s)
	var wet := 0.0 if builder.in_tunnel(car.s) or th.get("rain", 1.0) < 0.0 else maxf(0.35, th.get("rain", 1.0))
	car_view.set_spray(clampf((car.speed - 8.0) / 60.0, 0.0, 1.0) * wet, builder.lamp_light(car.s, car.x))
	_hit = move_toward(_hit, 0.0, delta * 3.0)
	_post_material.set_shader_parameter("hit", _hit)


## Orage, sous la pluie battante : un éclair de temps en temps (double éclat
## qui éclaire toute la scène), puis le tonnerre une à deux secondes après.
func _update_storm(delta: float) -> void:
	var th := builder.theme_at(car.s)
	var stormy: bool = th.get("rain", 1.0) >= 1.0 and not builder.in_tunnel(car.s) \
			and game.state == GameRun.State.RUNNING
	if stormy:
		_storm_wait -= delta
		if _storm_wait <= 0.0:
			_storm_wait = randf_range(12.0, 30.0)
			_flash_time = 0.0
			_thunder_in = randf_range(0.6, 2.0)
	if _flash_time >= 0.0:
		_flash_time += delta
		# Deux éclats rapprochés, puis plus rien.
		_flash = exp(-_flash_time * 14.0) + 0.7 * exp(-absf(_flash_time - 0.16) * 18.0)
		if _flash_time > 0.6:
			_flash_time = -1.0
			_flash = 0.0
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			audio.play("thunder", randf_range(-6.0, 0.0), randf_range(0.85, 1.1))
	_sky_material.set_shader_parameter("flash", _flash)
	RenderingServer.global_shader_parameter_set("sky_ambient", _ambient_base + Color(1.3, 1.4, 1.8) * _flash)


## Lumières proches, phares, reflet de la route, effets de vitesse.
func _update_lighting(delta: float) -> void:
	var cam := camera.global_position
	var sources := builder.light_sources(car.s - 60.0, car.s + 300.0)
	# Le néon sous caisse éclaire la chaussée (et se reflète dedans).
	var neon := car_view.neon_color()
	if neon != Color.BLACK:
		# Discret : plus fort, il saturait en tache blanche derrière la voiture.
		sources.append([car_view.global_position + Vector3.UP * 0.25, neon, 5.0, 1.1])
	sources.append_array(_ending.get("lights", []))
	sources.append_array(police_view.light_sources())
	_lights.update(sources, cam, delta)
	var t := track.transform_at(car.s, car.x)
	var fwd := -car_view.global_transform.basis.z
	RenderingServer.global_shader_parameter_set("head_pos", car_view.global_position + fwd * 2.1 + t.basis.y * 0.7)
	RenderingServer.global_shader_parameter_set("head_dir", (fwd - t.basis.y * 0.06).normalized())
	reflection.follow(track.point_at(car.s), t.basis.y)
	car_env.follow(car_view.global_transform)
	var playing := game.state == GameRun.State.RUNNING
	_post_material.set_shader_parameter("speed", car.speed / CarPhysics.TOP_SPEED if playing else 0.0)


## Brouillard, pluie ou neige de l'ambiance, avec un fondu d'une région à l'autre.
func _update_weather(delta: float) -> void:
	var th := builder.theme_at(car.s)
	var k := 1.0 - exp(-0.7 * delta) if delta > 0.0 else 1.0
	_fog_scale = lerpf(_fog_scale, th.get("fog", 1.0), k)
	_fog_tint = _fog_tint.lerp(th.get("fog_tint", NIGHT_FOG), k)
	var tunnel := builder.in_tunnel(car.s)
	var weather: float = th.get("rain", 1.0)
	_rain = lerpf(_rain, 0.0 if tunnel or _anchor < INF else absf(weather), 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0)
	# Scène de fin : l'air se lave, on voit jusqu'à l'horizon.
	var clear := smoothstep(0.0, 4.0, _time - _end_time) if _anchor < INF else 0.0
	RenderingServer.global_shader_parameter_set("fog_start", lerpf(FOG_START / _fog_scale, 160.0, clear))
	RenderingServer.global_shader_parameter_set("fog_end", lerpf(FOG_END / _fog_scale, 1800.0, clear))
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
	# Marceau prévient : une patrouille plus loin (la première fois en détail).
	var k := RouteMap.stage_at(car.s)
	if police.patrols.has(k) and not _patrol_said.has(k) and not police.woken(k) \
			and car.s > police.patrols[k] - 900.0 and not police.active():
		_patrol_said[k] = true
		_say(Scenario.RADIO["patrouille" if _patrol_said.size() == 1 else "patrouille2"], police.patrols[k])
	for name in _events.crossed(_prev_s, car.s):
		game.set_flag(name)
		match name:
			"radio_live":
				var region: String = builder.theme_at(car.s)["name"]
				_say(Lang.t(Scenario.RADIO["radio_live"]) % [int(car.speed_kmh()), Lang.t(region).to_lower()])
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


## Poursuite : chaque événement se voit, s'entend et se commente.
func _on_police(e: Dictionary) -> void:
	match e.type:
		"start":
			hud.popup("POURSUITE !", Hud.RED, 18, 196.0)
			_say(Scenario.RADIO["poursuite"])
			Input.vibrate_handheld(80)
			if save.runs <= 3 or not save.events_seen.has("poursuite"):
				hud.hint("QUAND ELLE CHARGE, CHANGE DE VOIE")
		"contact":
			_shake = 0.5
			_impact(signf(car.x - police.x), 0.7)
			audio.play("crash", -3.0)
			Input.vibrate_handheld(120)
			if e.strikes < Police.STRIKES_TO_BUST:
				hud.popup(Lang.t("TOUCHÉ %d/%d") % [e.strikes, Police.STRIKES_TO_BUST], Hud.RED, 10, 226.0)
		"busted":
			hud.popup("ARRÊTÉ !", Hud.RED, 18, 196.0)
			_say(Scenario.RADIO["arrete"])
			audio.play("thud", 0.0)
			save.busted += 1
		"escaped":
			game.set_flag("poursuite")
			save.pursuits_escaped += 1
			hud.popup(Lang.t("SEMÉE ! +%s") % Hud._group(Police.escape_points(police.stage, e.time)), Hud.AMBER, 18, 196.0)
			hud.popup("TURBO PLEIN", Hud.PINK, 9, 222.0)
			_say(Scenario.RADIO["seme_secteur" if e.why == "secteur" else "seme_distance"])
			audio.play("chime", -4.0)


func _on_station(index: int, added: float) -> void:
	hud.popup("+%d" % int(added), Hud.AMBER, 32, 140.0)
	hud.popup(Lang.t("STATION %d") % (index + 1), Hud.WHITE, 8, 188.0)
	# À chaque station, un message de Lou attend sur le répondeur.
	var region := RouteMap.theme_id(index, game.choices)
	var fresh := _collect_message(region)
	_radio_queue.push_front([Scenario.LOU[region], INF,
			(Lang.t("NOUVEAU — ") if fresh else "") + Lang.t(Scenario.LOU_HEADER)])
	_write_save()


func _on_fork(_index: int, _side: int) -> void:
	_sync_choices()
	_fork_said = false


func _on_region(_stage: int, theme_id: String) -> void:
	hud.title_card(RouteMap.THEMES[theme_id]["name"])
	_say(Scenario.RADIO[theme_id])


func _on_arrived(bonus: int) -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	var first_time := not _args.has("autopilot") and save.record_ending(game.ending, int(game.score))
	# Le dernier message de Lou arrive avec l'aube.
	var last_region := RouteMap.theme_id(RouteMap.STAGES.size() - 1, game.choices)
	var lou := Lang.t("%s\n« %s »") % [Lang.t(Scenario.LOU_HEADER), Lang.t(Scenario.LOU[last_region])]
	_collect_message(last_region)
	for f in game.flags:
		save.events_seen[f] = true
	var earned := _earn_credits()
	_write_save()
	_save_ghost()
	_begin_ending_scene()
	police.state = Police.State.DONE
	game.pursuit = false
	_ending_overlay = [RouteMap.ENDINGS[game.ending],
			Lang.t("%s\n\n%s\n\n%sSCORE %s\nBONUS TEMPS %s\nÉVÉNEMENTS %d/%d\n%s\n+%s CRÉDITS%s") % [
				Scenario.ending_text(game.ending, game.flags), lou,
				Lang.t("NOUVELLE FIN ! ") if first_time else "", Hud._group(int(game.score)), Hud._group(bonus),
				game.flags.size(), Menus.EVENT_NAMES.size(), Lang.t("NOUVEAU RECORD !") if record else Lang.t("RECORD %s") % Hud._group(save.best),
				Hud._group(earned), Lang.t("  —  nouvelle teinte au garage") if first_time else ""],
			"TOUCHE POUR REJOUER"]
	_overlay_at = _time + ENDING_SCENE_TIME


## Préchauffage : les effets rares (étincelles, hologramme du fantôme, voiture
## de police et ses gyrophares) sont dessinés quelques images, cachés sous la
## route, pendant le chargement. Le navigateur compile leurs shaders à ce
## moment-là plutôt qu'au premier choc (qui figeait l'image un instant).
func _warm_up_step() -> void:
	if _warm_frames <= 0:
		return
	_warm_frames -= 1
	var hidden := track.transform_at(car.s + 14.0, 0.0, -2.5)
	var done := _warm_frames == 0
	ghost_view.visible = not done
	ghost_view.transform = hidden
	police_view.warm_up(hidden, not done)
	if _warm_frames == 3:
		car_view.warm_sparks(hidden.origin)


## Fantôme : affiché tant qu'il suit la même route, écart en secondes à l'écran.
func _update_ghost() -> void:
	if ghost == null or _ghost_lost or game.state == GameRun.State.WAITING or _anchor < INF:
		ghost_view.visible = false
		hud.set_ghost("", false)
		return
	if not ghost.same_route(game.choices):
		_ghost_lost = true
		hud.popup("LE FANTÔME A PRIS L'AUTRE ROUTE", Hud.LOU_BLUE, 8, 250.0)
		return
	var p := ghost.at(_run_time)
	ghost_view.show_at(track, p.x, p.y, car.s)
	var t_ghost := ghost.time_at(car.s)
	if t_ghost == INF:
		hud.set_ghost("", false)
		return
	var gap := _run_time - t_ghost
	if _args.has("ghost_log") and Engine.get_process_frames() % 30 == 0:
		print("fantôme t %.2f joueur s %.0f | fantôme s %.0f x %.1f | écart %.2f" % [_run_time, car.s, p.x, p.y, gap])
	var txt := "%+.1f S" % gap
	if Lang.code == "fr":
		txt = txt.replace(".", ",")
	hud.set_ghost(Lang.t("RECORD %s") % txt, gap <= 0.0)


## Carte à partager : l'image de la scène telle qu'elle est (avant que le
## panneau de fin ne la couvre), composée en arrière-plan.
func _make_share_card(headline: String, detail: String, accent: Color, text: String) -> void:
	var scene := get_viewport().get_texture().get_image()
	if scene == null or scene.is_empty():
		return
	_share = ShareCard.new()
	add_child(_share)
	_share.ready_to_share.connect(func() -> void:
		hud.show_share(true)
		if _args.has("share_card"):
			var f := FileAccess.open(str(_args["share_card"]), FileAccess.WRITE)
			f.store_buffer(_share.png))
	_share.compose(scene, headline, detail, int(game.score), accent, text)


## Fin de partie : si elle bat le fantôme (au score), elle devient le fantôme.
func _save_ghost() -> void:
	if _args.has("autopilot") and not _args.has("record_ghost"):
		return
	_ghost_rec.choices = game.choices.duplicate()
	_ghost_rec.score = int(game.score)
	var best := Ghost.load_for(_seed)
	if best == null or _ghost_rec.score > best.score:
		_ghost_rec.write()


func _on_time_up() -> void:
	_end_time = _time
	var record := _save_best(int(game.score))
	for f in game.flags:
		save.events_seen[f] = true
	var earned := _earn_credits()
	_write_save()
	_save_ghost()
	_make_share_card(Lang.t("LA NUIT GAGNE"), Lang.t("Étape %d sur %d — %.1f km") % [game.segment() + 1, RunConfig.SEGMENT_COUNT, car.s / 1000.0],
			Hud.PINK, Lang.t("La nuit m'a rattrapé à l'étape %d dans Route de Nuit : %s points.") % [game.segment() + 1, Lang.group(int(game.score))])
	hud.show_overlay("LA NUIT\nGAGNE",
			Lang.t("\nÉTAPE %d SUR %d\n%.1f KM\n\nSCORE %s\n\n%s\n+%s CRÉDITS") % [
				game.segment() + 1, RunConfig.SEGMENT_COUNT, car.s / 1000.0, Hud._group(int(game.score)),
				Lang.t("NOUVEAU RECORD !") if record else Lang.t("RECORD %s") % Hud._group(save.best), Hud._group(earned)],
			"TOUCHE POUR REJOUER")


## Crédits de fin de partie (et record de la nuit du jour) ; renvoie le gain.
func _earn_credits() -> int:
	if _args.has("autopilot"):
		return 0
	var earned := SaveData.credits_for(int(game.score))
	save.credits += earned
	if daily_mode:
		save.daily[today()] = maxi(int(save.daily.get(today(), 0)), int(game.score))
	return earned


## Garde un message de Lou dans le carnet ; renvoie vrai s'il est nouveau.
func _collect_message(theme_id: String) -> bool:
	if _args.has("autopilot") or save.messages.has(theme_id):
		return false
	save.messages[theme_id] = true
	return true


func _write_save() -> void:
	if not _args.has("autopilot"):
		save.write()


## Enregistre le score s'il bat le record ; renvoie vrai si c'est un record.
func _save_best(score: int) -> bool:
	if score <= save.best or _args.has("autopilot"):
		return false
	save.best = score
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
	if not blocking and _sliced:
		_build_sliced(missing)
	elif not blocking and missing != -1 and _building == -1:
		_building = missing
		_build_task_id = WorkerThreadPool.add_task(_build_in_background.bind(missing, game.choices.duplicate()))
	for i in _chunks.keys():
		if not wanted.has(i):
			_chunks[i].queue_free()
			_chunks.erase(i)


## Sans fil d'exécution (version web) : le tronçon se construit par étapes,
## dans un budget de temps à chaque image, pour ne jamais saccader.
func _build_sliced(missing: int) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < SLICE_BUDGET_USEC:
		if _job.is_empty():
			if missing == -1:
				return
			_worker_builder.choices = game.choices.duplicate()
			_worker_builder.track.choices.assign(game.choices)
			_job = _worker_builder.begin_chunk(missing)
			missing = -1
		if _worker_builder.step_chunk(_job):
			var index: int = _job["index"]
			var mi: MeshInstance3D = _job["result"]
			_job = {}
			_worker_builder.track.trim((index - 2) * RoadBuilder.CHUNK_LENGTH)
			if _chunks.has(index) or absf(index * RoadBuilder.CHUNK_LENGTH - car.s) > 800.0:
				mi.free()
			else:
				_add_chunk(index, mi)


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
		# Au garage, la voiture remonte dans la moitié haute, au-dessus du panneau.
		var garage := menus != null and menus.current == "garage"
		hud.visible = menus == null or menus.current == "" and not _args.has("showcase")
		var a := _time * 0.25 + 2.2
		var radius := 8.0 if garage else 6.5
		var orbit := t.origin + t.basis * Vector3(sin(a) * radius, 1.7, cos(a) * radius)
		camera.look_at_from_position(orbit, t.origin + t.basis.y * (-1.9 if garage else 0.8), Vector3.UP)
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
	if _anchor < INF:
		# Scène de fin : la caméra quitte la voiture et s'élève vers l'aube.
		var shot := _ending_shot()
		var b := smoothstep(0.3, 5.0, _time - _end_time)
		eye = eye.lerp(shot[0], b)
		target = target.lerp(shot[1], b)
		camera.look_at_from_position(eye, target, Vector3.UP)
		camera.fov = lerpf(lerpf(60.0, 72.0, minf(car.speed / CarPhysics.TOP_SPEED, 1.0)), 50.0, b)
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.25
	camera.look_at_from_position(eye, target, Vector3.UP)
	# Le champ s'ouvre avec la vitesse, et encore plus sous turbo.
	_turbo_fov = lerpf(_turbo_fov, 9.0 if game.is_boosting() else 0.0, 1.0 - exp(-4.0 * delta) if delta > 0.0 else 1.0)
	camera.fov = lerpf(60.0, 72.0, minf(car.speed / CarPhysics.TOP_SPEED, 1.0)) + _turbo_fov

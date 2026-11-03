class_name AudioDirector
extends Node
## Le son du jeu (fichiers synthétisés par tools/make_audio.py) :
##  - moteur en deux couches (grondement, montée) dont le régime suit une boîte
##    à 6 rapports ;
##  - vent et pneus mouillés selon la vitesse, pluie selon la météo ; écho et
##    pluie coupée dans les tunnels ;
##  - bruitages (choc, frôlement, station, terre-plein, radio) ;
##  - la radio : deux stations musicales et « éteinte », au double tap.

## Vitesses de passage des rapports (m/s).
const GEARS := [0.0, 15.0, 28.0, 41.0, 54.0, 66.0, 80.0]
const STATIONS := [
	{"name": "RADIO NUIT 98.4", "music": "music_synthwave"},
	{"name": "BLEU NUIT 103.7", "music": "music_lofi"},
	{"name": "RADIO ÉTEINTE", "music": ""},
]

var station := 0
## Régime moteur (0 ralenti, 1 rupteur) et rapport engagé, pour l'affichage.
var rpm := 0.25
var gear := 1

var _engine_low: AudioStreamPlayer
var _engine_high: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _tires: AudioStreamPlayer
var _music: AudioStreamPlayer
## Scène de fin : la musique de l'aube, et le moteur qui s'efface au ralenti.
var _dawn: AudioStreamPlayer
var _engine_fade := 1.0
var _siren: AudioStreamPlayer
var _siren_level := 0.0
var _oneshots: Array[AudioStreamPlayer] = []
var _streams := {}
var _reverb: AudioEffectReverb
var _sfx_bus := 0
var _music_bus := 0


func _ready() -> void:
	_sfx_bus = _make_bus("Bruitages")
	_music_bus = _make_bus("Musique")
	# Les bus survivent au rechargement de la scène (rejouer) : on réutilise l'écho.
	if AudioServer.get_bus_effect_count(_sfx_bus) > 0:
		_reverb = AudioServer.get_bus_effect(_sfx_bus, 0)
	else:
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.6
		_reverb.damping = 0.4
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(_sfx_bus, _reverb)
	_reverb.wet = 0.0
	_engine_low = _loop("engine_low", -10.0)
	_engine_high = _loop("engine_high", -40.0)
	_wind = _loop("wind", -40.0)
	_rain = _loop("rain", -20.0)
	_tires = _loop("tires", -40.0)
	_siren = _loop("siren", -80.0)
	_music = AudioStreamPlayer.new()
	_music.bus = AudioServer.get_bus_name(_music_bus)
	# Mélange : en pleine course, la musique passait 17 dB sous le moteur, le
	# vent et la pluie (inaudible). Elle est maintenant ~5 dB sous les bruitages.
	_music.volume_db = 0.0
	add_child(_music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = AudioServer.get_bus_name(_sfx_bus)
		add_child(p)
		_oneshots.append(p)
	_tune(0)


## À chaque image : vitesse (m/s), gaz (0..1), pluie (0..1), tunnel.
func update(speed: float, throttle: float, rain_amount: float, tunnel: bool, delta: float) -> void:
	# Rapport et régime : le régime monte dans le rapport puis retombe au passage.
	while gear < GEARS.size() - 2 and speed > GEARS[gear + 1]:
		gear += 1
	while gear > 1 and speed < GEARS[gear] - 3.0:
		gear -= 1
	var lo: float = GEARS[gear]
	var hi: float = GEARS[gear + 1]
	var target := 0.25 + 0.75 * clampf((speed - lo) / (hi - lo), 0.0, 1.0)
	if speed < 1.0:
		target = 0.22
	rpm = lerpf(rpm, target, 1.0 - exp(-10.0 * delta)) if delta > 0.0 else target
	var load := 1.0 if throttle > 0.0 else 0.55
	_engine_low.pitch_scale = 0.55 + rpm * 1.25
	_engine_high.pitch_scale = 0.5 + rpm * 1.15
	_engine_low.volume_db = linear_to_db(lerpf(0.9, 0.45, rpm) * load * _engine_fade + 0.001) - 9.0
	_engine_high.volume_db = linear_to_db(pow(rpm, 1.6) * load * 0.8 * _engine_fade + 0.001) - 9.0
	var v := clampf(speed / CarPhysics.TOP_SPEED, 0.0, 1.0)
	_wind.volume_db = linear_to_db(v * v * 0.7 + 0.001) - 7.0
	_tires.volume_db = linear_to_db(pow(v, 1.4) * rain_amount * 0.6 + 0.001) - 9.0
	_rain.volume_db = linear_to_db((0.0 if tunnel else rain_amount) * 0.7 + 0.001) - 7.0
	_reverb.wet = move_toward(_reverb.wet, 0.35 if tunnel else 0.0, delta * 1.5)


## Arrivée : la radio s'éteint doucement, le moteur se tait presque, et la
## musique de l'aube monte (sur le bus Musique : le réglage de volume compte).
func play_dawn() -> void:
	if _dawn != null:
		return
	_dawn = AudioStreamPlayer.new()
	_dawn.bus = _music.bus
	_dawn.stream = _stream("dawn")
	_dawn.volume_db = -30.0
	add_child(_dawn)
	var tw := create_tween().set_parallel()
	tw.tween_property(_music, "volume_db", -60.0, 3.0)
	tw.tween_property(self, "_engine_fade", 0.3, 5.0)
	tw.tween_callback(_dawn.play).set_delay(1.2)
	tw.tween_property(_dawn, "volume_db", -5.0, 4.0).set_delay(1.2)
	tw.chain().tween_callback(_music.stop)


## Sirène : plus forte quand la police est proche, plus aiguë quand elle se
## rapproche (effet Doppler), muette hors poursuite.
func update_siren(on: bool, distance: float, closing_speed: float, delta: float) -> void:
	var target := clampf(40.0 / (40.0 + absf(distance)), 0.0, 1.0) if on else 0.0
	_siren_level = move_toward(_siren_level, target, delta * (3.0 if on else 0.8))
	_siren.volume_db = linear_to_db(_siren_level * 0.9 + 0.0001) - 3.0
	_siren.pitch_scale = clampf(343.0 / (343.0 - closing_speed), 0.92, 1.08)


func next_station() -> String:
	_tune((station + 1) % STATIONS.size())
	play("static", -8.0)
	return STATIONS[station]["name"]


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	for p in _oneshots:
		if not p.playing:
			p.stream = _stream(name)
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func _tune(index: int) -> void:
	station = index
	var music: String = STATIONS[station]["music"]
	if music == "":
		_music.stop()
		return
	_music.stream = _stream(music, true)
	_music.play()


func _loop(name: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(name, true)
	p.volume_db = volume_db
	p.bus = AudioServer.get_bus_name(_sfx_bus)
	add_child(p)
	p.play()
	return p


func _stream(name: String, loop := false) -> AudioStream:
	var key := name + ("#loop" if loop else "")
	if not _streams.has(key):
		var s: AudioStreamOggVorbis = load("res://assets/audio/%s.ogg" % name).duplicate()
		s.loop = loop
		_streams[key] = s
	return _streams[key]


func _make_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

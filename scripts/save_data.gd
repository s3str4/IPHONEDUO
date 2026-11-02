class_name SaveData
extends RefCounted
## Tout ce qui survit d'une partie à l'autre (user://save.cfg) : record,
## parties jouées, fins découvertes et record par fin, messages de Lou reçus,
## événements déjà vus, couleur de la voiture, réglages, records de la nuit
## du jour. Les tests utilisent un autre chemin.

const PATH := "user://save.cfg"

var path := PATH
var best := 0
var runs := 0
## Indice de fin -> meilleur score obtenu en y arrivant.
var endings := {}
## Tronçon (id d'ambiance) -> vrai : message de Lou reçu.
var messages := {}
## Événement -> vrai : déjà vu au moins une fois.
var events_seen := {}
var car_color := 0
var music_volume := 0.8
var sfx_volume := 1.0
## Sensibilité du pouce : 0.7 (doux) à 1.4 (vif).
var sensitivity := 1.0
## Qualité graphique : 0 sobre, 1 normale, 2 haute.
var quality := 2
## « AAAA-MM-JJ » -> meilleur score de la nuit du jour.
var daily := {}
## Garage : crédits gagnés en roulant, niveaux d'amélioration (0..3),
## options esthétiques achetées et choisies.
var credits := 0
var upgrades := {"moteur": 0, "pneus": 0, "turbo": 0, "chassis": 0}
var owned := {}
var neon_color := 0
var spoiler_on := true
var neon_on := true
## Langue : "" (celle du système), "fr" ou "en".
var language := ""


static func load_or_new(p: String = PATH) -> SaveData:
	var s := SaveData.new()
	s.path = p
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		return s
	s.best = int(cfg.get_value("scores", "best", 0))
	s.runs = int(cfg.get_value("progress", "runs", 0))
	# Anciennes sauvegardes : une simple liste des fins découvertes.
	var e = cfg.get_value("progress", "endings", {})
	if e is Array:
		for i in e:
			s.endings[int(i)] = 0
	else:
		s.endings = e
	s.messages = cfg.get_value("progress", "messages", {})
	s.events_seen = cfg.get_value("progress", "events", {})
	s.car_color = int(cfg.get_value("garage", "color", 0))
	s.music_volume = float(cfg.get_value("settings", "music", 0.8))
	s.sfx_volume = float(cfg.get_value("settings", "sfx", 1.0))
	s.sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))
	s.quality = int(cfg.get_value("settings", "quality", 2))
	s.daily = cfg.get_value("daily", "best", {})
	s.credits = int(cfg.get_value("garage", "credits", 0))
	var up: Dictionary = cfg.get_value("garage", "upgrades", {})
	for k in up:
		s.upgrades[k] = int(up[k])
	s.owned = cfg.get_value("garage", "owned", {})
	s.neon_color = int(cfg.get_value("garage", "neon_color", 0))
	s.spoiler_on = bool(cfg.get_value("garage", "spoiler_on", true))
	s.neon_on = bool(cfg.get_value("garage", "neon_on", true))
	s.language = str(cfg.get_value("settings", "language", ""))
	return s


func write() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "best", best)
	cfg.set_value("progress", "runs", runs)
	cfg.set_value("progress", "endings", endings)
	cfg.set_value("progress", "messages", messages)
	cfg.set_value("progress", "events", events_seen)
	cfg.set_value("garage", "color", car_color)
	cfg.set_value("settings", "music", music_volume)
	cfg.set_value("settings", "sfx", sfx_volume)
	cfg.set_value("settings", "sensitivity", sensitivity)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("daily", "best", daily)
	cfg.set_value("garage", "credits", credits)
	cfg.set_value("garage", "upgrades", upgrades)
	cfg.set_value("garage", "owned", owned)
	cfg.set_value("garage", "neon_color", neon_color)
	cfg.set_value("garage", "spoiler_on", spoiler_on)
	cfg.set_value("garage", "neon_on", neon_on)
	cfg.set_value("settings", "language", language)
	cfg.save(path)


## Crédits gagnés à la fin d'une partie (un pour cent points de score).
static func credits_for(score: int) -> int:
	return score / 100


## Achète le niveau suivant d'une amélioration ; renvoie vrai si c'est fait.
func buy_upgrade(key: String) -> bool:
	var level: int = upgrades[key]
	if level >= Garage.MAX_LEVEL or credits < Garage.PRICES[level]:
		return false
	credits -= Garage.PRICES[level]
	upgrades[key] = level + 1
	return true


## Achète une option esthétique ; renvoie vrai si c'est fait.
func buy_option(key: String) -> bool:
	if owned.has(key) or credits < Garage.OPTIONS[key][1]:
		return false
	credits -= Garage.OPTIONS[key][1]
	owned[key] = true
	return true


## Enregistre une arrivée ; renvoie vrai si la fin est nouvelle.
func record_ending(ending: int, score: int) -> bool:
	var fresh := not endings.has(ending)
	endings[ending] = maxi(int(endings.get(ending, 0)), score)
	return fresh


## Couleurs de carrosserie disponibles : la rouge, plus une par fin découverte.
func unlocked_colors() -> Array:
	var out := [0]
	for e in endings.keys():
		out.append(int(e) + 1)
	out.sort()
	return out

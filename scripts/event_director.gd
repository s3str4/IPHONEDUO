class_name EventDirector
extends RefCounted
## Programme des événements étranges d'une partie, sans rendu. Les positions
## dépendent de la graine et du nombre de parties déjà jouées (l'auto-stoppeuse
## est chaque fois un peu plus loin), pas du chemin : on les croise toutes,
## sauf le tunnel trop long, réservé à l'ambiance « tunnels ».

## Événements : nom -> s (m). « panneau » : le premier des trois panneaux.
var plan := {}
## Événements déjà déclenchés.
var fired := {}

const PANNEAU_SPACING := 300.0
const GHOST_DURATION := 9.0


func _init(seed: int = 1, runs: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "evenements"])
	plan["stoppeuse"] = RouteMap.region_start(1) + 1500.0 + float(posmod(runs, 6)) * 450.0
	plan["radio_live"] = RouteMap.region_start(1) + rng.randf_range(600.0, 1100.0)
	plan["panneau"] = RouteMap.region_start(2) + rng.randf_range(1200.0, 2200.0)
	plan["fantome"] = RouteMap.region_start(3) + rng.randf_range(1500.0, 2600.0)
	# Station 3 : celle au bout de l'étape 3.
	plan["station_vide"] = RouteMap.fork_s(2)


## Événements dont la position vient d'être franchie entre prev_s et s.
func crossed(prev_s: float, s: float) -> Array:
	var out := []
	for name in plan:
		var at: float = plan[name]
		if name == "panneau":
			at += 2.0 * PANNEAU_SPACING
		if not fired.has(name) and prev_s < at and s >= at:
			fired[name] = true
			out.append(name)
	return out


## Le panneau « VOUS ÊTES ICI » est-il posé en s (à 1 m près) ?
func panneau_at(s0: float, s1: float) -> Array:
	var out := []
	for i in 3:
		var p: float = plan["panneau"] + i * PANNEAU_SPACING
		if p >= s0 and p < s1:
			out.append(p)
	return out

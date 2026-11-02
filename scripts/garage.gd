class_name Garage
extends RefCounted
## Améliorations de la voiture, achetées avec les crédits gagnés en roulant.
## Les gains restent modestes (quelques pour cent) : l'adresse compte plus que
## l'argent, et l'équilibrage (tools/balance.gd) est mesuré voiture d'origine.

const MAX_LEVEL := 3
const PRICES := [1200, 3500, 8000]
const UPGRADES := {
	"moteur": ["MOTEUR", "Vitesse de pointe +1,5 % par niveau"],
	"pneus": ["PNEUS PLUIE", "Braquage +6 %, moins de dérive en virage"],
	"turbo": ["TURBO", "Jauge +15 % plus rapide, +0,3 s de turbo"],
	"chassis": ["CHÂSSIS", "Moins de vitesse perdue dans les chocs"],
}
## Options esthétiques : [nom, prix].
const OPTIONS := {
	"aileron": ["AILERON", 1500],
	"neon": ["NÉON SOUS CAISSE", 2500],
	"jantes": ["JANTES CHROMÉES", 1000],
}
const NEON_COLORS := [Color(1.0, 0.25, 0.65), Color(0.2, 0.85, 1.0), Color(0.6, 0.35, 1.0), Color(0.3, 1.0, 0.5)]


## Applique les améliorations à la physique de la voiture et aux règles.
static func apply(save: SaveData, car: CarPhysics, game: GameRun) -> void:
	car.upgrade_top = 1.0 + 0.015 * save.upgrades["moteur"]
	car.steer_mult = 1.0 + 0.06 * save.upgrades["pneus"]
	car.grip = 1.0 - 0.05 * save.upgrades["pneus"]
	car.crash_keep = 0.06 * save.upgrades["chassis"]
	game.turbo_gain = 1.0 + 0.15 * save.upgrades["turbo"]
	game.turbo_duration = RunConfig.TURBO_DURATION + 0.3 * save.upgrades["turbo"]

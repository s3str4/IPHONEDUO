class_name CarPhysics
extends RefCounted
## Conduite arcade en coordonnées de route (s, x), sans moteur physique :
## prévisible, réglable et testable en headless.
##
## Entrées par image : throttle (0..1) et steer (-1..1). Les virages poussent
## la voiture vers l'extérieur ; il faut braquer pour rester sur la route.

const TOP_SPEED := 78.0          # m/s (≈ 280 km/h)
const ACCEL := 16.0              # m/s² à l'arrêt, décroît jusqu'à la vitesse max
const COAST_DECEL := 5.0         # pouce levé : frein moteur
const BRAKE_DECEL := 22.0        # pouce levé longtemps : freinage
const BRAKE_DELAY := 0.45        # s de pouce levé avant de freiner
const STEER_SPEED_LOW := 5.0     # m/s de déplacement latéral à basse vitesse
const STEER_SPEED_HIGH := 13.0   # m/s de déplacement latéral à pleine vitesse
const STEER_RESPONSE := 9.0      # réactivité du braquage (1/s)
const CENTRIFUGAL := 0.075       # poussée vers l'extérieur = κ·v²·CENTRIFUGAL
const ROAD_HALF_WIDTH := 6.0     # 3 voies de 4 m
const SHOULDER := 7.5            # accotement : la voiture ralentit
const RAIL := 8.0                # glissière
const SHOULDER_DRAG := 18.0      # m/s² de freinage sur l'accotement
const RAIL_SPEED_LOSS := 0.82    # vitesse gardée à chaque choc contre la glissière
const RAIL_SCRAPE_DRAG := 12.0   # m/s² en frottant contre la glissière
const CAR_HALF_WIDTH := 0.9

var s := 0.0
var x := 0.0
var speed := 0.0
## Vitesse latérale (m/s), positive vers la droite.
var lateral := 0.0
## Angle de dérapage visuel (rad), pour l'affichage de la voiture.
var slip := 0.0
var rail_hits := 0
## Vrai pendant l'image où la voiture touche la glissière.
var hit_rail := false

var _lift_time := 0.0
var _on_rail := false


func step(track: Track, throttle: float, steer: float, delta: float) -> void:
	steer = clampf(steer, -1.0, 1.0)
	var v_ratio := speed / TOP_SPEED

	# Longitudinal.
	if throttle > 0.0:
		_lift_time = 0.0
		speed += ACCEL * throttle * (1.0 - v_ratio * v_ratio) * delta
	else:
		_lift_time += delta
		var decel := BRAKE_DECEL if _lift_time > BRAKE_DELAY else COAST_DECEL
		speed = maxf(0.0, speed - decel * delta)

	var off := absf(x) + CAR_HALF_WIDTH - ROAD_HALF_WIDTH
	if off > 0.0:
		speed = maxf(0.0, speed - SHOULDER_DRAG * clampf(off / (SHOULDER - ROAD_HALF_WIDTH), 0.0, 1.0) * delta)

	# Latéral : le braquage vise une vitesse latérale, le virage pousse dehors.
	var steer_speed := lerpf(STEER_SPEED_LOW, STEER_SPEED_HIGH, v_ratio) * minf(1.0, speed / 6.0)
	var target := steer * steer_speed
	lateral = lerpf(lateral, target, 1.0 - exp(-STEER_RESPONSE * delta))
	var push := track.curvature_at(s) * speed * speed * CENTRIFUGAL
	# Virage à droite (κ > 0) : poussée vers la gauche.
	x += (lateral - push) * delta
	slip = lerpf(slip, clampf((lateral - push) / maxf(speed, 1.0) * 2.5, -0.5, 0.5), 1.0 - exp(-6.0 * delta))

	# Glissière : un choc franc coûte de la vitesse, frotter contre elle freine.
	hit_rail = false
	var limit := RAIL - CAR_HALF_WIDTH
	if absf(x) >= limit:
		x = signf(x) * limit
		if not _on_rail:
			speed *= RAIL_SPEED_LOSS
			rail_hits += 1
			hit_rail = true
		else:
			speed = maxf(0.0, speed - RAIL_SCRAPE_DRAG * delta)
		lateral = -signf(x) * 1.5
		_on_rail = true
	elif absf(x) < limit - 0.3:
		_on_rail = false

	s += speed * delta


func speed_kmh() -> float:
	return speed * 3.6


## Pilote automatique (tests, captures) : renvoie le braquage qui compense la
## poussée du virage et ramène la voiture vers target_x.
func autopilot_steer(track: Track, target_x: float) -> float:
	var steer_speed := lerpf(STEER_SPEED_LOW, STEER_SPEED_HIGH, speed / TOP_SPEED) * minf(1.0, speed / 6.0)
	if steer_speed <= 0.0:
		return 0.0
	var push := track.curvature_at(s + speed * 0.3) * speed * speed * CENTRIFUGAL
	var wanted := push + (target_x - x) * 1.2
	return clampf(wanted / steer_speed, -1.0, 1.0)

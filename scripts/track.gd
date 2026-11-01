class_name Track
extends RefCounted
## Tracé de la route : une ligne centrale échantillonnée tous les STEP mètres,
## générée à la demande devant la voiture et oubliée derrière.
##
## Tout se repère par `s`, la distance parcourue le long de la route (mètres),
## et `x`, le décalage latéral (mètres, positif à droite). Même graine = même route.

const STEP := 2.0
## Courbure maximale (rad/m) : rayon de 110 m, serré mais pris à fond en dérapant.
const MAX_CURVATURE := 0.009
## Vitesse de variation de la courbure (rad/m par mètre) : entrées de virage douces.
const CURVATURE_RATE := 0.00012
const SLOPE_RATE := 0.0006

var _rng := RandomNumberGenerator.new()
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _curv := PackedFloat32Array()
## Indice absolu du premier point gardé en mémoire.
var _base := 0

# État du générateur.
var _section_left := 0.0
var _curv_target := 0.0
var _slope_target := 0.0
var _cur_curv := 0.0
var _cur_slope := 0.0
var _cur_yaw := 0.0
var _cur_pos := Vector3.ZERO


func _init(seed: int = 1) -> void:
	_rng.seed = seed
	# Départ en ligne droite et à plat.
	_section_left = 160.0
	_push_point()
	ensure(400.0)


## Longueur générée (s du dernier point).
func end_s() -> float:
	return float(_base + _pos.size() - 1) * STEP


## Plus petit s encore en mémoire.
func start_s() -> float:
	return float(_base) * STEP


## Génère la route au moins jusqu'à s_max.
func ensure(s_max: float) -> void:
	while end_s() < s_max:
		_push_point()


## Oublie les points avant s_min (la route derrière la voiture).
func trim(s_min: float) -> void:
	var drop := int(floor(s_min / STEP)) - _base
	if drop < 64:
		return
	_pos = _pos.slice(drop)
	_yaw = _yaw.slice(drop)
	_curv = _curv.slice(drop)
	_base += drop


func point_at(s: float) -> Vector3:
	var f := _index(s)
	var i := int(f)
	return _pos[i].lerp(_pos[mini(i + 1, _pos.size() - 1)], f - i)


func yaw_at(s: float) -> float:
	var f := _index(s)
	var i := int(f)
	return lerpf(_yaw[i], _yaw[mini(i + 1, _yaw.size() - 1)], f - i)


func curvature_at(s: float) -> float:
	var f := _index(s)
	var i := int(f)
	return lerpf(_curv[i], _curv[mini(i + 1, _curv.size() - 1)], f - i)


## Direction d'avancée (avec la pente).
func forward_at(s: float) -> Vector3:
	var a := point_at(maxf(s - STEP, start_s()))
	var b := point_at(minf(s + STEP, end_s()))
	return (b - a).normalized()


## Droite de la route, toujours horizontale (la route n'est pas relevée en virage).
func right_at(s: float) -> Vector3:
	var y := yaw_at(s)
	return Vector3(cos(y), 0.0, sin(y))


## Repère local de la route en (s, x) : -Z vers l'avant, +X à droite, +Y en haut.
func transform_at(s: float, x: float = 0.0, height: float = 0.0) -> Transform3D:
	var fwd := forward_at(s)
	var right := right_at(s)
	var up := right.cross(fwd).normalized()
	var origin := point_at(s) + right * x + up * height
	return Transform3D(Basis(right, up, -fwd), origin)


func _index(s: float) -> float:
	var f := s / STEP - float(_base)
	return clampf(f, 0.0, float(_pos.size() - 1) - 0.0001)


func _push_point() -> void:
	if _section_left <= 0.0:
		_new_section()
	_cur_curv = move_toward(_cur_curv, _curv_target, CURVATURE_RATE * STEP)
	_cur_slope = move_toward(_cur_slope, _slope_target, SLOPE_RATE * STEP)
	if not _pos.is_empty():
		_cur_yaw += _cur_curv * STEP
		var fwd := Vector3(sin(_cur_yaw), 0.0, -cos(_cur_yaw))
		_cur_pos += fwd * STEP
		_cur_pos.y += _cur_slope * STEP
	_pos.append(_cur_pos)
	_yaw.append(_cur_yaw)
	_curv.append(_cur_curv)
	_section_left -= STEP


func _new_section() -> void:
	_section_left = _rng.randf_range(90.0, 340.0)
	if _rng.randf() < 0.3:
		_curv_target = 0.0
	else:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		_curv_target = side * _rng.randf_range(0.25, 1.0) * MAX_CURVATURE
	# Collines douces, rappelées vers l'altitude 0 pour ne pas dériver.
	_slope_target = clampf(_rng.randf_range(-0.045, 0.045) - _cur_pos.y * 0.002, -0.06, 0.06)

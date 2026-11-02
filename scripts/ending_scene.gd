class_name EndingScene
extends RefCounted
## Les cinq destinations, à l'aube : la route s'arrête et un décor propre à
## chaque fin se dresse devant la voiture (la plage et Lou en ciré jaune,
## l'immeuble et sa fenêtre allumée, la crête du barrage, l'observatoire
## au-dessus des nuages, la cabine sur la plaine blanche).
##
## Tout est construit dans un repère posé au bout de la route : origine au
## milieu de la chaussée, x à droite, y en haut, -z droit devant (à
## l'horizontale). Le décor du monde au-delà est masqué (voir Main).

## Distance entre l'arrivée et le bout de la route (arrondie à un tronçon).
const RUNOUT := 260.0
## La voiture s'immobilise au plus tard à cette distance du bout de la route.
const STOP_BEFORE := 26.0

const SAND := Color(0.62, 0.52, 0.42)
const SNOW := Color(0.86, 0.88, 0.94)
const CONCRETE := Color(0.42, 0.42, 0.45)
const DARK := Color(0.06, 0.06, 0.08)
const RAINCOAT := Color(1.0, 0.78, 0.1)
const WARM := Color(1.0, 0.7, 0.35)


## Bout de la route pour une arrivée en `arrival_s` : en début de tronçon, pour
## que rien du monde normal ne dépasse.
static func anchor_s(arrival_s: float) -> float:
	return ceilf((arrival_s + RUNOUT) / RoadBuilder.CHUNK_LENGTH) * RoadBuilder.CHUNK_LENGTH


## Repère du bout de la route.
static func frame(track: Track, s: float) -> Transform3D:
	var f := track.forward_at(s)
	f.y = 0.0
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, Vector3.UP, -f), track.point_at(s))


## Construit la scène de la fin `ending`. Renvoie {node, focus, eye, sun,
## lights} : focus et eye (repère local) cadrent le plan final, sun décale le
## lever du soleil (radians, autour de l'axe de la route), lights sont des
## sources pour LightField.
static func build(ending: int, b: RoadBuilder, track: Track, s: float) -> Dictionary:
	var sc := EndingScene.new()
	sc._b = b
	sc._f = frame(track, s)
	sc._env = b._new_tool()
	sc._glow = b._new_tool()
	sc._wet = b._new_tool()
	var out: Dictionary
	match ending:
		0:
			out = sc._sea()
		1:
			out = sc._city()
		2:
			out = sc._dam()
		3:
			out = sc._mountain()
		_:
			out = sc._nowhere()
	var mats := b._materials_for({})
	var mi := MeshInstance3D.new()
	mi.name = "EndingScene"
	mi.mesh = b._assemble([[sc._env, mats[1]], [sc._glow, b.glow_material]])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wet := MeshInstance3D.new()
	wet.mesh = b._assemble([[sc._wet, b.water_material]])
	wet.layers = 1 << (Reflection.WET_LAYER - 1)
	wet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(wet)
	var lights := []
	for l in out.get("lights", []):
		lights.append([sc._f * l[0], l[1], l[2], l[3]])
	out["lights"] = lights
	out["node"] = mi
	out["frame"] = sc._f
	return out


var _b: RoadBuilder
var _f: Transform3D
var _env: SurfaceTool
var _glow: SurfaceTool
var _wet: SurfaceTool


## Après l'arrivée : la voiture roule en roue libre jusqu'au bout de la route
## et s'y arrête en douceur (12 m/s²), plus fort seulement si elle arrive trop
## vite. `prev_speed` est la vitesse avant le pas de la physique, dont le frein
## l'aurait arrêtée bien trop tôt.
static func brake(car: CarPhysics, anchor: float, delta: float, prev_speed: float) -> void:
	var room := anchor - STOP_BEFORE - car.s
	# Moins un demi-mètre par seconde : la courbe touche zéro juste avant le bout.
	var limit := maxf(sqrt(2.0 * 12.0 * maxf(room, 0.0)) - 0.5, 0.0)
	var stepped := car.speed
	car.speed = prev_speed if prev_speed <= limit else move_toward(prev_speed, limit, 36.0 * delta)
	# Le pas de la physique a avancé la voiture à sa vitesse freinée : on rattrape.
	car.s = minf(car.s + (car.speed - stepped) * delta, anchor - STOP_BEFORE)
	if room <= 0.0 or car.speed < 0.05:
		car.speed = 0.0
	car.x = lerpf(car.x, 0.0, 1.0 - exp(-0.8 * delta))


# --- Les cinq fins -----------------------------------------------------------------

## La mer : la route descend sur le sable, le soleil sort de l'eau, Lou attend
## au bord. Un phare au loin sur la gauche.
func _sea() -> Dictionary:
	_plane(_env, -400.0, 400.0, 0.0, -70.0, -0.15, SAND, 0.0)
	_plane(_wet, -3000.0, 3000.0, -60.0, -4000.0, -0.6, Color(0.3, 0.32, 0.4), 0.0)
	# Petite dune de chaque côté de l'arrivée, et des piquets de ganivelle.
	for side in [-1.0, 1.0]:
		_box(_env, Vector3(side * 16.0, -0.2, -6.0), Vector3(18.0, 1.4, 14.0), SAND * 0.85, 0.0)
		for i in 8:
			_box(_env, Vector3(side * (8.0 + i * 1.6), 0.0, -14.0), Vector3(0.12, 1.1, 0.12), DARK, 0.0)
	_figure(Vector3(2.2, -0.15, -16.0), RAINCOAT)
	# Phare.
	var lh := Vector3(-220.0, -0.6, -420.0)
	_box(_env, lh, Vector3(10.0, 4.0, 10.0), DARK, 0.0)
	for k in 6:
		_box(_env, lh + Vector3(0, 4.0 + k * 5.0, 0), Vector3(5.0 - k * 0.3, 5.0, 5.0 - k * 0.3),
				Color(0.85, 0.85, 0.85) if k % 2 == 0 else Color(0.7, 0.12, 0.1), 0.0)
	_glow_box(lh + Vector3(0, 34.0, 0), Vector3(3.0, 2.5, 3.0), WARM, 3.0)
	return {"focus": Vector3(1.5, 1.0, -40.0), "eye": Vector3(-3.0, 2.2, 8.0), "sun": 0.0,
			"lights": [[Vector3(2.2, 3.0, -14.0), WARM, 10.0, 0.6]]}


## La ville : une place, son immeuble droit devant, une seule fenêtre allumée
## au quatrième ; d'autres tours derrière.
func _city() -> Dictionary:
	_plane(_env, -300.0, 300.0, 0.0, -600.0, 0.0, Color(0.3, 0.3, 0.33), 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Rues bordées de tours, puis une ligne d'horizon.
	for i in 14:
		for side in [-1.0, 1.0]:
			var x: float = side * rng.randf_range(24.0, 60.0)
			var z := -30.0 - i * 40.0 - rng.randf_range(0.0, 20.0)
			var h := rng.randf_range(18.0, 70.0)
			_building(Vector3(x, 0, z), Vector3(rng.randf_range(14.0, 22.0), h, 16.0), rng, 0.25)
	for i in 24:
		var x := rng.randf_range(-500.0, 500.0)
		_building(Vector3(x, 0, -700.0 - rng.randf_range(0.0, 300.0)),
				Vector3(rng.randf_range(30.0, 60.0), rng.randf_range(40.0, 160.0), 30.0), rng, 0.15)
	# Son immeuble : cinq étages, tout éteint sauf sa fenêtre.
	var home := Vector3(0, 0, -52.0)
	_box(_env, home, Vector3(26.0, 17.0, 12.0), Color(0.36, 0.3, 0.3), 0.0)
	_box(_env, home + Vector3(0, 17.0, 0), Vector3(27.0, 0.6, 12.6), CONCRETE, 0.0)
	for floor_i in 5:
		for col in 6:
			var p := home + Vector3(-10.0 + col * 4.0, 1.4 + floor_i * 3.2, 6.05)
			var lit := floor_i == 3 and col == 3
			if lit:
				_glow_box(p, Vector3(1.6, 1.9, 0.1), WARM, 3.2)
			else:
				_box(_env, p, Vector3(1.6, 1.9, 0.1), Color(0.1, 0.11, 0.14), 0.0)
	# La porte, le mot dessus.
	_box(_env, home + Vector3(0, 0, 6.1), Vector3(2.2, 2.6, 0.2), DARK, 0.0)
	_box(_env, home + Vector3(0.0, 1.4, 6.25), Vector3(0.3, 0.4, 0.02), Color(0.95, 0.95, 0.9), 0.4)
	_glow_box(home + Vector3(0, 2.8, 6.3), Vector3(1.6, 0.25, 0.25), WARM, 1.5)
	return {"focus": Vector3(1.5, 9.0, -52.0), "eye": Vector3(4.5, 1.8, 6.0), "sun": 0.7,
			"lights": [[home + Vector3(2.0, 11.0, 8.0), WARM, 14.0, 1.0],
					[home + Vector3(0, 3.0, 8.0), WARM, 10.0, 0.8]]}


## Le barrage : la route devient la crête, le lac à gauche, le vide à droite.
func _dam() -> Dictionary:
	var length := 320.0
	# Crête et parapets, lampadaires éteints par l'aube.
	_plane(_env, -6.0, 6.0, 0.0, -length, 0.0, Color(0.34, 0.34, 0.37), 0.0)
	for side in [-1.0, 1.0]:
		_box(_env, Vector3(side * 6.3, 0.0, -length * 0.5), Vector3(0.6, 1.1, length), CONCRETE, 0.0)
		for k in 9:
			var z := -20.0 - k * 36.0
			_box(_env, Vector3(side * 6.3, 1.1, z), Vector3(0.2, 6.0, 0.2), DARK, 0.0)
			_glow_box(Vector3(side * 5.6, 6.8, z), Vector3(1.2, 0.2, 0.4), WARM, 1.2)
	# Le lac, haut, à gauche ; le parement qui plonge à droite, la vallée en bas.
	_plane(_wet, -3000.0, -6.6, 40.0, -3000.0, -2.5, Color(0.3, 0.32, 0.4), 0.0)
	_slope(Vector3(6.6, 0.0, 0.0), Vector3(70.0, -90.0, 0.0), length, CONCRETE * 0.9)
	_plane(_env, 70.0, 3000.0, 60.0, -3000.0, -90.0, Color(0.16, 0.2, 0.16), 0.0)
	# La maison du gardien au bout de la crête.
	_box(_env, Vector3(0, 0, -length - 8.0), Vector3(14.0, 6.0, 10.0), CONCRETE * 0.8, 0.0)
	_glow_box(Vector3(-3.0, 2.0, -length - 2.9), Vector3(1.4, 1.4, 0.1), WARM, 1.6)
	return {"focus": Vector3(14.0, -4.0, -120.0), "eye": Vector3(-4.0, 3.2, 10.0), "sun": -0.55,
			"lights": []}


## La montagne : une mer de nuages, un sommet, l'observatoire et sa fente
## éclairée. Lou attend devant, un thermos à la main.
func _mountain() -> Dictionary:
	_plane(_env, -12.0, 12.0, 0.0, -40.0, 0.0, Color(0.3, 0.3, 0.32), 0.0)
	# Le sommet : un cône bas, et tout autour les nuages.
	_cone_hill(Vector3(0, -40.0, -70.0), 120.0, 46.0, Color(0.42, 0.36, 0.38))
	_plane(_env, -3000.0, 3000.0, 80.0, -3000.0, -18.0, Color(0.95, 0.78, 0.8), 0.25)
	for k in 30:
		var a := k * 2.39996
		var r := 160.0 + float(k) * 40.0
		_box(_env, Vector3(cos(a) * r, -19.0, -sin(a) * r * 0.8 - 100.0),
				Vector3(80.0, 6.0, 50.0), Color(0.98, 0.82, 0.84), 0.3)
	var top := Vector3(0, 6.0, -70.0)
	_box(_env, top - Vector3(0, 6.0, 0), Vector3(16.0, 7.0, 16.0), CONCRETE, 0.0)
	_dome(top + Vector3(0, 1.0, 0), 7.0, Color(0.85, 0.85, 0.88))
	_glow_box(top + Vector3(0, 2.0, 6.6), Vector3(1.2, 6.2, 0.3), WARM, 1.8)
	_figure(Vector3(-1.8, 0.0, -14.0), Color(0.75, 0.2, 0.25))
	return {"focus": Vector3(0.0, 5.0, -70.0), "eye": Vector3(-6.0, 3.0, 8.0), "sun": 0.9,
			"lights": [[top + Vector3(0, 3.0, 9.0), WARM, 12.0, 0.8]]}


## Nulle part : la route s'efface dans la neige. Une cabine, le combiné pend.
func _nowhere() -> Dictionary:
	_plane(_env, -3000.0, 3000.0, 0.0, -3000.0, -0.05, SNOW, 0.0)
	var p := Vector3(2.6, 0.0, -10.0)
	var frame_col := Color(0.55, 0.08, 0.08)
	_box(_env, p, Vector3(1.3, 0.15, 1.3), frame_col, 0.0)
	_box(_env, p + Vector3(0, 2.25, 0), Vector3(1.3, 0.35, 1.3), frame_col, 0.0)
	for cx in [-0.6, 0.6]:
		for cz in [-0.6, 0.6]:
			_box(_env, p + Vector3(cx, 0.15, cz), Vector3(0.1, 2.1, 0.1), frame_col, 0.0)
	_glow_box(p + Vector3(0, 0.3, 0.0), Vector3(1.1, 1.9, 1.1), Color(1.0, 0.85, 0.6), 0.35)
	_glow_box(p + Vector3(0, 2.3, 0.66), Vector3(0.9, 0.22, 0.04), Color(1.0, 0.95, 0.85), 1.5)
	# Combiné pendu à son fil.
	_box(_env, p + Vector3(0.3, 0.7, 0.2), Vector3(0.1, 0.5, 0.1), DARK, 0.0)
	return {"focus": p + Vector3(-1.0, 1.4, 0), "eye": Vector3(-4.0, 1.9, 7.0), "sun": -0.25,
			"lights": [[p + Vector3(0, 1.8, 0), Color(1.0, 0.85, 0.6), 7.0, 0.7]]}


# --- Briques (repère local) -------------------------------------------------------

func _to_world(p: Vector3) -> Vector3:
	return _f * p


## Rectangle horizontal à la hauteur y, de x0 à x1 et de z0 à z1 (z vers l'arrière).
func _plane(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float,
		color: Color, light: float) -> void:
	var p := [Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0)]
	_quad(st, p, color, light)


func _quad(st: SurfaceTool, local: Array, color: Color, light: float, glow := false) -> void:
	var w := []
	for q in local:
		w.append(_to_world(q))
	var uvs := [Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, 1)] if glow else []
	_b._quad(st, w, [color, color, color, color], [light, light, light, light], uvs)


## Pavé posé au sol (base au centre de la face du bas).
func _box(st: SurfaceTool, base: Vector3, size: Vector3, color: Color, light: float, glow := false) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := []
	for y in [0.0, size.y]:
		for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			c.append(base + Vector3(corner.x, y, corner.y))
	for f in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
		_quad(st, [c[f[0]], c[f[1]], c[f[2]], c[f[3]]], color, light, glow)


func _glow_box(base: Vector3, size: Vector3, color: Color, strength: float) -> void:
	_box(_glow, base, size, color, strength, true)


## Silhouette debout, de dos à la caméra, face au soleil.
func _figure(base: Vector3, coat: Color) -> void:
	_box(_env, base, Vector3(0.36, 0.85, 0.24), DARK, 0.0)
	_box(_env, base + Vector3(0, 0.8, 0), Vector3(0.56, 0.8, 0.34), coat, 0.0)
	_box(_env, base + Vector3(0, 1.58, 0), Vector3(0.26, 0.28, 0.26), Color(0.5, 0.36, 0.3), 0.0)
	_box(_env, base + Vector3(0, 1.8, 0.02), Vector3(0.36, 0.14, 0.38), coat * 0.9, 0.0)


func _building(base: Vector3, size: Vector3, rng: RandomNumberGenerator, lit_ratio: float) -> void:
	_box(_env, base, size, Color(0.16, 0.16, 0.2), 0.0)
	var rows := int(size.y / 4.0)
	var cols := int(size.x / 4.0)
	for r in rows:
		for c in cols:
			if rng.randf() < lit_ratio * 0.4:
				var p := base + Vector3(-size.x * 0.5 + 2.0 + c * 4.0, 1.5 + r * 4.0, size.z * 0.5 + 0.05)
				_glow_box(p, Vector3(1.4, 1.6, 0.05), WARM if rng.randf() < 0.7 else Color(0.7, 0.85, 1.0), 0.9)


## Paroi en pente, de `top` à `bottom` (écarts en x et y), sur toute la longueur.
func _slope(top: Vector3, bottom: Vector3, length: float, color: Color) -> void:
	var p := [Vector3(top.x, top.y, -length), Vector3(bottom.x, bottom.y, -length),
			Vector3(bottom.x, bottom.y, 0.0), Vector3(top.x, top.y, 0.0)]
	_quad(_env, p, color, 0.0)
	# Les joints du béton, en bandes sombres.
	for k in 8:
		var t := (k + 1) / 9.0
		var a := top.lerp(bottom, t)
		_quad(_env, [Vector3(a.x, a.y, -length), Vector3(a.x + 0.6, a.y - 0.8, -length),
				Vector3(a.x + 0.6, a.y - 0.8, 0.0), Vector3(a.x, a.y, 0.0)], color * 0.7, 0.0)


func _cone_hill(base: Vector3, radius: float, height: float, color: Color) -> void:
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := base + Vector3(cos(a0) * 10.0, height, sin(a0) * 10.0)
		var t1 := base + Vector3(cos(a1) * 10.0, height, sin(a1) * 10.0)
		_quad(_env, [p0, p1, t1, t0], color * (0.85 + 0.15 * sin(a0 * 3.0)), 0.0)
	_plane(_env, base.x - 10.0, base.x + 10.0, base.z + 10.0, base.z - 10.0, base.y + height, color, 0.0)


func _dome(center: Vector3, radius: float, color: Color) -> void:
	var n := 16
	var m := 6
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for j in m:
			var e0 := PI * 0.5 * j / m
			var e1 := PI * 0.5 * (j + 1) / m
			var q := [
				center + Vector3(cos(a0) * cos(e0), sin(e0), sin(a0) * cos(e0)) * radius,
				center + Vector3(cos(a0) * cos(e1), sin(e1), sin(a0) * cos(e1)) * radius,
				center + Vector3(cos(a1) * cos(e1), sin(e1), sin(a1) * cos(e1)) * radius,
				center + Vector3(cos(a1) * cos(e0), sin(e0), sin(a1) * cos(e0)) * radius,
			]
			_quad(_env, [q[0], q[3], q[2], q[1]], color, 0.0)

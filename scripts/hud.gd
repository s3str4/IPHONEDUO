class_name Hud
extends CanvasLayer
## Interface en jeu (résolution interne 270×480) : chrono, score, jauge des
## étapes, multiplicateur, compteur de vitesse, messages flottants, écrans de
## titre et de fin. Polices pixel sans lissage (assets/fonts).

const AMBER := Color(1.0, 0.82, 0.45)
const PINK := Color(1.0, 0.4, 0.6)
const RED := Color(1.0, 0.3, 0.22)
const WHITE := Color(0.95, 0.95, 1.0)
const DIM := Color(0.6, 0.62, 0.72)
const SPEED_SEGMENTS := 14

static var _arcade: FontFile
static var _text: FontFile
static var _text_bold: FontFile

var _time: Label
var _time_caption: Label
var _score: Label
var _stage: Label
var _mult: Label
var _speed: Label
var _speed_bar: Array[ColorRect] = []
var _progress: Array[ColorRect] = []
var _popups: Control
var _play: Control
var _overlay: Control
var _overlay_logo: Control
var _overlay_title: Label
var _overlay_body: Label
var _overlay_hint: Label
var _panel: ColorRect
var _blink := 0.0


static func arcade_font() -> FontFile:
	if _arcade == null:
		_arcade = _pixel_font("res://assets/fonts/PressStart2P.woff")
		_text = _pixel_font("res://assets/fonts/PixelifySans.woff")
		_text_bold = _pixel_font("res://assets/fonts/PixelifySans-Bold.woff")
	return _arcade


static func text_font(bold := false) -> FontFile:
	arcade_font()
	return _text_bold if bold else _text


static func _pixel_font(path: String) -> FontFile:
	var f: FontFile = load(path).duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Bandeaux sombres en dégradé derrière l'interface, en haut et en bas.
	root.add_child(_shade(true))
	root.add_child(_shade(false))

	# Tout ce qui ne sert qu'en course (masqué sur l'écran de titre).
	_play = Control.new()
	_play.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_play)
	_time_caption = _label(_play, "TEMPS", arcade_font(), 8, AMBER, Vector2(0, 6), HORIZONTAL_ALIGNMENT_CENTER, true)
	_time = _label(_play, "88", arcade_font(), 24, AMBER, Vector2(0, 18), HORIZONTAL_ALIGNMENT_CENTER, true)
	_label(_play, "SCORE", arcade_font(), 8, DIM, Vector2(8, 6), HORIZONTAL_ALIGNMENT_LEFT)
	_score = _label(_play, "0", arcade_font(), 8, WHITE, Vector2(8, 19), HORIZONTAL_ALIGNMENT_LEFT)
	_stage = _label(_play, "ÉTAPE 1/5", arcade_font(), 8, DIM, Vector2(-8, 6), HORIZONTAL_ALIGNMENT_RIGHT)
	_mult = _label(_play, "", arcade_font(), 8, AMBER, Vector2(-8, 19), HORIZONTAL_ALIGNMENT_RIGHT)

	# Jauge des étapes : la nuit vers l'aube, une case par étape.
	var seg_w := 30.0
	var gap := 3.0
	var total := RunConfig.SEGMENT_COUNT * seg_w + (RunConfig.SEGMENT_COUNT - 1) * gap
	for i in RunConfig.SEGMENT_COUNT:
		var r := ColorRect.new()
		r.size = Vector2(seg_w, 3)
		r.position = Vector2(135.0 - total * 0.5 + i * (seg_w + gap), 47)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_play.add_child(r)
		_progress.append(r)

	# Compteur : chiffre + barre segmentée.
	_speed = _label(_play, "0", arcade_font(), 16, WHITE, Vector2(0, -46), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	_label(_play, "KM/H", arcade_font(), 8, DIM, Vector2(0, -27), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	for i in SPEED_SEGMENTS:
		var r := ColorRect.new()
		r.size = Vector2(9, 4)
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.position = Vector2(135.0 - SPEED_SEGMENTS * 11 * 0.5 + i * 11 + 1, -12)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_play.add_child(r)
		_speed_bar.append(r)

	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popups)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_panel = ColorRect.new()
	_panel.color = Color(0.02, 0.02, 0.06, 0.78)
	_panel.position = Vector2(18, 150)
	_panel.size = Vector2(234, 200)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_panel)
	var border := ReferenceRect.new()
	border.border_color = AMBER * Color(1, 1, 1, 0.6)
	border.border_width = 1.0
	border.editor_only = false
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(border)
	_overlay_logo = Control.new()
	_overlay_logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_logo)
	_label(_overlay_logo, "ROUTE", arcade_font(), 32, AMBER, Vector2(0, 92), HORIZONTAL_ALIGNMENT_CENTER, true, false, 6)
	_label(_overlay_logo, "DE NUIT", arcade_font(), 24, PINK, Vector2(0, 132), HORIZONTAL_ALIGNMENT_CENTER, true, false, 6)
	_overlay_title = _label(_overlay, "", arcade_font(), 16, AMBER, Vector2(0, 166), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_body = _label(_overlay, "", arcade_font(), 8, WHITE, Vector2(0, 196), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_hint = _label(_overlay, "", arcade_font(), 8, AMBER, Vector2(0, -92), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	_overlay.visible = false


func _process(delta: float) -> void:
	_blink += delta
	if _overlay.visible:
		_overlay_hint.visible = fmod(_blink, 1.0) < 0.65


func set_values(time_left: float, score: float, stage: int, multiplier: float, speed_kmh: float,
		progress: float = 0.0) -> void:
	_time.text = str(int(ceil(time_left)))
	var low := time_left < 10.0
	var col := RED if low else AMBER
	_time_caption.label_settings.font_color = col
	_time.label_settings.font_color = WHITE if low and fmod(_blink, 0.5) < 0.2 else col
	_score.text = _group(int(score))
	_stage.text = "ÉTAPE %d/%d" % [stage + 1, RunConfig.SEGMENT_COUNT]
	_mult.text = "x%.2f" % multiplier if multiplier > 1.0 else ""
	_speed.text = str(int(round(speed_kmh)))
	var lit := int(round(speed_kmh / (CarPhysics.TOP_SPEED * 3.6) * SPEED_SEGMENTS))
	for i in SPEED_SEGMENTS:
		var t := float(i) / (SPEED_SEGMENTS - 1)
		var on := Color(0.35, 0.9, 0.6).lerp(AMBER, smoothstep(0.3, 0.7, t)).lerp(RED, smoothstep(0.75, 1.0, t))
		_speed_bar[i].color = on if i < lit else Color(1, 1, 1, 0.12)
	# Jauge des étapes : de la couleur de la nuit à celle de l'aube.
	for i in _progress.size():
		var fill := clampf(progress * RunConfig.SEGMENT_COUNT - i, 0.0, 1.0)
		var dawn_col := Color(0.35, 0.45, 0.95).lerp(PINK, float(i) / (_progress.size() - 1))
		_progress[i].color = dawn_col if fill >= 1.0 else (dawn_col * Color(1, 1, 1, 0.35 + 0.5 * fill))


## Message flottant qui monte et s'efface.
func popup(text: String, color: Color = AMBER, size: int = 16, y: float = 170.0) -> void:
	var font := arcade_font()
	var l := _label(_popups, text, font, size, color, Vector2(0, y), HORIZONTAL_ALIGNMENT_CENTER, true)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", y - 40.0, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


## Écran de titre (logo, pas de panneau) ou de fin (titre et panneau).
func show_overlay(title: String, body: String, hint: String, logo := false) -> void:
	_overlay.visible = true
	_overlay_logo.visible = logo
	_play.visible = not logo
	_panel.visible = not logo
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay_body.position.y = 300.0 if logo else 198.0
	_overlay_hint.text = hint
	_blink = 0.0


func hide_overlay() -> void:
	_overlay.visible = false
	_play.visible = true


func _shade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0.02, 0.7 if top else 0.0))
	g.set_color(1, Color(0, 0, 0.02, 0.0 if top else 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = 1.0
	if top:
		r.offset_bottom = 64.0
	else:
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.offset_top = -70.0
	return r


func _label(parent: Control, text: String, font: Font, size: int, color: Color, pos: Vector2,
		align: HorizontalAlignment, full_width := false, from_bottom := false, outline := -1) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline if outline >= 0 else maxi(2, size / 6)
	ls.outline_color = Color(0.02, 0.0, 0.05, 0.95)
	ls.shadow_size = 0
	ls.line_spacing = 4.0
	l.label_settings = ls
	if full_width:
		l.anchor_left = 0.0
		l.anchor_right = 1.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		l.anchor_left = 1.0
		l.anchor_right = 1.0
		l.offset_left = -160.0 + pos.x
		l.offset_right = pos.x
	else:
		l.offset_left = pos.x
		l.offset_right = pos.x + 160.0
	if from_bottom:
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
	l.offset_top = pos.y
	l.offset_bottom = pos.y + size * 1.6
	parent.add_child(l)
	return l


static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

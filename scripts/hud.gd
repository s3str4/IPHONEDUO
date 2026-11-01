class_name Hud
extends CanvasLayer
## Interface en jeu (résolution interne 270×480) : chrono, score, étape,
## multiplicateur, vitesse, messages flottants, écrans de titre et de fin.

const AMBER := Color(1.0, 0.82, 0.45)
const RED := Color(1.0, 0.3, 0.22)
const WHITE := Color(0.95, 0.95, 1.0)

var _time: Label
var _time_caption: Label
var _score: Label
var _stage: Label
var _mult: Label
var _speed: Label
var _popups: Control
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _overlay_hint: Label
var _blink := 0.0


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_time_caption = _label(root, "TEMPS", 9, AMBER, Vector2(0, 6), HORIZONTAL_ALIGNMENT_CENTER, true)
	_time = _label(root, "88", 34, AMBER, Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER, true)
	_label(root, "SCORE", 9, WHITE, Vector2(8, 6), HORIZONTAL_ALIGNMENT_LEFT)
	_score = _label(root, "0", 14, WHITE, Vector2(8, 16), HORIZONTAL_ALIGNMENT_LEFT)
	_stage = _label(root, "ÉTAPE 1/5", 9, WHITE, Vector2(-8, 6), HORIZONTAL_ALIGNMENT_RIGHT)
	_mult = _label(root, "", 14, AMBER, Vector2(-8, 16), HORIZONTAL_ALIGNMENT_RIGHT)
	_speed = _label(root, "0 km/h", 20, AMBER, Vector2(0, -44), HORIZONTAL_ALIGNMENT_CENTER, true, true)

	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popups)

	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.0, 0.0, 0.03, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_overlay_title = _label(_overlay, "", 26, AMBER, Vector2(0, 120), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_body = _label(_overlay, "", 11, WHITE, Vector2(0, 175), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_hint = _label(_overlay, "", 11, AMBER, Vector2(0, 380), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay.visible = false


func _process(delta: float) -> void:
	_blink += delta
	if _overlay.visible:
		_overlay_hint.visible = fmod(_blink, 1.0) < 0.65


func set_values(time_left: float, score: float, stage: int, multiplier: float, speed_kmh: float) -> void:
	_time.text = str(int(ceil(time_left)))
	var low := time_left < 10.0
	var col := RED if low else AMBER
	_time_caption.label_settings.font_color = col
	_time.label_settings.font_color = WHITE if low and fmod(_blink, 0.5) < 0.2 else col
	_score.text = _group(int(score))
	_stage.text = "ÉTAPE %d/%d" % [stage + 1, RunConfig.SEGMENT_COUNT]
	_mult.text = "×%.2f" % multiplier if multiplier > 1.0 else ""
	_speed.text = "%d km/h" % int(round(speed_kmh))


## Message flottant qui monte et s'efface.
func popup(text: String, color: Color = AMBER, size: int = 16, y: float = 170.0) -> void:
	var l := _label(_popups, text, size, color, Vector2(0, y), HORIZONTAL_ALIGNMENT_CENTER, true)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", y - 40.0, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func show_overlay(title: String, body: String, hint: String) -> void:
	_overlay.visible = true
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay_hint.text = hint
	_blink = 0.0


func hide_overlay() -> void:
	_overlay.visible = false


func _label(parent: Control, text: String, size: int, color: Color, pos: Vector2,
		align: HorizontalAlignment, full_width := false, from_bottom := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = maxi(2, size / 6)
	ls.outline_color = Color(0, 0, 0, 0.9)
	l.label_settings = ls
	if full_width:
		l.anchor_left = 0.0
		l.anchor_right = 1.0
		l.offset_left = 0.0
		l.offset_right = 0.0
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

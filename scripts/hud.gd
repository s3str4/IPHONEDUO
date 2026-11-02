class_name Hud
extends CanvasLayer
## Interface en jeu (résolution interne 270×480) : chrono, score, jauge des
## étapes, multiplicateur, compteur de vitesse, messages flottants, écrans de
## titre et de fin. Polices néon (assets/fonts) : Audiowide pour les chiffres
## et les titres, Rajdhani pour les textes, Monoton pour le logo.

const AMBER := Color(1.0, 0.82, 0.45)
const PINK := Color(1.0, 0.4, 0.6)
const RED := Color(1.0, 0.3, 0.22)
const WHITE := Color(0.95, 0.95, 1.0)
const DIM := Color(0.6, 0.62, 0.72)
const LOU_BLUE := Color(0.55, 0.82, 1.0)
const SPEED_SEGMENTS := 14

static var _arcade: FontFile
static var _text: FontFile
static var _text_bold: FontFile
static var _logo: FontFile

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
var _radio: Control
var _radio_header: Label
var _radio_text: Label
var _radio_full := ""
var _radio_shown := 0.0
var _radio_hide_at := 0.0
var _fork_left: Label
var _fork_right: Label
var _card: Label
var _hint: Label
var _title_button: Button
var _share_button: Button
var _turbo_back: ColorRect
var _turbo_fill: ColorRect
var _turbo_label: Label
## Scène de fin : bandes noires, plus de compteurs.
var _cinema := false
## Poursuite : bandeau, témoins de touches, distance, alerte d'éperonnage.
var _pursuit: Control
var _pursuit_label: Label
var _pursuit_dist: Label
var _pips: Array[ColorRect] = []
var _ram_bar: ColorRect
var _ram_label: Label
var _pursuit_time := 0.0
var _ghost_label: Label
const GHOST_CYAN := Color(0.45, 0.9, 1.0)
const SIREN_RED := Color(1.0, 0.25, 0.22)
const SIREN_BLUE := Color(0.35, 0.55, 1.0)
var _bars: Array[ColorRect] = []
const BAR_H := 46.0
var _paused := false

## Le bouton pause est touché ; une touche pendant la pause demande la reprise.
signal pause_pressed
signal resume_requested
## Boutons de l'écran titre.
signal journal_pressed
signal settings_pressed
signal daily_pressed
signal garage_pressed
## Retour à l'écran titre (fin de partie, pause).
signal title_pressed
signal share_pressed


## Chiffres et titres (Audiowide).
static func arcade_font() -> FontFile:
	if _arcade == null:
		_arcade = load("res://assets/fonts/Audiowide.woff")
		_text = load("res://assets/fonts/Rajdhani-SemiBold.woff")
		_text_bold = load("res://assets/fonts/Rajdhani-Bold.woff")
		_logo = load("res://assets/fonts/Monoton.woff")
	return _arcade


## Textes (Rajdhani).
static func text_font(bold := false) -> FontFile:
	arcade_font()
	return _text_bold if bold else _text


## Logo (Monoton, tubes de néon).
static func logo_font() -> FontFile:
	arcade_font()
	return _logo


func _ready() -> void:
	layer = 2
	# L'interface continue de vivre pendant la pause (c'est elle qui la lève).
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Bandeaux sombres en dégradé derrière l'interface, en haut et en bas.
	root.add_child(_shade(true))
	root.add_child(_shade(false))

	# Bandes du plan de cinéma (scènes de fin), repliées hors écran.
	# Ancrées aux vrais bords : sur un écran plus allongé que 270 × 480 (iPhone
	# en plein écran), une bande placée « sous » y = 480 restait visible.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = -BAR_H if top else 0.0
		bar.offset_bottom = 0.0 if top else BAR_H
		root.add_child(bar)
		_bars.append(bar)

	# Tout ce qui ne sert qu'en course (masqué sur l'écran de titre).
	_play = Control.new()
	_play.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_play)
	_time_caption = _label(_play, "TEMPS", text_font(true), 10, AMBER, Vector2(0, 4), HORIZONTAL_ALIGNMENT_CENTER, true)
	_time = _label(_play, "88", arcade_font(), 26, AMBER, Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER, true)
	_label(_play, "SCORE", text_font(true), 10, DIM, Vector2(8, 4), HORIZONTAL_ALIGNMENT_LEFT)
	_score = _label(_play, "0", arcade_font(), 10, WHITE, Vector2(8, 17), HORIZONTAL_ALIGNMENT_LEFT)
	_ghost_label = _label(_play, "", text_font(true), 9, GHOST_CYAN, Vector2(8, 32), HORIZONTAL_ALIGNMENT_LEFT)
	_stage = _label(_play, "ÉTAPE 1/5", text_font(true), 10, DIM, Vector2(-8, 4), HORIZONTAL_ALIGNMENT_RIGHT)
	_mult = _label(_play, "", arcade_font(), 10, AMBER, Vector2(-8, 17), HORIZONTAL_ALIGNMENT_RIGHT)

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
	_speed = _label(_play, "0", arcade_font(), 22, WHITE, Vector2(0, -52), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	_label(_play, "KM/H", text_font(true), 10, DIM, Vector2(0, -28), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	for i in SPEED_SEGMENTS:
		var r := ColorRect.new()
		r.size = Vector2(9, 4)
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.position = Vector2(135.0 - SPEED_SEGMENTS * 11 * 0.5 + i * 11 + 1, -12)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_play.add_child(r)
		_speed_bar.append(r)

	# Jauge du turbo : barre verticale à droite du compteur.
	_turbo_back = ColorRect.new()
	_turbo_back.color = Color(1, 1, 1, 0.12)
	_turbo_back.anchor_top = 1.0
	_turbo_back.anchor_bottom = 1.0
	_turbo_back.position = Vector2(222, -60)
	_turbo_back.size = Vector2(7, 48)
	_turbo_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play.add_child(_turbo_back)
	_turbo_fill = ColorRect.new()
	_turbo_fill.color = PINK
	_turbo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turbo_back.add_child(_turbo_fill)
	# Poursuite.
	_pursuit = Control.new()
	_pursuit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pursuit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pursuit.visible = false
	_play.add_child(_pursuit)
	_pursuit_label = _label(_pursuit, "POURSUITE", arcade_font(), 11, SIREN_RED, Vector2(0, 56), HORIZONTAL_ALIGNMENT_CENTER, true)
	for i in Police.STRIKES_TO_BUST:
		var pip := ColorRect.new()
		pip.size = Vector2(14, 4)
		pip.position = Vector2(135.0 - 25.0 + i * 18.0, 76)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pursuit.add_child(pip)
		_pips.append(pip)
	_pursuit_dist = _label(_pursuit, "", text_font(true), 9, DIM, Vector2(0, 82), HORIZONTAL_ALIGNMENT_CENTER, true)
	_ram_bar = ColorRect.new()
	_ram_bar.size = Vector2(70, 5)
	_ram_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ram_bar.visible = false
	_play.add_child(_ram_bar)
	_ram_label = _label(_play, "ELLE CHARGE", text_font(true), 9, WHITE, Vector2(0, 0), HORIZONTAL_ALIGNMENT_CENTER)
	_ram_label.visible = false
	_turbo_label = _label(_play, "TURBO", text_font(true), 8, PINK, Vector2(203, -10), HORIZONTAL_ALIGNMENT_LEFT, false, true)

	# Directions à la prochaine bifurcation.
	_fork_left = _label(_play, "", text_font(true), 11, Scenery.LEFT_SIGN.lightened(0.45), Vector2(8, 56), HORIZONTAL_ALIGNMENT_LEFT)
	_fork_right = _label(_play, "", text_font(true), 11, Scenery.RIGHT_SIGN.lightened(0.5), Vector2(-8, 56), HORIZONTAL_ALIGNMENT_RIGHT)
	_fork_right.offset_left = -200.0
	_fork_left.offset_right = 200.0

	# Radio Nuit : bandeau au-dessus du compteur, texte tapé lettre à lettre.
	_radio = ColorRect.new()
	(_radio as ColorRect).color = Color(0.02, 0.01, 0.06, 0.72)
	_radio.position = Vector2(10, 330)
	_radio.size = Vector2(250, 62)
	_radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play.add_child(_radio)
	_radio_header = _label(_radio, Scenario.STATION, arcade_font(), 8, PINK, Vector2(6, 4), HORIZONTAL_ALIGNMENT_LEFT)
	_radio_header.offset_right = 244.0
	_radio_text = _label(_radio, "", text_font(), 11, WHITE, Vector2(6, 16), HORIZONTAL_ALIGNMENT_LEFT)
	_radio_text.offset_right = 244.0
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_text.label_settings.line_spacing = 3.0
	_radio.visible = false

	# Titre de région (« LA FORÊT ») au centre, qui apparaît puis s'efface.
	_card = _label(_play, "", arcade_font(), 18, WHITE, Vector2(0, 150), HORIZONTAL_ALIGNMENT_CENTER, true, false, 4)
	_card.modulate.a = 0.0

	# Conseils de la première partie, en bas de l'écran.
	_hint = _label(_play, "", text_font(true), 13, WHITE, Vector2(0, 292), HORIZONTAL_ALIGNMENT_CENTER, true)
	_hint.modulate.a = 0.0

	# Bouton pause, discret, sous le score.
	var pause := Button.new()
	pause.text = "II"
	pause.flat = true
	pause.focus_mode = Control.FOCUS_NONE
	pause.position = Vector2(4, 34)
	pause.size = Vector2(30, 26)
	pause.add_theme_font_override("font", arcade_font())
	pause.add_theme_font_size_override("font_size", 11)
	pause.add_theme_color_override("font_color", DIM)
	pause.pressed.connect(func() -> void: pause_pressed.emit())
	_play.add_child(pause)

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
	# Boutons du titre : une touche ailleurs lance la partie.
	var titles := [["CARNET", journal_pressed], ["GARAGE", garage_pressed],
			["NUIT DU JOUR", daily_pressed], ["RÉGLAGES", settings_pressed]]
	for i in titles.size():
		var b := Button.new()
		b.text = Lang.t(titles[i][0])
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(14 + (i % 2) * 124, 404 + (i / 2) * 34)
		b.size = Vector2(118, 28)
		b.add_theme_font_override("font", arcade_font())
		b.add_theme_font_size_override("font_size", 8)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.03, 0.1, 0.85)
		style.border_color = PINK * Color(1, 1, 1, 0.7)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, style)
		var sig: Signal = titles[i][1]
		b.pressed.connect(func() -> void: sig.emit())
		_overlay_logo.add_child(b)
	_label(_overlay_logo, "ROUTE", logo_font(), 40, AMBER, Vector2(0, 80), HORIZONTAL_ALIGNMENT_CENTER, true, false, 0)
	_label(_overlay_logo, "DE NUIT", logo_font(), 30, PINK, Vector2(0, 132), HORIZONTAL_ALIGNMENT_CENTER, true, false, 0)
	_overlay_title = _label(_overlay, "", arcade_font(), 18, AMBER, Vector2(0, 166), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_body = _label(_overlay, "", text_font(), 12, WHITE, Vector2(0, 196), HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay_body.offset_left = 26.0
	_overlay_body.offset_right = -26.0
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Sans largeur minimale, reset_size() replie le texte sur une seule lettre de large.
	_overlay_body.custom_minimum_size.x = 218.0
	_overlay_hint = _label(_overlay, "", arcade_font(), 9, AMBER, Vector2(0, -92), HORIZONTAL_ALIGNMENT_CENTER, true, true)
	_title_button = Button.new()
	_title_button.text = Lang.t("TITRE")
	_title_button.focus_mode = Control.FOCUS_NONE
	_title_button.position = Vector2(105, 430)
	_title_button.size = Vector2(60, 24)
	_title_button.add_theme_font_override("font", arcade_font())
	_title_button.add_theme_font_size_override("font_size", 8)
	_title_button.flat = true
	_title_button.add_theme_color_override("font_color", DIM)
	_title_button.pressed.connect(func() -> void: title_pressed.emit())
	_overlay.add_child(_title_button)
	_share_button = _title_button.duplicate()
	_share_button.text = Lang.t("PARTAGER")
	_share_button.add_theme_color_override("font_color", AMBER)
	_share_button.position = Vector2(55, 430)
	_share_button.size = Vector2(80, 24)
	_share_button.visible = false
	_share_button.pressed.connect(func() -> void: share_pressed.emit())
	_overlay.add_child(_share_button)
	_overlay.visible = false


func _process(delta: float) -> void:
	_blink += delta
	if _overlay.visible:
		_overlay_hint.visible = fmod(_blink, 1.0) < 0.65
	if _radio.visible:
		_radio_shown = minf(_radio_shown + delta * 38.0, _radio_full.length())
		_radio_text.text = _radio_full.substr(0, int(_radio_shown))
		_radio_hide_at -= delta
		if _radio_hide_at <= 0.0:
			_radio.visible = false
	if _overlay.visible and _overlay_body.visible_ratio < 1.0:
		_overlay_body.visible_ratio = minf(1.0, _overlay_body.visible_ratio + delta * 38.0 / maxf(1.0, _overlay_body.text.length()))


## Une réplique de Radio Nuit, tapée lettre à lettre puis effacée.
func radio(text: String, header: String = Scenario.STATION) -> void:
	# Radio Nuit en rose ; les messages de Lou en bleu, comme un écran de téléphone.
	_radio_header.text = Lang.t(header)
	_radio_header.label_settings.font_color = PINK if header == Scenario.STATION else LOU_BLUE
	_radio_full = Lang.t(text)
	_radio_shown = 0.0
	_radio_text.text = ""
	_radio.visible = true
	_radio_hide_at = text.length() / 38.0 + 4.0


func radio_busy() -> bool:
	return _radio.visible


## Directions de la prochaine bifurcation (vide : rien à afficher).
func fork_prompt(left: String, right: String) -> void:
	_fork_left.text = ("< " + Lang.t(left)) if left != "" else ""
	_fork_right.text = (Lang.t(right) + " >") if right != "" else ""
	var on := fmod(_blink, 0.8) < 0.55
	_fork_left.visible = on
	_fork_right.visible = on


## Titre de la région où l'on entre.
func title_card(text: String) -> void:
	_card.text = Lang.t(text)
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.4)
	tw.tween_interval(2.2)
	tw.tween_property(_card, "modulate:a", 0.0, 0.8)


## Écart avec le fantôme du record (vide : rien) ; cyan devant, rouge derrière.
func set_ghost(text: String, ahead: bool) -> void:
	_ghost_label.text = text
	_ghost_label.label_settings.font_color = GHOST_CYAN if ahead else RED


## Poursuite : gap (m, positif derrière vous), touches reçues, et pendant
## l'éperonnage, le côté visé (-1 gauche, 0 votre voie, 1 droite).
func set_pursuit(on: bool, strikes: int, gap: float, ram_side: int, delta: float) -> void:
	_pursuit.visible = on
	_pursuit_time += delta
	var red := PoliceView.red_on(_pursuit_time)
	_pursuit_label.label_settings.font_color = SIREN_RED if red else SIREN_BLUE
	for i in _pips.size():
		_pips[i].color = SIREN_RED if i < strikes else Color(1, 1, 1, 0.18)
	_pursuit_dist.text = Lang.t("%d M DERRIÈRE") % int(gap) if gap >= 0.0 else Lang.t("DEVANT VOUS")
	var charging := on and ram_side != 99
	_ram_bar.visible = charging and fmod(_pursuit_time, 0.24) < 0.16
	_ram_label.visible = charging
	if charging:
		var cx := 135.0 + ram_side * 80.0
		_ram_bar.position = Vector2(cx - 35.0, 384.0)
		_ram_bar.color = SIREN_RED if red else SIREN_BLUE
		_ram_label.position = Vector2(cx - 50.0, 368.0)
		_ram_label.size.x = 100.0


## Jauge du turbo (0..1) ; elle clignote quand elle est pleine, et se vide
## pendant le turbo (boosting : part restante).
func set_turbo(charge: float, boosting: float) -> void:
	var fill := boosting if boosting > 0.0 else charge
	_turbo_fill.size = Vector2(7, 48 * fill)
	_turbo_fill.position = Vector2(0, 48 * (1.0 - fill))
	var full := charge >= 1.0 and fmod(_blink, 0.5) < 0.3
	_turbo_fill.color = WHITE if full or boosting > 0.0 else PINK
	_turbo_label.modulate.a = 1.0 if charge >= 1.0 or boosting > 0.0 else 0.55


func set_values(time_left: float, score: float, stage: int, multiplier: float, speed_kmh: float,
		progress: float = 0.0) -> void:
	_time.text = str(int(ceil(time_left)))
	var low := time_left < 10.0
	var col := RED if low else AMBER
	_time_caption.label_settings.font_color = col
	_time.label_settings.font_color = WHITE if low and fmod(_blink, 0.5) < 0.2 else col
	_score.text = _group(int(score))
	_stage.text = Lang.t("ÉTAPE %d/%d") % [stage + 1, RunConfig.SEGMENT_COUNT]
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
## Hauteur maximale du texte d'un écran de fin (le panneau s'arrête au-dessus du conseil).
const OVERLAY_BODY_MAX := 268.0


func show_overlay(title: String, body: String, hint: String, logo := false) -> void:
	_overlay.visible = true
	_overlay_logo.visible = logo
	_title_button.visible = not logo
	_play.visible = not logo and not _cinema
	_panel.visible = not logo
	_overlay_title.text = Lang.t(title)
	_overlay_body.text = Lang.t(body)
	_overlay_body.position.y = 300.0 if logo else 198.0
	# Les fins se dévoilent lettre à lettre, comme la radio.
	_overlay_body.visible_ratio = 1.0 if logo else 0.0
	if not logo:
		_radio.visible = false
		# Le texte doit tenir entre le haut de l'écran et « TOUCHE POUR REJOUER » :
		# s'il est long (fin, message de Lou, scores), la police rapetisse.
		var body_h := 0.0
		for size in [12, 11, 10, 9]:
			_overlay_body.label_settings.font_size = size
			_overlay_body.reset_size()
			# (get_line_count() ne compte que les lignes déjà dévoilées : 1 ici.)
			body_h = _overlay_body.size.y
			if body_h <= OVERLAY_BODY_MAX:
				break
		_panel.size.y = clampf(body_h + 66.0, 200.0, OVERLAY_BODY_MAX + 66.0)
		_panel.position.y = clampf(260.0 - _panel.size.y * 0.5, 44.0, minf(150.0, 380.0 - _panel.size.y))
		_overlay_title.position.y = _panel.position.y + 16.0
		_overlay_body.position.y = _panel.position.y + 48.0
	_overlay_hint.text = Lang.t(hint)
	_blink = 0.0


## Conseil affiché quelques secondes (première partie).
func hint(text: String) -> void:
	_hint.text = Lang.t(text)
	var tw := create_tween()
	tw.tween_property(_hint, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.2)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.6)


## Bouton PARTAGER de l'écran de fin (quand la carte est prête).
func show_share(on: bool) -> void:
	_share_button.visible = on
	_title_button.position.x = 145.0 if on else 105.0


func show_pause(on: bool) -> void:
	_paused = on
	if on:
		show_overlay("PAUSE", "", "TOUCHE POUR REPRENDRE")
		_play.visible = true
	else:
		hide_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if _paused and event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		resume_requested.emit()


## Plan de cinéma : les compteurs s'effacent, deux bandes noires entrent.
func cinema(on: bool) -> void:
	_cinema = on
	_play.visible = not on
	var tw := create_tween().set_parallel()
	var d := BAR_H if on else 0.0
	for p in [["offset_top", -BAR_H + d, 0], ["offset_bottom", d, 0], ["offset_top", -d, 1], ["offset_bottom", BAR_H - d, 1]]:
		tw.tween_property(_bars[p[2]], p[0], p[1], 1.2).set_trans(Tween.TRANS_SINE)


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
	l.text = Lang.t(text)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline if outline >= 0 else 1
	ls.outline_color = Color(0.02, 0.0, 0.05, 0.9)
	# Lueur de néon : une ombre floue de la couleur du texte, sans décalage.
	ls.shadow_size = maxi(3, size / 3)
	ls.shadow_color = Color(color.r, color.g, color.b, 0.4)
	ls.shadow_offset = Vector2.ZERO
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
	return Lang.group(n)

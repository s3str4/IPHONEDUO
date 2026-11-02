class_name Menus
extends CanvasLayer
## Écrans ouverts depuis le titre : le carnet de route (fins, messages de Lou,
## événements, voitures, records), le garage (améliorations et options, la
## voiture visible au-dessus) et les réglages (volumes, sensibilité du pouce,
## qualité graphique). Tout est construit par code, en coordonnées
## d'interface 270 × 480.

signal closed
signal settings_changed
signal color_chosen(index: int)
signal garage_changed

const EVENT_NAMES := {
	"stoppeuse": "L'auto-stoppeuse", "radio_live": "La radio parle de toi",
	"panneau": "Le panneau qui se répète", "station_vide": "La station vide",
	"fantome": "La voiture fantôme", "tunnel": "Le tunnel trop long",
}
const ENDING_HINTS := ["toujours à gauche", "une fois à droite", "deux fois à droite",
		"trois fois à droite", "toujours à droite"]

var save: SaveData
## Écran ouvert : "", "carnet", "garage" ou "reglages".
var current := ""
var _root: Control
var _bg: ColorRect
var _scroll: ScrollContainer
var _content: VBoxContainer


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.015, 0.05, 0.96)
	_root.add_child(_bg)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(236, 0)
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)
	_layout(false)
	var back := _button("RETOUR", Vector2(85, 440), Vector2(100, 28))
	back.pressed.connect(close)
	_root.add_child(back)
	_root.visible = false


func close() -> void:
	_root.visible = false
	current = ""
	closed.emit()


func is_open() -> bool:
	return _root.visible


# --- Carnet de route --------------------------------------------------------------

## Plein écran, ou moitié basse seulement (garage : la voiture reste visible).
func _layout(lower_half: bool) -> void:
	var top := 214.0 if lower_half else 0.0
	_bg.position = Vector2(0, top)
	_bg.size = Vector2(270, 480 - top)
	_scroll.position = Vector2(14, top + 12)
	_scroll.size = Vector2(242, 420 - top)


func open_journal() -> void:
	current = "carnet"
	_layout(false)
	_clear()
	_title("CARNET DE ROUTE")
	_heading("FINS  %d / %d" % [save.endings.size(), RouteMap.ENDINGS.size()])
	for e in RouteMap.ENDINGS.size():
		if save.endings.has(e):
			_text("%s  —  record %s" % [RouteMap.ENDINGS[e], Hud._group(int(save.endings[e]))], Hud.AMBER, true)
			_text(Scenario.ENDINGS[e][1].get_slice(".", 0) + ".", Hud.DIM)
		else:
			_text("???  —  %s" % ENDING_HINTS[e], Hud.DIM, true)
	var total := 0
	for stage in RouteMap.STAGES:
		total += stage.size()
	_heading("MESSAGES DE LOU  %d / %d" % [save.messages.size(), total])
	for stage in RouteMap.STAGES:
		for id in stage:
			_text(RouteMap.THEMES[id]["name"], Hud.LOU_BLUE if save.messages.has(id) else Hud.DIM, true)
			_text("« %s »" % Scenario.LOU[id] if save.messages.has(id) else "— pas encore écouté —",
					Hud.WHITE if save.messages.has(id) else Hud.DIM)
	_heading("ÉVÉNEMENTS  %d / %d" % [save.events_seen.size(), EVENT_NAMES.size()])
	for key in EVENT_NAMES:
		_text((EVENT_NAMES[key] if save.events_seen.has(key) else "???  —  pas encore vu"),
				Hud.WHITE if save.events_seen.has(key) else Hud.DIM)
	_heading("VOITURE")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var unlocked := save.unlocked_colors()
	for i in CarView.PAINTS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 26)
		b.focus_mode = Control.FOCUS_NONE
		var paint: Array = CarView.PAINTS[i]
		var style := StyleBoxFlat.new()
		style.bg_color = paint[1] if i in unlocked else Color(0.12, 0.12, 0.14)
		style.border_color = Hud.WHITE if i == save.car_color else Color(0, 0, 0, 0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.text = "" if i in unlocked else "?"
		b.disabled = not i in unlocked
		b.pressed.connect(func() -> void:
			save.car_color = i
			color_chosen.emit(i)
			open_journal())
		row.add_child(b)
	_content.add_child(row)
	_text(CarView.PAINTS[save.car_color][0] + "  —  chaque fin débloque une teinte", Hud.DIM)
	_heading("RECORDS")
	_text("Meilleur score : %s" % Hud._group(save.best), Hud.WHITE)
	_text("Nuit du jour : %s" % Hud._group(int(save.daily.get(Main.today(), 0))), Hud.WHITE)
	_text("Parties jouées : %d" % save.runs, Hud.DIM)
	_root.visible = true


# --- Réglages --------------------------------------------------------------------

func open_settings() -> void:
	current = "reglages"
	_layout(false)
	_clear()
	_title("RÉGLAGES")
	_slider("MUSIQUE", save.music_volume, 0.0, 1.0, func(v: float) -> void: save.music_volume = v)
	_slider("EFFETS", save.sfx_volume, 0.0, 1.0, func(v: float) -> void: save.sfx_volume = v)
	_slider("SENSIBILITÉ DU POUCE", save.sensitivity, 0.7, 1.4, func(v: float) -> void: save.sensitivity = v)
	_heading("QUALITÉ GRAPHIQUE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for q in 3:
		var b := _button(["SOBRE", "NORMALE", "HAUTE"][q], Vector2.ZERO, Vector2(74, 26))
		b.modulate = Hud.AMBER if save.quality == q else Hud.DIM
		b.pressed.connect(func() -> void:
			save.quality = q
			settings_changed.emit()
			open_settings())
		row.add_child(b)
	_content.add_child(row)
	_text("Sobre : sans reflet de la route, pour les iPhone plus anciens.", Hud.DIM)
	_root.visible = true


# --- Garage --------------------------------------------------------------------

func open_garage() -> void:
	current = "garage"
	_layout(true)
	_clear()
	_title("GARAGE")
	_text("CRÉDITS  %s   —   1 crédit tous les 100 points" % Hud._group(save.credits), Hud.AMBER, true)
	for key in Garage.UPGRADES:
		var info: Array = Garage.UPGRADES[key]
		var level: int = save.upgrades[key]
		_heading("%s  —  NIVEAU %d/%d" % [info[0], level, Garage.MAX_LEVEL])
		_text(info[1], Hud.DIM)
		if level < Garage.MAX_LEVEL:
			var price: int = Garage.PRICES[level]
			var b := _button("AMÉLIORER — %s" % Hud._group(price), Vector2.ZERO, Vector2(230, 26))
			b.disabled = save.credits < price
			b.modulate = Hud.WHITE if save.credits >= price else Hud.DIM
			b.pressed.connect(func() -> void:
				if save.buy_upgrade(key):
					garage_changed.emit()
				open_garage())
			_content.add_child(b)
	_heading("OPTIONS")
	for key in Garage.OPTIONS:
		var name: String = Garage.OPTIONS[key][0]
		var price: int = Garage.OPTIONS[key][1]
		var label: String
		if save.owned.has(key):
			label = "%s : %s" % [name, "OUI" if _option_on(key) else "NON"]
		else:
			label = "%s — %s" % [name, Hud._group(price)]
		var b := _button(label, Vector2.ZERO, Vector2(230, 26))
		b.disabled = not save.owned.has(key) and save.credits < price
		b.modulate = Hud.WHITE if not b.disabled else Hud.DIM
		b.pressed.connect(func() -> void:
			if save.owned.has(key):
				_toggle_option(key)
			else:
				save.buy_option(key)
			garage_changed.emit()
			open_garage())
		_content.add_child(b)
	if save.owned.has("neon"):
		var nb := _button("COULEUR DU NÉON", Vector2.ZERO, Vector2(230, 26))
		nb.modulate = Garage.NEON_COLORS[save.neon_color]
		nb.pressed.connect(func() -> void:
			save.neon_color = (save.neon_color + 1) % Garage.NEON_COLORS.size()
			garage_changed.emit()
			open_garage())
		_content.add_child(nb)
	_root.visible = true


func _option_on(key: String) -> bool:
	match key:
		"aileron":
			return save.spoiler_on
		"neon":
			return save.neon_on
	return true


func _toggle_option(key: String) -> void:
	match key:
		"aileron":
			save.spoiler_on = not save.spoiler_on
		"neon":
			save.neon_on = not save.neon_on


# --- Briques --------------------------------------------------------------------

func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()


func _title(text: String) -> void:
	var l := _text(text, Hud.AMBER, false, Hud.arcade_font(), 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _heading(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_content.add_child(spacer)
	_text(text, Hud.PINK, false, Hud.arcade_font(), 9)


func _text(text: String, color: Color, bold := false, font: Font = null, size := 11) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(236, 0)
	var ls := LabelSettings.new()
	ls.font = font if font != null else Hud.text_font(bold)
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	_content.add_child(l)
	return l


func _slider(label: String, value: float, lo: float, hi: float, setter: Callable) -> void:
	_heading(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(230, 22)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		settings_changed.emit())
	_content.add_child(s)


func _button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Hud.arcade_font())
	b.add_theme_font_size_override("font_size", 9)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.12, 0.9)
	style.border_color = Hud.AMBER * Color(1, 1, 1, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, style)
	return b

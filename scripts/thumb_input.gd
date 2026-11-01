class_name ThumbInput
extends Node
## Commande à une main : pouce posé = gaz, glissé = braquage relatif au point
## de contact. Si le pouce dépasse la course, l'ancre le suit : pas besoin de
## revenir pile au point de départ pour remettre les roues droites.
## Sur PC : la souris (émulée en toucher) ou les flèches / Q-D et Espace.

## Course du pouce pour braquer à fond, en fraction de la largeur d'écran.
@export_range(0.05, 0.5) var steer_range := 0.16
## Zone morte au centre, en fraction de la course.
@export_range(0.0, 0.5) var dead_zone := 0.08

var throttle := 0.0
var steer := 0.0

var _touch_index := -1
var _anchor_x := 0.0
var _touch_x := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_anchor_x = event.position.x
			_touch_x = event.position.x
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch_x = event.position.x


func _process(_delta: float) -> void:
	if _touch_index != -1:
		var width := get_viewport().get_visible_rect().size.x
		var course := maxf(1.0, width * steer_range)
		var dx := _touch_x - _anchor_x
		if absf(dx) > course:
			_anchor_x = _touch_x - signf(dx) * course
			dx = signf(dx) * course
		var r := dx / course
		steer = signf(r) * clampf((absf(r) - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
		throttle = 1.0
		return
	# Clavier (tests sur PC).
	var k_steer := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		k_steer -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		k_steer += 1.0
	var k_gas := Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SPACE) \
			or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W)
	steer = k_steer
	throttle = 1.0 if k_gas else 0.0

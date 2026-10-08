class_name UiCard
extends Control
## The web build's .card: a framed panel over a blurred backdrop that scrolls when its
## content is taller than the screen (drag, wheel, or follow the focused item), rises
## into place as its screen comes in, and leans a little on the Score.

const SHADOW_MARGIN := 160.0

## Content blocks go here, laid out from (0, 0) at the content width.
var content := Control.new()
var pad := Vector2(22, 14)
var scroll := 0.0
var max_scroll := 0.0
## True once a press has moved far enough to scroll; the pressed item then ignores it.
var dragged := false
## The card's resting position; the entrance offset is added to it.
var home := Vector2.ZERO
## 0..1 entrance (CSS translateY(14px) scale(0.985) to none, 0.45 s).
var rise := 0.0
var rising := false
var px_scale := 2.0

var _bg := Control.new()
var _clip := Control.new()
var _mat := ShaderMaterial.new()
var _press_y := 0.0
var _press_scroll := 0.0
var _pressing := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mat.shader = UiStyle.card_shader
	_bg.material = _mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(func() -> void: _bg.draw_rect(Rect2(Vector2.ZERO, _bg.size), Color.WHITE))
	add_child(_bg)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(content)


## Places the card: `rect` is its border box; `content_h` the full content height.
func place(rect: Rect2, content_h: float) -> void:
	home = rect.position
	size = rect.size
	pivot_offset = rect.size / 2.0
	_bg.position = -Vector2.ONE * SHADOW_MARGIN
	_bg.size = rect.size + Vector2.ONE * SHADOW_MARGIN * 2.0
	_clip.position = Vector2.ONE
	_clip.size = rect.size - Vector2(2, 2)
	max_scroll = maxf(0.0, content_h + pad.y * 2.0 - _clip.size.y)
	scroll = clampf(scroll, 0.0, max_scroll)
	content.size = Vector2(rect.size.x - 2.0 - pad.x * 2.0, content_h)
	_apply()


func _apply() -> void:
	content.position = Vector2(pad.x, pad.y - scroll)
	var e := UiStyle.ease(rise)
	position = home + Vector2(0, 14.0 * (1.0 - e))
	scale = Vector2.ONE * (1.0 - 0.015 * (1.0 - e) * UiStyle.k)
	rotation = deg_to_rad(-0.4) * (1.0 - UiStyle.k)


## Scrolls the least amount that shows `c` (a descendant of content), like scrollIntoView.
func reveal(c: Control) -> void:
	if max_scroll <= 0.0:
		return
	var top := c.get_global_rect().position.y - content.get_global_rect().position.y
	var bottom := top + c.size.y
	var view_h := _clip.size.y
	if pad.y + top - scroll < 0.0:
		scroll = pad.y + top
	elif pad.y + bottom - scroll > view_h:
		scroll = pad.y + bottom - view_h
	scroll = clampf(scroll, 0.0, max_scroll)
	_apply()


func _process(dt: float) -> void:
	var target := 1.0 if rising else 0.0
	if rise != target:
		rise = move_toward(rise, target, dt / 0.45)
	_mat.set_shader_parameter("card_pos", Vector2.ONE * SHADOW_MARGIN)
	_mat.set_shader_parameter("card_size", size)
	_mat.set_shader_parameter("card_color", UiStyle.c("card"))
	_mat.set_shader_parameter("edge_color", UiStyle.c("card_edge"))
	_mat.set_shader_parameter("accent", UiStyle.c("accent"))
	_mat.set_shader_parameter("k", UiStyle.k)
	# CSS backdrop-filter: blur(10px) is a gaussian of 10 px; pick the screen mip that matches.
	_mat.set_shader_parameter("blur_lod", log(10.0 * px_scale) / log(2.0) + 0.3 if UiStyle.blur else 0.0)
	_apply()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pressing = true
				dragged = false
				_press_y = e.global_position.y
				_press_scroll = scroll
			else:
				_pressing = false
		elif e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			scroll = clampf(scroll + (40.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -40.0), 0.0, max_scroll)
			_apply()
		accept_event()
	elif e is InputEventMouseMotion and _pressing:
		var dy: float = e.global_position.y - _press_y
		if absf(dy) > 8.0:
			dragged = true
		if dragged and max_scroll > 0.0:
			scroll = clampf(_press_scroll - dy, 0.0, max_scroll)
			_apply()
		accept_event()

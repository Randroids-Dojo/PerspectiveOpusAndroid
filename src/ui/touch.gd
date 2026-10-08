class_name TouchControls
extends Control
## On-screen controls, a port of the web build's src/ui/touch.ts: a floating stick on
## the left (it appears under the thumb and follows a thumb that drifts too far), the
## round jump button and the world button on the right. Multi-touch by touch index.

signal jumped
signal switched

const R := 52.0
const DEAD := 0.18

var input: InputRouter
var safe := Vector4.ZERO
var mode := "3d"
var shown := false

var _stick_id := -1
var _origin := Vector2.ZERO
## Where the stick rests (18vw, 72vh until first used, then where it was last).
var _stick_at := Vector2(-1, -1)
var _knob := Vector2.ZERO
var _active := false
var _jump_id := -1
var _switch_id := -1
var _page_t := 0.0
var _stage_t := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_controls(v: bool) -> void:
	shown = v
	visible = v
	if not v:
		_reset()


func _reset() -> void:
	_stick_id = -1
	_jump_id = -1
	_switch_id = -1
	_active = false
	_knob = Vector2.ZERO
	if input:
		input.touch_x = 0.0
		input.touch_y = 0.0
		input.touch_jump = false


func jump_rect() -> Rect2:
	var vw := size.x / 100.0
	var vh := size.y / 100.0
	return Rect2(size.x - safe.z - 5.0 * vw - 86.0, size.y - safe.w - 6.0 * vh - 86.0, 86.0, 86.0)


func switch_rect() -> Rect2:
	var vw := size.x / 100.0
	var vh := size.y / 100.0
	return Rect2(size.x - safe.z - 5.0 * vw - 104.0 - 64.0, size.y - safe.w - 6.0 * vh - 34.0 - 64.0, 64.0, 64.0)


func stick_zone() -> Rect2:
	return Rect2(0, size.y * 0.18, size.x * 0.48, size.y * 0.82)


func _stick_center() -> Vector2:
	if _stick_at.x < 0.0:
		return Vector2(size.x * 0.18, size.y * 0.72)
	return _stick_at


func _in_circle(r: Rect2, p: Vector2) -> bool:
	return p.distance_to(r.get_center()) <= r.size.x / 2.0


func _input(e: InputEvent) -> void:
	if not shown:
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed:
			if _jump_id < 0 and _in_circle(jump_rect(), p):
				_jump_id = e.index
				input.touch_jump = true
				input.press_jump()
				jumped.emit()
				get_viewport().set_input_as_handled()
			elif _switch_id < 0 and _in_circle(switch_rect(), p):
				_switch_id = e.index
				input.press_switch()
				switched.emit()
				get_viewport().set_input_as_handled()
			elif _stick_id < 0 and stick_zone().has_point(p):
				_stick_id = e.index
				_origin = p
				_stick_at = p
				_knob = Vector2.ZERO
				_active = true
				get_viewport().set_input_as_handled()
		else:
			if e.index == _jump_id:
				_jump_id = -1
				input.touch_jump = false
			elif e.index == _switch_id:
				_switch_id = -1
			elif e.index == _stick_id:
				_stick_id = -1
				_active = false
				_knob = Vector2.ZERO
				input.touch_x = 0.0
				input.touch_y = 0.0
	elif e is InputEventScreenDrag and e.index == _stick_id:
		_stick_move(e.position)
		get_viewport().set_input_as_handled()


func _stick_move(p: Vector2) -> void:
	var d := p - _origin
	var dist := d.length()
	if dist > R:
		# Let the stick follow a thumb that drifts too far.
		_origin += d / dist * (dist - R)
		_stick_at = _origin
		d = d / dist * R
	_knob = d
	var nx := d.x / R
	var ny := -d.y / R
	input.touch_x = 0.0 if absf(nx) < DEAD else nx
	input.touch_y = 0.0 if absf(ny) < DEAD + 0.12 else ny


func _process(dt: float) -> void:
	var page_target := 1.0 if mode == "2d" else 0.0
	_page_t = move_toward(_page_t, page_target, dt / 0.45)
	_stage_t = move_toward(_stage_t, 1.0 - page_target, dt / 0.45)
	if visible:
		queue_redraw()


func _draw() -> void:
	var fg := UiStyle.c("fg")
	var card := UiStyle.c("card")
	# The stick: a ring with a soft fill, brighter while held.
	var c := _stick_center()
	var op := 0.9 if _active else 0.35
	UiStyle.ellipse(self, c, Vector2(60, 60), [[0.0, UiStyle.fade(card, 0.4 * op)], [0.7, UiStyle.fade(card, 0.0)], [1.0, UiStyle.fade(card, 0.0)]], 32)
	draw_arc(c, 59.25, 0, TAU, 64, UiStyle.fade(fg, 0.35 * op), 1.5, true)
	var kc := c + _knob
	draw_circle(kc, 26.0, UiStyle.fade(fg, 0.3 * op), true, -1.0, true)
	draw_arc(kc, 25.25, 0, TAU, 48, UiStyle.fade(fg, 0.6 * op), 1.5, true)
	_draw_button(jump_rect(), _jump_id >= 0)
	var jr := jump_rect()
	var js := (0.9 if _jump_id >= 0 else 1.0)
	var jsz := Vector2(32, 32) * js
	draw_texture_rect(UiStyle.chevron, Rect2(jr.get_center() - jsz / 2.0, jsz), false, fg)
	_draw_button(switch_rect(), _switch_id >= 0)
	var sr := switch_rect()
	var ss := 0.9 if _switch_id >= 0 else 1.0
	var sc := sr.get_center()
	if _page_t > 0.0:
		var sx := cos(deg_to_rad(80.0) * UiStyle.ease(1.0 - _page_t))
		var pz := Vector2(18, 22) * ss
		# The page icon's sheet fills the 18 by 22 box: draw its 22 view box a little larger.
		var vb := pz * Vector2(22.0 / 12.5, 22.0 / 14.5) * 0.9
		draw_texture_rect(UiStyle.page_icon, Rect2(sc - Vector2(vb.x * sx, vb.y) / 2.0, Vector2(vb.x * sx, vb.y)), false, UiStyle.fade(fg, _page_t))
	if _stage_t > 0.0:
		var k := lerpf(0.3, 1.0, UiStyle.ease(_stage_t)) * ss
		var sz := Vector2(24, 24) * k
		draw_texture_rect(UiStyle.stage_icon, Rect2(sc - sz / 2.0, sz), false, UiStyle.fade(fg, _stage_t))


func _draw_button(r: Rect2, down: bool) -> void:
	var fg := UiStyle.c("fg")
	var fill := UiStyle.fade(UiStyle.c("accent"), 0.35) if down else UiStyle.fade(UiStyle.c("card"), 0.55)
	var rr := r
	if down:
		rr = Rect2(r.get_center() - r.size * 0.45, r.size * 0.9)
	var c := rr.get_center()
	var rad := rr.size.x / 2.0
	draw_circle(c, rad, fill, true, -1.0, true)
	draw_arc(c, rad - 0.75, 0, TAU, 64, UiStyle.fade(fg, 0.55), 1.5, true)

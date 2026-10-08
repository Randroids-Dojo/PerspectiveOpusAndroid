class_name InputRouter
extends Node
## Keyboard, gamepad and touch merged into one action model, like the web build's
## src/core/input.ts. Presses are latched until the simulation reads them, so a tap
## shorter than a frame still counts. Menus listen to `nav`.

signal nav(action: String)
signal device_changed(device: String)

## "keyboard", "gamepad" or "touch".
var device := "touch"
var enabled := true
## Written by the on-screen controls.
var touch_x := 0.0
var touch_y := 0.0
var touch_jump := false

var _keys := {}
var _jump_latch := false
var _switch_latch := false
var _pause_latch := false
var _pad_x := 0.0
var _pad_y := 0.0
var _pad_jump := false
var _axis_prev := Vector2.ZERO

const LEFT := [KEY_LEFT, KEY_A]
const RIGHT := [KEY_RIGHT, KEY_D]
const UP := [KEY_UP, KEY_W]
const DOWN := [KEY_DOWN, KEY_S]
const JUMP := [KEY_SPACE, KEY_K, KEY_Z, KEY_C]
const SWITCH := [KEY_SHIFT, KEY_E, KEY_X, KEY_L, KEY_Q]
const PAUSE := [KEY_ESCAPE, KEY_P]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("mobile"):
		device = "keyboard"


func _set_device(d: String) -> void:
	if device == d:
		return
	device = d
	device_changed.emit(d)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_device("touch")
	elif event is InputEventKey:
		var k: int = event.physical_keycode
		if k == 0:
			k = event.keycode
		if event.pressed:
			if event.keycode != KEY_BACK:
				_set_device("keyboard")
			_keys[k] = true
			if not event.echo:
				if k in JUMP:
					_jump_latch = true
				if k in SWITCH:
					_switch_latch = true
				if k in PAUSE:
					_pause_latch = true
					nav.emit("pause")
				if k in UP:
					nav.emit("up")
				if k in DOWN:
					nav.emit("down")
				if k in LEFT:
					nav.emit("left")
				if k in RIGHT:
					nav.emit("right")
				if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
					nav.emit("confirm")
				if k == KEY_ESCAPE or k == KEY_BACKSPACE or event.keycode == KEY_BACK:
					nav.emit("back")
		else:
			_keys.erase(k)
	elif event is InputEventJoypadButton:
		_set_device("gamepad")
		if event.pressed:
			match event.button_index:
				JOY_BUTTON_A:
					_jump_latch = true
					nav.emit("confirm")
				JOY_BUTTON_B:
					nav.emit("back")
				JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
					_switch_latch = true
				JOY_BUTTON_START:
					_pause_latch = true
					nav.emit("pause")
				JOY_BUTTON_DPAD_UP:
					nav.emit("up")
				JOY_BUTTON_DPAD_DOWN:
					nav.emit("down")
				JOY_BUTTON_DPAD_LEFT:
					nav.emit("left")
				JOY_BUTTON_DPAD_RIGHT:
					nav.emit("right")
	elif event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT:
			if event.axis_value > 0.6:
				_switch_latch = true
		elif absf(event.axis_value) > 0.4:
			_set_device("gamepad")


## The Android back gesture arrives as a window notification, not a key.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_pause_latch = true
		nav.emit("back")
		nav.emit("pause")


func _process(_delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_pad_x = 0.0
		_pad_y = 0.0
		_pad_jump = false
		return
	var id: int = pads[0]
	var ax := _deadzone(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
	var ay := _deadzone(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
	var dx := (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT) else 0.0) - (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT) else 0.0)
	var dy := (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN) else 0.0) - (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP) else 0.0)
	_pad_x = clampf(ax + dx, -1, 1)
	_pad_y = clampf(ay + dy, -1, 1)
	_pad_jump = Input.is_joy_button_pressed(id, JOY_BUTTON_A)
	# Stick flicks drive menus too.
	var raw := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
	if raw.y < -0.6 and _axis_prev.y >= -0.6:
		nav.emit("up")
	if raw.y > 0.6 and _axis_prev.y <= 0.6:
		nav.emit("down")
	if raw.x < -0.6 and _axis_prev.x >= -0.6:
		nav.emit("left")
	if raw.x > 0.6 and _axis_prev.x <= 0.6:
		nav.emit("right")
	_axis_prev = raw


static func _deadzone(v: float) -> float:
	var a := absf(v)
	if a < 0.18:
		return 0.0
	return signf(v) * minf(1.0, (a - 0.18) / 0.72)


func _any(list: Array) -> bool:
	for k in list:
		if _keys.has(k):
			return true
	return false


func press_jump() -> void:
	_jump_latch = true


func press_switch() -> void:
	_switch_latch = true


func consume_pause() -> bool:
	var p := _pause_latch
	_pause_latch = false
	return p


func consume_switch() -> bool:
	var p := _switch_latch
	_switch_latch = false
	return p


## Drops latched presses (a menu's confirm must not become a jump).
func flush() -> void:
	_jump_latch = false
	_switch_latch = false
	_pause_latch = false


## Builds one simulation frame: [move_x, move_z, jump_held, jump_pressed, switch_pressed].
## Presses are handed out once.
func frame() -> Array:
	if not enabled:
		return [0.0, 0.0, false, false, false]
	var x := (1.0 if _any(RIGHT) else 0.0) - (1.0 if _any(LEFT) else 0.0)
	var z := (1.0 if _any(UP) else 0.0) - (1.0 if _any(DOWN) else 0.0)
	x += _pad_x + touch_x
	z += -_pad_y + touch_y
	var f := [clampf(x, -1, 1), clampf(z, -1, 1), _any(JUMP) or _pad_jump or touch_jump, _jump_latch, _switch_latch]
	_jump_latch = false
	_switch_latch = false
	return f

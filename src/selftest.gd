class_name SelfTest
extends Node
## Automated checks through the real input pipeline (`-- --selftest[=mode]`, runs
## headless). Results go to the log as "SELFTEST PASS/FAIL ..." lines; the last line
## is "SELFTEST PASS" or "SELFTEST FAIL", and the exit code matches.
##
##   flow  title, programme, settings, begin, play, switch, pause, back to the
##         metronome, the back gesture, finish (teleport to the arch), the completion
##         card and the next movement, using keyboard, gamepad and touch events.
##   full  replays every movement's recorded solution (tests/data/<id>.json, 120 Hz)
##         through the game from the title and checks each completes with 7 notes and
##         0 deaths, then the ending and back to the title.
##
##   godot --headless --path . -- --selftest=flow
##   godot --headless --path . -- --selftest=full --speed=8


## The input router, plus a queue of recorded simulation frames handed out one per
## step while a replay runs.
class ReplayInput:
	extends InputRouter
	var replay: Array = []
	var replay_i := 0
	var replaying := false

	func start_replay(inputs: Array) -> void:
		replay = inputs
		replay_i = 0
		replaying = true

	func frame() -> Array:
		if not replaying:
			return super()
		if replay_i >= replay.size():
			return [0.0, 0.0, false, false, false]
		var inp: Array = replay[replay_i]
		replay_i += 1
		var flags := int(inp[2])
		return [float(inp[0]), float(inp[1]), flags & 1 != 0, flags & 2 != 0, flags & 4 != 0]


var app: App
var director: Director
var mode := "flow"
var speed := 1.0
var _passes := 0
var _fails := 0


## Called by the director before it connects to the input router.
func prepare(a: App, d: Director) -> void:
	app = a
	director = d
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--selftest="):
			mode = arg.substr(11)
		elif arg.begins_with("--speed="):
			speed = float(arg.substr(8))
	var old: InputRouter = app.input
	var rep := ReplayInput.new()
	var idx := old.get_index()
	app.remove_child(old)
	old.queue_free()
	rep.name = "Input"
	app.add_child(rep)
	app.move_child(rep, idx)
	app.input = rep


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log("start mode=%s speed=%.1f renderer=%s display=%s" % [mode, speed, RenderingServer.get_current_rendering_method(), DisplayServer.get_name()])
	_run.call_deferred()


func _log(s: String) -> void:
	print("SELFTEST ", s)


func _check(name: String, ok: bool, detail := "") -> bool:
	if ok:
		_passes += 1
		_log("PASS %s %s" % [name, detail])
	else:
		_fails += 1
		_log("FAIL %s %s" % [name, detail])
	return ok


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, false).timeout


func _wait_until(test: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not test.call():
		if (Time.get_ticks_msec() - t0) * Engine.time_scale > timeout * 1000.0:
			return false
		await get_tree().process_frame
	return true


func _run() -> void:
	Engine.time_scale = speed
	await _wait(0.8)
	if mode == "full":
		await _full()
	else:
		await _flow()
	Engine.time_scale = 1.0
	_log("%d passed, %d failed" % [_passes, _fails])
	_log("PASS" if _fails == 0 else "FAIL")
	app.paused = true
	if app.audio and app.audio.has_method("prepare_quit"):
		await app.audio.prepare_quit()
	get_tree().quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- synthetic input

func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _key(code: Key, hold := 0.06) -> void:
	_key_event(code, true)
	await _wait(hold)
	_key_event(code, false)
	await _wait(0.12)


func _key_event(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(0.06)
	var r := InputEventJoypadButton.new()
	r.device = 0
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await _wait(0.12)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(pos)
	e.relative = rel
	Input.parse_input_event(e)


func _tap(pos: Vector2, hold := 0.08) -> void:
	_touch(0, pos, true)
	await _wait(hold)
	_touch(0, pos, false)
	await _wait(0.15)


func _menu_item(label: String) -> UiMenuItem:
	var s := director.top_screen()
	if s == null or s.menu == null:
		return null
	return s.menu.find_label(label)


func _tap_item(label: String) -> bool:
	var it := _menu_item(label)
	if it == null:
		_log("no menu item " + label)
		return false
	await _tap(it.get_global_rect().get_center())
	return true


func _top_id() -> String:
	var s := director.top_screen()
	if s == null or s.menu == null or s.menu.items.is_empty():
		return ""
	return String(s.menu.items[0].id)


func _back_gesture() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.3)


# ---------------------------------------------------------------- flow

func _flow() -> void:
	# Held controller triggers emit one switch until released, including after focus loss.
	var probe := InputRouter.new()
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.8
	probe._input(trigger)
	_check("trigger_press", probe.consume_switch())
	_check("trigger_uses_pad_hints", probe.device == "gamepad")
	probe._input(trigger)
	_check("trigger_hold_once", not probe.consume_switch())
	trigger.axis_value = -1.0
	probe._input(trigger)
	trigger.axis_value = 0.8
	probe._input(trigger)
	_check("trigger_release_rearms", probe.consume_switch())
	probe.touch_x = 1.0
	probe.touch_jump = true
	probe.press_jump()
	probe.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("focus_releases_input", probe.frame() == [0.0, 0.0, false, false, false])
	var held_key := InputEventKey.new()
	held_key.physical_keycode = KEY_RIGHT
	held_key.pressed = true
	probe._input(held_key)
	_check("background_ignores_input", probe.frame() == [0.0, 0.0, false, false, false])
	probe.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	probe._input(held_key)
	_check("focus_restores_input", probe.frame()[0] == 1.0)
	probe.free()
	var game_x := func() -> float: return app.game.player.pos.x
	_check("title", director.state == "title" and _top_id() == "begin", director.state)
	# Keyboard: down to Programme, open it.
	await _key(KEY_DOWN)
	await _key(KEY_ENTER, 0.06)
	await _wait(0.5)
	_check("programme_opens", _top_id() == "overture", _top_id())
	# Touch: tap Back.
	await _tap_item("Back")
	await _wait(0.4)
	_check("programme_back_by_touch", _top_id() == "begin", _top_id())
	# Gamepad: down to Settings, open it, nudge the volume, back out with B.
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _wait(0.5)
	_check("settings_opens", _top_id() == "master", _top_id())
	var before := float(director.save.settings.master)
	await _pad(JOY_BUTTON_DPAD_LEFT)
	var after := float(director.save.settings.master)
	_check("settings_volume_steps", after < before, "%.2f -> %.2f" % [before, after])
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_B)
	await _wait(0.4)
	_check("settings_back_by_pad", _top_id() == "begin", _top_id())
	_check("settings_saved", FileAccess.file_exists(director.save.path))
	# Keyboard: up to Begin and start.
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _wait(1.4)
	_check("begin_plays", director.state == "play" and director.level_index() == 0, "%s %d" % [director.state, director.level_index()])
	_check("intro_card", director.intro.showing())
	_check("hud_shown", director.hud.is_shown())
	await _wait(1.0)
	# Keyboard: run right and jump.
	var x0: float = game_x.call()
	_key_event(KEY_RIGHT, true)
	await _wait(0.6)
	await _key(KEY_SPACE)
	await _wait(0.3)
	_key_event(KEY_RIGHT, false)
	await _wait(0.2)
	_check("keyboard_moves", game_x.call() > x0 + 1.5, "x %.2f -> %.2f" % [x0, game_x.call()])
	# Touch: the first touch makes the touch controls appear; then drag the stick.
	await _tap(Vector2(director.root.size.x * 0.25, director.root.size.y * 0.3))
	await _wait(0.2)
	_check("touch_controls_shown", director.touch.visible, app.input.device)
	var hint := director.hud.hint_text()
	_check("hint_for_touch", hint == "" or not hint.contains("Space"), hint)
	var x1: float = game_x.call()
	var at := Vector2(director.root.size.x * 0.2, director.root.size.y * 0.7)
	_touch(1, at, true)
	await _wait(0.05)
	for s in 6:
		_drag(1, at - Vector2(10.0 * (s + 1), 0), Vector2(-10, 0))
		await _wait(0.02)
	await _wait(0.5)
	_check("stick_drives", app.input.touch_x < -0.5 and game_x.call() < x1 - 0.5, "touch_x %.2f x %.2f -> %.2f" % [app.input.touch_x, x1, game_x.call()])
	# Jump with the stick still held (multi-touch).
	var j := director.touch.jump_rect().get_center()
	_touch(2, j, true)
	await _wait(0.1)
	_check("jump_button", app.game.player.since_jump < 0.3, "since_jump %.2f" % app.game.player.since_jump)
	_touch(1, at - Vector2(60, 0), false)
	await _wait(0.05)
	_check("stick_release_keeps_jump", app.input.touch_jump and app.input.touch_x == 0.0)
	_touch(2, j, false)
	await _wait(0.6)
	_check("stick_released", app.input.touch_x == 0.0)
	# The world button turns to the Score; the badge turns back.
	await _tap(director.touch.switch_rect().get_center())
	await _wait(1.0)
	_check("switch_to_score", app.game.mode == "2d", app.game.mode)
	_check("ui_restyles_for_score", UiStyle.k < 0.05, "k %.2f" % UiStyle.k)
	await _tap(director.hud.badge_rect().get_center())
	await _wait(1.0)
	_check("badge_to_stage", app.game.mode == "3d", app.game.mode)
	_check("ui_restyles_for_stage", UiStyle.k > 0.95, "k %.2f" % UiStyle.k)
	# Pause with the HUD button, back to the metronome with the gamepad.
	await _tap(director.hud.pause_rect().get_center())
	await _wait(0.4)
	_check("pause_button", director.state == "pause" and app.paused, director.state)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _wait(0.4)
	_check("back_to_metronome", director.state == "play" and not app.paused, director.state)
	# Esc pauses and Esc resumes (once each).
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	_check("esc_pauses", director.state == "pause", director.state)
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	_check("esc_resumes", director.state == "play", director.state)
	# The Android back gesture: pauses play, backs out of settings to the pause card, resumes.
	await _back_gesture()
	_check("back_gesture_pauses", director.state == "pause", director.state)
	await _tap_item("Settings")
	await _wait(0.4)
	_check("pause_settings", _top_id() == "master", _top_id())
	await _back_gesture()
	_check("back_gesture_leaves_settings", director.state == "pause" and _top_id() == "resume", "%s %s" % [director.state, _top_id()])
	await _back_gesture()
	_check("back_gesture_resumes", director.state == "play", director.state)
	# A real pickup persists before the arch is reached.
	var note: V3 = app.game.level.notes[0].pos
	app.teleport(note.x, note.y - 0.43, note.z)
	await _wait(0.2)
	var partial = JSON.parse_string(FileAccess.get_file_as_string(director.save.path))
	_check("pickup_saved_before_finish", app.game.notes_taken[0] and partial.movements.overture.notes[0])
	# Finish: put Quaver by the arch and walk in.
	var ex := app.game.level.exit_pos
	app.teleport(ex.x - 1.5, ex.y, ex.z)
	_key_event(KEY_RIGHT, true)
	await _wait(0.5)
	_key_event(KEY_RIGHT, false)
	var done := await _wait_until(func() -> bool: return director.state == "complete", 4.0)
	_check("movement_complete", done, director.state)
	_check("progress_saved", director.save.is_done("overture"))
	var saved = JSON.parse_string(FileAccess.get_file_as_string(director.save.path))
	_check("save_file_shape", saved is Dictionary and int(saved.v) == 1 and saved.movements.overture.done == true and saved.settings.has("startIn"))
	await _wait(0.6)
	await _tap_item("Next movement")
	await _wait(1.6)
	_check("next_movement", director.state == "play" and director.level_index() == 1, "%s %d" % [director.state, director.level_index()])
	_check("save_last", int(director.save.data.last) == 1)


# ---------------------------------------------------------------- full

## Feeds the movement's recorded solution from its very first simulation step.
func _replay_level(i: int) -> void:
	var f := FileAccess.open("res://tests/data/%s.json" % director.ids[i], FileAccess.READ)
	var rec: Dictionary = JSON.parse_string(f.get_as_text())
	(app.input as ReplayInput).start_replay(rec.inputs)


func _full() -> void:
	var rep := app.input as ReplayInput
	var ids: Array = director.ids
	director.level_started.connect(_replay_level)
	_check("title", director.state == "title")
	await _key(KEY_ENTER)
	for i in ids.size():
		var started := await _wait_until(func() -> bool: return director.state == "play" and director.level_index() == i, 5.0)
		if not _check("start_%s" % ids[i], started, director.state):
			return
		var t0 := Time.get_ticks_msec()
		var done := await _wait_until(func() -> bool: return director.state == "complete", 400.0)
		var g := app.game
		_check("%s" % ids[i], done and g.finished and g.notes_count() == 7 and g.deaths == 0,
			"finished %s notes %d deaths %d switches %d time %s in %d ms" % [g.finished, g.notes_count(), g.deaths, g.switches, UiStyle.fmt_time(g.play_time), Time.get_ticks_msec() - t0])
		_check("%s_hud_notes" % ids[i], director.hud._slots.count(true) == 7)
		rep.replaying = false
		await _wait(0.8)
		await _key(KEY_ENTER)
	var ending := await _wait_until(func() -> bool: return director.state == "ending", 3.0)
	_check("ending", ending, director.state)
	var credits := await _wait_until(func() -> bool: return director._ending_timer > 30.0, 40.0)
	_check("ending_credits", credits, "t %.1f" % director._ending_timer)
	await _key(KEY_ESCAPE)
	var back := await _wait_until(func() -> bool: return director.state == "title", 3.0)
	_check("ending_to_title", back, director.state)
	_check("seen_ending", bool(director.save.data.seenEnding))
	_check("all_notes_saved", director.save.total_notes(ids) == 42, str(director.save.total_notes(ids)))
	_check("title_offers_begin_again", _top_id() == "begin" and director.top_screen().menu.items[0].label == "Begin again", _top_id())

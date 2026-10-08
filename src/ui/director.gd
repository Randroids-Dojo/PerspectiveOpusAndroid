class_name Director
extends CanvasLayer
## Runs the game around the loop: title, programme, play, pause, completion and the
## ending, a port of the web build's src/director.ts. It owns the UI layer (menus, HUD,
## touch controls, the intro card and the fade), the save, and applies settings to
## the audio, the camera and the renderers.
##
## Screenshot flags (with app.gd's --shot and --frames):
##   --ui=programme|settings|controls|credits    open a screen over the title
##   --ui=pause|complete|ending                   with --level=<id>: pause, finish, or the last bow
##   --world=2d        the title (or the level) on the Score
##   --device=touch|gamepad|keyboard              pretend the last input came from there
##   --demo            a save with some progress (never written)
##   --intro           with --level: show the movement's title card
##   --cutout=left|right                          fake a camera cutout's safe inset

signal level_started(index: int)

const SONGS := {
	"overture": "overture", "adagio": "adagio", "scherzo": "scherzo", "nocturne": "nocturne",
	"toccata": "toccata", "finale": "finale", "title": "title",
}

var app: App
var save: OpusSave
## "title", "play", "pause", "complete" or "ending".
var state := "title"
var ids: Array = []
var infos: Array = []
var stack: Array[UiScreen] = []
var hooks := {}

var root := Control.new()
var hud := Hud.new()
var touch := TouchControls.new()
var screens := Control.new()
var intro := UiOverlays.IntroCard.new()
var fade := UiOverlays.Fade.new()
var safe := Vector4.ZERO

var _title_clock := 0.0
var _title_turn_at := 9.0
var _complete_timer := -1.0
var _busy := false
var _ending_timer := -1.0
var _setup_done := false
var _args := {}
var _k_from := 1.0
var _k_to := 1.0
var _k_t := 1.0
var _nav_frame := -1
var _quality_setting := "auto"
var _slow_frames := 0.0
var _frame_count := 0
var _mobile := false
var _selftest: Node = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiStyle.setup()
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_mobile = OS.has_feature("mobile")
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(root)
	screens.set_anchors_preset(Control.PRESET_FULL_RECT)
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [hud, touch, screens, intro, fade]:
		root.add_child(c)
	touch.show_controls(false)
	get_viewport().size_changed.connect(_on_resize)


## Called by app.gd when it reaches its _ready (after this node's), so the app's
## nodes exist by now.
func _setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	app = get_parent() as App
	ids = Level.movement_ids()
	for id in ids:
		var f := FileAccess.open("res://assets/data/levels/%s.json" % id, FileAccess.READ)
		infos.append((JSON.parse_string(f.get_as_text()) as Dictionary).info)
	if _args.has("selftest"):
		var path := "user://selftest_save.json"
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		save = OpusSave.load_from(path)
		_selftest = load("res://src/selftest.gd").new()
		_selftest.prepare(app, self)
	elif _args.has("demo"):
		save = OpusSave.load_from("user://__none__.json")
		save.writable = false
		_demo_progress()
	else:
		save = OpusSave.load_from(OpusSave.PATH)
		# Screenshot and development runs never touch the player's progress.
		save.writable = not (_args.has("shot") or _args.has("ui"))
	hooks = {
		"hover": func() -> void: _ui("hover"),
		"select": func() -> void: _ui("confirm"),
		"blocked": func() -> void: _ui("back"),
	}
	touch.input = app.input
	app.input.nav.connect(_nav)
	app.input.device_changed.connect(_on_device)
	app.events_emitted.connect(_on_events)
	app.frame_done.connect(_frame)
	hud.switch_pressed.connect(_on_badge)
	hud.pause_pressed.connect(pause)
	touch.jumped.connect(func() -> void: _haptic(8, 0.4))
	touch.switched.connect(func() -> void: _haptic(14, 0.6))
	if _args.has("device"):
		app.input.device = String(_args.device)
	UiStyle.device = app.input.device
	_apply_settings()
	_on_resize()
	if _selftest:
		add_child(_selftest)


func _demo_progress() -> void:
	var d := save.data
	d.movements = {
		"overture": {"done": true, "notes": [true, true, true, true, true, true, true], "bestTime": 83.4, "fewestDeaths": 0},
		"adagio": {"done": true, "notes": [true, false, true, true, false, true, false], "bestTime": 141.25, "fewestDeaths": 2},
		"scherzo": {"done": false, "notes": [true, true, false, false, false, false, false], "bestTime": null, "fewestDeaths": null},
	}
	d.last = 2
	d.settings.showTimer = true


# ---------------------------------------------------------------- flow

func start() -> void:
	_setup()
	_show_title(true)
	if _args.has("world") and _args.world == "2d":
		app.game.toggle_mode()
		app.view.snap(app.game)
		_title_clock = -1e9
	_snap_world()
	match String(_args.get("ui", "")):
		"programme":
			_push(_make_programme())
		"settings":
			_push(_make_settings())
		"controls":
			_push(_make_settings())
			_push(_make_controls())
		"credits":
			_push(_make_credits())


func _show_title(first := false) -> void:
	state = "title"
	_clear_screens()
	hud.show_hud(false)
	intro.hide_card()
	app.start_level("title", "3d")
	app.input.enabled = false
	app.paused = false
	_audio("set_paused", [false])
	app.view.has_focus = true
	app.view.focus = Vector3(20, 9.2, 4)
	app.view.orbit = Vector3.ZERO
	_title_clock = 0.0
	_title_turn_at = 7.0 if first else 5.0
	_push(_make_title())
	_refresh_touch()
	_play_music()
	_fade_in()


func _ctx(extra: Dictionary) -> Dictionary:
	var c := {"save": save, "ids": ids, "infos": infos, "hooks": hooks}
	c.merge(extra, true)
	return c


func _make_title() -> UiScreen:
	return UiScreens.title(_ctx({
		"on_begin": func() -> void: play(0),
		"on_continue": func(i: int) -> void: play(i),
		"on_programme": func() -> void: _push(_make_programme()),
		"on_settings": func() -> void: _push(_make_settings()),
		"on_credits": func() -> void: _push(_make_credits()),
	}))


func _make_programme() -> UiScreen:
	return UiScreens.programme(_ctx({"on_play": func(i: int) -> void: play(i), "on_back": _pop}))


func _make_settings() -> UiScreen:
	return UiScreens.settings(_ctx({
		"settings": save.settings,
		"haptics": _mobile or _args.has("haptics"),
		"on_change": _settings_changed,
		"on_controls": func() -> void: _push(_make_controls()),
		"on_back": _pop,
	}))


func _settings_changed() -> void:
	_apply_settings()
	save.write()


func _make_controls() -> UiScreen:
	return UiScreens.controls(_ctx({"on_back": _pop}))


func _make_credits() -> UiScreen:
	return UiScreens.credits(_ctx({"on_back": _pop, "total": save.total_notes(ids)}))


func level_index() -> int:
	return ids.find(app.level_id)


## Starts a movement with a fade and its title card.
func play(index: int, mode := "") -> void:
	if _busy:
		return
	_busy = true
	_ui("start")
	_fade_out(_begin_play.bind(index, mode))


func _begin_play(index: int, mode: String) -> void:
	_busy = false
	_clear_screens()
	state = "play"
	save.data.last = index
	save.write()
	app.view.has_focus = false
	app.view.orbit = Vector3.ZERO
	var game := app.start_level(ids[index], mode if mode != "" else String(save.settings.startIn))
	# Notes already found stay found, so a replay is about the ones still missing.
	save.record(ids[index], game.level.notes.size())
	app.input.enabled = true
	app.input.flush()
	app.paused = false
	_audio("set_paused", [false])
	_complete_timer = -1.0
	hud.set_level(game)
	hud.show_hud(true)
	_refresh_touch()
	_audio("set_restored", [0, game.level.notes.size()])
	_play_music()
	intro.show_card(infos[index])
	hud.quiet_until = Time.get_ticks_msec() + 3600
	_fade_in()
	level_started.emit(index)


## Development entry (app.gd's --level): no fade, no card.
func play_now() -> void:
	_setup()
	_clear_screens()
	state = "play"
	var game := app.game
	if _args.has("world") and _args.world == "2d" and game.mode == "3d":
		game.toggle_mode()
		app.view.snap(game)
	_snap_world()
	app.input.enabled = true
	hud.set_level(game)
	hud.show_hud(true)
	_refresh_touch()
	_play_music()
	if _args.has("intro") and level_index() >= 0:
		intro.show_card(infos[level_index()])
	match String(_args.get("ui", "")):
		"pause":
			pause()
		"complete":
			for i in game.notes_taken.size():
				game.notes_taken[i] = i % 3 == 0
			game.switches = 4
			_complete()
		"ending":
			_begin_ending()


func pause() -> void:
	if state != "play" or app.game == null or app.game.finished:
		return
	var game := app.game
	state = "pause"
	app.paused = true
	_audio("set_paused", [true])
	_ui("pause")
	hud.show_hud(false)
	_refresh_touch()
	var info := game.level.info
	_push(UiScreens.pause(_ctx({
		"title": info.title,
		"movement": info.movement,
		"found": game.notes_count(),
		"on_resume": resume,
		"on_checkpoint": _to_checkpoint,
		"on_restart": func() -> void: play(level_index(), app.game.mode if app.game else ""),
		"on_settings": func() -> void: _push(_make_settings()),
		"on_programme": func() -> void: _push(_make_programme()),
		"on_title": func() -> void: _fade_out(_show_title),
	})))


func _to_checkpoint() -> void:
	resume()
	if app.game:
		app.game.return_to_checkpoint()


func resume() -> void:
	if state != "pause":
		return
	_clear_screens()
	state = "play"
	app.paused = false
	_audio("set_paused", [false])
	_ui("resume")
	app.input.flush()
	hud.show_hud(true)
	_refresh_touch()


func _complete() -> void:
	var game := app.game
	var index := level_index()
	if index < 0:
		# Not a movement (the gallery): nothing to record, back to the title.
		_fade_out(_show_title)
		return
	var id: String = ids[index]
	var rec := save.record(id, game.level.notes.size())
	var was_done := bool(rec.done)
	rec.done = true
	for i in game.notes_taken.size():
		if game.notes_taken[i]:
			rec.notes[i] = true
	var best: bool = rec.bestTime == null or game.play_time < float(rec.bestTime)
	if best:
		rec.bestTime = game.play_time
	rec.fewestDeaths = game.deaths if rec.fewestDeaths == null else mini(int(rec.fewestDeaths), game.deaths)
	save.write()
	state = "complete"
	app.input.enabled = false
	hud.show_hud(false)
	_refresh_touch()
	_ui("complete")
	var last := index == ids.size() - 1
	_audio("preload", ["ending" if last else SONGS.get(ids[index + 1], "title")])
	var notes: Array = []
	for t in game.notes_taken:
		notes.append(t)
	_push(UiScreens.complete(_ctx({
		"info": game.level.info,
		"notes": notes,
		"time": game.play_time,
		"deaths": game.deaths,
		"switches": game.switches,
		"best": best and was_done,
		"last": last,
		"on_next": _next_after.bind(index, last),
		"on_replay": func() -> void: play(index),
		"on_programme": func() -> void: _push(_make_programme()),
	})))


func _next_after(index: int, last: bool) -> void:
	if last:
		_ending()
	else:
		play(index + 1)


func total_notes() -> int:
	return save.total_notes(ids)


## The last bow: the whole Opus plays over the hall while the credits roll.
func _ending() -> void:
	_fade_out(_begin_ending)


func _begin_ending() -> void:
	_clear_screens()
	state = "ending"
	save.data.seenEnding = true
	save.write()
	app.start_level("title", "3d", "finale")
	app.input.enabled = false
	app.view.has_focus = true
	app.view.focus = Vector3(22.5, 9.4, 4)
	app.view.orbit = Vector3(0, 0.1, 6)
	hud.show_hud(false)
	_refresh_touch()
	_audio("play_song", ["ending"])
	_ending_timer = 0.0
	var total := total_notes()
	var lines := UiOverlays.EndingLines.new()
	lines.lines = [
		"The last note found its place.",
		"The page and the stage were never two places.",
		"They were one song, heard two ways.",
		"Every one of the forty-two notes is home. Encore." if total == 42 else "%d of 42 notes are home. The rest are still out there, humming." % total,
	]
	var to_title := func() -> void: _fade_out(_show_title)
	var credits := UiScreens.credits(_ctx({"on_back": to_title, "total": total}))
	credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	var holder := EndingCredits.new()
	holder.director = self
	holder.add_child(credits)
	var s := UiScreen.new()
	s.kind = "ending"
	s.menu = credits.menu
	s.add_child(lines)
	s.add_child(holder)
	credits.on_scrim = func() -> void:
		if _ending_timer > 3.0:
			to_title.call()
	s.nav_fn = func(a: String) -> bool: return credits.nav(a) if _ending_timer > 3.0 else true
	s.layout_fn = func(_sc: UiScreen, w: float, h: float) -> void:
		lines.size = Vector2(w, h)
		holder.size = Vector2(w, h)
		credits.relayout(w, h)
	_push(s)
	credits.set_state("in")
	_fade_in(2.5)


## Holds the ending's credits: they rise in 27 s into the bow (credits-in, 2.4 s).
class EndingCredits:
	extends Control
	var director: Director

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		var p := UiStyle.ease(clampf((director._ending_timer - 27.0) / 2.4, 0.0, 1.0))
		modulate.a = p
		position.y = 30.0 * (1.0 - p)


# ---------------------------------------------------------------- per frame

func _frame(dt: float) -> void:
	if not _setup_done:
		return
	var game := app.game
	if game == null:
		return
	_update_world(dt)
	touch.mode = game.mode
	if state == "play":
		if app.input.consume_pause():
			pause()
		hud.update(game, app.input.device)
		if _complete_timer >= 0.0:
			_complete_timer += dt
			if _complete_timer > 1.7:
				_complete_timer = -1.0
				_complete()
	elif state == "title" or state == "ending":
		app.input.consume_pause()
		# The title world turns by itself, and on request.
		_title_clock += dt
		var asked := app.input.consume_switch()
		if asked or _title_clock > _title_turn_at:
			game.toggle_mode()
			_title_clock = 0.0
			_title_turn_at = 8.0 if game.mode == "3d" else 5.5
			if asked:
				_ui("page")
		var t := Time.get_ticks_msec() / 1000.0
		if state == "title":
			app.view.orbit = Vector3(sin(t * 0.11) * 0.22, sin(t * 0.07) * 0.06, 2.0)
		else:
			_ending_timer += dt
			app.view.orbit = Vector3(sin(t * 0.08) * 0.35, 0.12 + minf(_ending_timer * 0.004, 0.2), 6.0 + _ending_timer * 0.12)
	else:
		app.input.consume_pause()
		app.input.consume_switch()
	_watch_frame_rate(dt)


func _on_events(events: Array) -> void:
	var game := app.game
	if game == null or state != "play":
		return
	hud.on_events(events, game, app.view)
	var reduce := bool(save.settings.reduceMotion)
	for e in events:
		match String(e.t):
			"note":
				_audio("set_restored", [e.count, e.total])
			"exit":
				_complete_timer = 0.0
			"death":
				app.view.shake = 0.0 if reduce else 0.6
			"land":
				var impact := float(e.impact)
				if impact > 17.0:
					app.view.shake = maxf(app.view.shake, 0.0 if reduce else 0.25)
				# A tap underfoot, firmer for a long fall.
				if impact > 9.0:
					_haptic(18 if impact > 17.0 else 8, 0.7 if impact > 17.0 else 0.25)


## The UI's colours follow the world, easing over half a second when it turns.
func _update_world(dt: float) -> void:
	var target := 1.0 if app.view.blend > 0.5 else 0.0
	if target != _k_to:
		_k_from = UiStyle.k
		_k_to = target
		_k_t = 0.0
	if _k_t < 1.0:
		_k_t = minf(1.0, _k_t + dt / 0.5)
		UiStyle.k = lerpf(_k_from, _k_to, UiStyle.ease(_k_t))
		root.propagate_call("queue_redraw")


func _snap_world() -> void:
	_k_to = 1.0 if app.view.blend > 0.5 else 0.0
	_k_from = _k_to
	_k_t = 1.0
	UiStyle.k = _k_to
	root.propagate_call("queue_redraw")


# ---------------------------------------------------------------- input and screens

func _nav(a: String) -> void:
	if not _setup_done:
		return
	# One press, one action: Esc and the back gesture send both "back" and "pause".
	if (a == "back" or a == "pause") and _nav_frame == Engine.get_process_frames():
		return
	if stack.is_empty():
		return
	var top: UiScreen = stack.back()
	if top.state != "in" or fade.mouse_filter == Control.MOUSE_FILTER_STOP:
		return
	var handled := false
	if a == "pause" and state == "pause" and stack.size() > 1:
		_pop()
		handled = true
	else:
		handled = top.nav(a)
		if not handled and a == "back" and stack.size() > 1:
			_pop()
			handled = true
	if handled and (a == "back" or a == "pause"):
		_nav_frame = Engine.get_process_frames()


func _push(s: UiScreen) -> void:
	if not stack.is_empty():
		stack.back().set_state("under")
	stack.append(s)
	screens.add_child(s)
	s.relayout(root.size.x, root.size.y)
	s.set_state("in")


func _pop() -> void:
	if stack.is_empty():
		return
	var s: UiScreen = stack.pop_back()
	_ui("back")
	if s.leave_fn.is_valid():
		s.leave_fn.call()
	s.set_state("out")
	get_tree().create_timer(0.26).timeout.connect(s.queue_free)
	if not stack.is_empty():
		stack.back().set_state("in")


func _clear_screens() -> void:
	for s in stack:
		if s.leave_fn.is_valid():
			s.leave_fn.call()
		s.queue_free()
	stack.clear()


func top_screen() -> UiScreen:
	return stack.back() if not stack.is_empty() else null


func _refresh_touch() -> void:
	touch.show_controls(app.input.device == "touch" and state == "play")


func _on_device(d: String) -> void:
	UiStyle.device = d
	_refresh_touch()
	for s in stack:
		s.relayout(root.size.x, root.size.y)


func _on_badge() -> void:
	app.input.press_switch()
	_haptic(14, 0.6)


func _fade_out(then: Callable) -> void:
	fade.go(1.0, 0.45)
	get_tree().create_timer(0.47).timeout.connect(then)


func _fade_in(seconds := 0.6) -> void:
	fade.go(0.0, seconds)


func _on_resize() -> void:
	var vr := get_viewport().get_visible_rect().size
	root.size = vr
	safe = Vector4.ZERO
	if _mobile:
		var area := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		if win.x > 0 and area.size.x > 0:
			var k := vr.x / float(win.x)
			safe = Vector4(maxf(0.0, area.position.x * k), maxf(0.0, area.position.y * k), maxf(0.0, (win.x - area.end.x) * k), maxf(0.0, (win.y - area.end.y) * k))
	if _args.has("cutout"):
		safe = Vector4(32, 0, 0, 0) if _args.cutout == "left" else Vector4(0, 0, 32, 0)
	hud.safe = safe
	touch.safe = safe
	UiStyle.compact = vr.y <= 480.0
	for s in stack:
		s.relayout(vr.x, vr.y)


# ---------------------------------------------------------------- audio, haptics, settings

func _audio(method: String, args: Array = []) -> void:
	var au: Node = app.audio if app else null
	if au and au.has_method(method):
		au.callv(method, args)


func _ui(name: String) -> void:
	_audio("ui", [name])


func _play_music() -> void:
	if state == "ending":
		_audio("play_song", ["ending"])
		return
	var id := String(app.game.level.info.id) if app.game else "title"
	_audio("play_song", [SONGS.get(id, "title")])
	# From the title, the next thing played is the movement Begin or Continue leads to.
	if state == "title":
		var next := save.next_movement(ids)
		_audio("preload", [SONGS[ids[mini(next, ids.size() - 1)]]])


func _haptic(ms: int, amplitude: float) -> void:
	if _mobile and app.input.device == "touch" and bool(save.settings.get("haptics", true)):
		Input.vibrate_handheld(ms, amplitude)


func _apply_settings() -> void:
	var s := save.settings
	_audio("set_volumes", [{"master": float(s.master), "music": float(s.music), "sfx": float(s.sfx)}])
	app.view.reduce_motion = bool(s.reduceMotion)
	hud.show_timer = bool(s.showTimer)
	_set_quality(String(s.quality))


## Picks a detail tier. "auto" starts from the device and steps down if frames run slow.
func _set_quality(q: String) -> void:
	_quality_setting = q
	if q == "auto":
		app.quality = "medium" if _mobile else "high"
	else:
		app.quality = q
	_slow_frames = 0.0
	UiStyle.blur = app.quality != "low"


func _watch_frame_rate(dt: float) -> void:
	if _quality_setting != "auto" or app.paused or _selftest != null:
		return
	_frame_count += 1
	if _frame_count < 120:
		return
	# Over about three seconds of slow frames, drop a tier.
	if dt > 1.0 / 40.0:
		_slow_frames += 1.0
	else:
		_slow_frames = maxf(0.0, _slow_frames - 0.25)
	if _slow_frames > 90.0 and app.quality != "low":
		app.quality = "medium" if app.quality == "high" else "low"
		UiStyle.blur = app.quality != "low"
		_slow_frames = 0.0
		_frame_count = 0


## The app went to the background: pause a movement in play, like the web build on
## visibilitychange.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or (_mobile and what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		if _setup_done and state == "play" and _selftest == null:
			pause()

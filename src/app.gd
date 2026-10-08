class_name App
extends Node
## Owns the loop: input, the fixed-step simulation, the shared camera, both renderers
## and the audio. A port of the web build's src/app.ts.
##
## Development flags (after `--` on the command line):
##   --level=overture|0..5|title|gallery  --mode=2d|3d  --palette=night
##   --x= --y= --z=      teleport the player
##   --switch-at=N       press switch on frame N
##   --shot=path.png     save a screenshot after --frames=N (default 90) and quit

signal events_emitted(events: Array)
signal frame_done(dt: float)

const STEP := 1.0 / 120.0

@onready var input: InputRouter = $Input
@onready var stage = $Stage
@onready var page = $Page
@onready var audio = $Audio

var game: Sim
var view := View.new()
var palettes: Dictionary
var level_id := ""
var paused := false
var quality := "medium"
var dark_page := false
var _acc := 0.0
var _now := 0.0
var _frames := 0
var _args := {}


func _ready() -> void:
	var f := FileAccess.open("res://assets/data/palettes.json", FileAccess.READ)
	palettes = JSON.parse_string(f.get_as_text())
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	if _args.has("level"):
		var lid: String = _args.level
		if lid.is_valid_int():
			lid = Level.movement_ids()[int(lid)]
		start_level(lid, _args.get("mode", "3d"), _args.get("palette", ""))
		if _args.has("x"):
			teleport(float(_args.x), float(_args.get("y", "12")), float(_args.get("z", "3")))
		var ui = get_node_or_null("UI")
		if ui and ui.has_method("play_now"):
			ui.play_now()
	else:
		var ui = get_node_or_null("UI")
		if ui and ui.has_method("start"):
			ui.start()
		else:
			start_level("title", "3d")


func _on_resize() -> void:
	var vr := get_viewport().get_visible_rect().size
	var win := Vector2(get_window().size)
	view.resize(vr.x, vr.y, win.x / maxf(1.0, vr.x))
	if stage and stage.has_method("resize"):
		stage.resize(view)
	if page and page.has_method("resize"):
		page.resize(view)


func start_level(id: String, mode: String, palette_override: String = "") -> Sim:
	level_id = id
	var lv := Level.load_id(id)
	game = Sim.new(lv, mode)
	var pal: Dictionary = palettes[palette_override if palette_override != "" else String(lv.info.palette)]
	dark_page = bool(pal.inverted)
	stage.load_level(game, pal)
	page.load_level(game, pal)
	view.snap(game)
	page.prewarm(game, view, _now, quality, true)
	_acc = 0.0
	return game


func teleport(x: float, y: float, z: float) -> void:
	if game == null:
		return
	game.player.pos = V3.new(x, y, z)
	game.player.prev = V3.new(x, y, z)
	game.player.vel = V3.new()
	view.snap(game)


func _process(delta: float) -> void:
	var dt := minf(0.1, delta)
	_now += dt
	_frames += 1
	if _args.has("switch-at") and _frames == int(_args["switch-at"]):
		input.press_switch()
	var game_dt := 0.0
	var events: Array = []
	if game != null and not paused:
		_acc += dt * view.time_scale
		var steps := 0
		while _acc >= STEP and steps < 12:
			var f := input.frame()
			game.step(STEP, f[0], f[1], f[2], f[3], f[4])
			_acc -= STEP
			game_dt += STEP
			steps += 1
			if not game.events.is_empty():
				events.append_array(game.events)
				game.events.clear()
		if steps == 12:
			_acc = 0.0
	if game != null:
		if not paused:
			view.update(game, dt)
		if audio and audio.has_method("set_perspective"):
			audio.set_perspective(view.blend)
			audio.set_time_scale(view.time_scale)
			if not events.is_empty():
				audio.handle(events, game)
		if not events.is_empty():
			events_emitted.emit(events)
		var frame := {
			"alpha": 1.0 if paused else _acc / STEP,
			"dt": dt,
			"game_dt": game_dt,
			"now": _now,
			"events": events,
			"beat": audio.beat() if audio and audio.has_method("beat") else -1.0,
			"quality": quality,
			"paused": paused,
		}
		var show_stage := view.wipe > 0.0
		var show_page := view.wipe < 1.0
		stage.set_world_visible(show_stage)
		page.set_world_visible(show_page)
		if show_stage:
			stage.render(game, view, frame)
		if show_page:
			page.render(game, view, frame)
		elif not paused:
			page.prewarm(game, view, _now, quality)
	frame_done.emit(dt)
	if _args.has("shot") and _frames == int(_args.get("frames", "90")):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("SHOT ", _args.shot)
		paused = true
		if audio and audio.has_method("prepare_quit"):
			await audio.prepare_quit()
		get_tree().quit()

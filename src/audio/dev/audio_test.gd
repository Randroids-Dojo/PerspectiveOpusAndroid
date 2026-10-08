extends Node
## Audio tour: every song through restores and switches, every effect in both worlds,
## every menu sound, logging what plays (with the beat and the harmony it fits).
##
##   $GODOT --path . res://src/audio/dev/audio_test.tscn -- [--songs=title,overture] [--seconds=24] [--verbose]
##   $GODOT --path . res://src/audio/dev/audio_test.tscn -- --steady=overture,finale
##       each song from its start for 24 s: score and stage with all notes found, then with none
##       (the conditions of the web build's `scripts/audio-render.ts --levels`), for loudness parity
##   $GODOT --path . res://src/audio/dev/audio_test.tscn -- --switches=overture,finale
##       36 s from the start on the stage, switching to the page at 6 and 22 s and back at 14 and
##       30 s (0.8 s linear glides, the game's slow-down), all notes found and then three, effects
##       off: the scenario `tools/render_audio.ts --only=reference` renders with the web build
##
## Add `--write-movie /tmp/tour.avi --fixed-fps 60` (before the `--`) to capture what
## Godot actually mixed; tools/audio/analyze_capture.py measures it. A timeline of
## what happened when is written to user://audio_test.json.

const ALL: Array[String] = ["title", "overture", "adagio", "scherzo", "nocturne", "toccata", "finale", "ending"]
const SWITCH_TIME := 0.8

var audio: OpusAudio
var args := {}
var songs: Array[String] = []
var seg := 24.0
var t := 0.0
var seg_t := 0.0
var index := -1
var blend := 1.0
var sw_from := 1.0
var sw_to := 1.0
var sw_t := -1.0
var found := 0
var plan: Array = []
var marks: Array = []
var steady := ""
var steady_runs: Array = []  # [song, blend, restored]
var linear := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	audio = OpusAudio.new()
	audio.log_sounds = args.has("verbose")
	add_child(audio)
	if args.has("comp-threshold"):
		# Tuning only: the master compressor's threshold.
		(AudioServer.get_bus_effect(0, 0) as AudioEffectCompressor).threshold = float(args["comp-threshold"])
	steady = String(args.get("steady", ""))
	if args.has("switches"):
		linear = true
		audio.set_volumes(1.0, 1.0, 0.0)
		for id in String(args.switches).split(","):
			for level in [7, 3]:
				steady_runs.append([id, 1.0, level])
				songs.append(id)
		steady = "switches"
	elif steady != "":
		for id in steady.split(","):
			var levels := [7] if id == "title" or id == "ending" else [7, 0]
			for level in levels:
				for b in [0.0, 1.0]:
					steady_runs.append([id, b, level])
					songs.append(id)
	else:
		var list: PackedStringArray = String(args.get("songs", ",".join(ALL))).split(",")
		for s in list:
			songs.append(s)
	seg = float(args.get("seconds", "36" if linear else "24"))


func _process(delta: float) -> void:
	t += delta
	seg_t += delta
	if index >= songs.size():
		return
	if index < 0 or seg_t >= (seg if songs[index] != "ending" or steady != "" else minf(seg, 16.0)):
		_next_song()
	_switching(delta)
	while not plan.is_empty() and float(plan[0][0]) <= seg_t:
		var step: Array = plan.pop_front()
		(step[1] as Callable).call()
	audio.set_perspective(blend)


func _next_song() -> void:
	index += 1
	seg_t = 0.0
	plan.clear()
	if index >= songs.size():
		audio.stop_song(1.0)
		_mark("stop", {})
		await get_tree().create_timer(1.6).timeout
		_finish()
		return
	var id := songs[index]
	if steady != "":
		# The same song from its start in each condition.
		var run: Array = steady_runs[index]
		blend = run[1]
		sw_t = -1.0
		audio.stop_song(0.02)
		audio.set_restored(run[2], 7)
		audio.play_song(id)
		_mark("song", {"id": id, "blend": blend, "restored": run[2]})
		if linear:
			for at in [6.0, 14.0, 22.0, 30.0]:
				plan.append([at, func() -> void: _switch(false)])
		return
	found = 0
	audio.set_restored(0, 7)
	audio.play_song(id)
	if index + 1 < songs.size():
		audio.preload_song(songs[index + 1])
	_mark("song", {"id": id, "blend": blend, "restored": 0})
	var fx := func(at: float, what: String, ev: Dictionary) -> void:
		plan.append([at, func() -> void: _event(what, ev)])
	# Notes found every 2.5 s.
	for k in range(1, 8):
		var at := 0.6 + 2.5 * k
		plan.append([at, func() -> void:
			found = k
			audio.set_restored(found, 7)
			_event("note %d/7" % k, {"t": "note", "id": k, "count": k, "total": 7})])
	# Switches, the first at 4 s.
	for at in [4.0, 9.0, 14.0, 19.0]:
		plan.append([at, func() -> void: _switch()])
	for k in 4:
		fx.call(1.0 + 0.28 * k, "step wood", {"t": "step", "surface": 3})
	fx.call(2.0, "jump", {"t": "jump"})
	fx.call(2.5, "land soft", {"t": "land", "impact": 6.0, "surface": 1})
	fx.call(3.0, "land hard", {"t": "land", "impact": 20.0, "surface": 3})
	fx.call(3.5, "bonk", {"t": "bonk"})
	fx.call(5.5, "checkpoint", {"t": "checkpoint", "id": 0})
	fx.call(6.4, "death", {"t": "death", "cause": "thorn"})
	fx.call(7.4, "respawn", {"t": "respawn"})
	fx.call(8.2, "bounce", {"t": "bounce", "id": 0})
	fx.call(10.4, "key on", {"t": "key", "id": 0, "group": 1, "on": true})
	fx.call(10.4, "gate on", {"t": "gate", "group": 1, "on": true})
	fx.call(11.6, "key off", {"t": "key", "id": 0, "group": 1, "on": false})
	fx.call(11.6, "gate off", {"t": "gate", "group": 1, "on": false})
	var mats := ["stone", "brick", "brass", "dark", "crystal", "leaf", "marble"]
	for k in mats.size():
		fx.call(12.2 + 0.25 * k, "step " + mats[k], {"t": "step", "surface": [1, 2, 4, 5, 6, 7, 9][k]})
	fx.call(16.0, "jump", {"t": "jump"})
	fx.call(17.0, "exit", {"t": "exit"})
	var uis := ["hover", "confirm", "back", "pause", "resume", "start", "complete", "unlock", "page"]
	for k in uis.size():
		var u: String = uis[k]
		plan.append([20.5 + 0.35 * k, func() -> void:
			if u == "pause":
				audio.set_paused(true)
			if u == "resume":
				audio.set_paused(false)
			audio.ui(u)
			_mark("ui", {"name": u})
			_log("ui " + u)])
	plan.sort_custom(func(a, b): return float(a[0]) < float(b[0]))


func _mode() -> String:
	return "2d" if blend < 0.5 else "3d"


func _event(what: String, ev: Dictionary) -> void:
	if not ev.has("mode") and ev.t in ["step", "jump", "land"]:
		ev["mode"] = _mode()
	audio.handle([ev], {"mode": _mode()})
	_mark("event", {"what": what, "mode": String(ev.get("mode", _mode()))})
	_log("%s (%s)" % [what, "page" if String(ev.get("mode", _mode())) == "2d" else "stage"])


func _switch(sound := true) -> void:
	sw_from = blend
	sw_to = 0.0 if blend > 0.5 else 1.0
	sw_t = 0.0
	# The simulation reports a switch with the world being switched to.
	var to := "2d" if sw_to < 0.5 else "3d"
	if sound:
		audio.handle([{"t": "switch", "mode": to, "embedded": false}], {"mode": to})
	_mark("switch", {"to": to})
	_log("switch to the %s" % ("page" if to == "2d" else "stage"))


func _switching(delta: float) -> void:
	if sw_t < 0.0:
		audio.set_time_scale(1.0)
		return
	sw_t += delta
	var p := clampf(sw_t / SWITCH_TIME, 0.0, 1.0)
	var e := p if linear else p * p * (3.0 - 2.0 * p)
	blend = lerpf(sw_from, sw_to, e)
	# The game slows to about a third mid-turn, as the view does.
	audio.set_time_scale(1.0 - 0.66 * sin(PI * p))
	if p >= 1.0:
		sw_t = -1.0


func _mark(kind: String, data: Dictionary) -> void:
	data["t"] = t
	data["kind"] = kind
	marks.append(data)


func _log(what: String) -> void:
	var s: Dictionary = audio.stats()
	print("[%7.2f] %-9s beat %7.2f  %-6s blend %.2f restored %d voices %2d | %s" % [t, s.song, s.beat, s.harmony, blend, s.restored, s.voices, what])


func _finish() -> void:
	var s := audio.stats()
	print("tour done: %d sounds played, %d stolen, %d dropped" % [s.played, s.stolen, s.dropped])
	var f := FileAccess.open("user://audio_test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"marks": marks, "stats": s}))
	f.close()
	print("timeline: ", ProjectSettings.globalize_path("user://audio_test.json"))
	await audio.prepare_quit()
	get_tree().quit()

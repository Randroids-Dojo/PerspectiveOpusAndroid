extends SceneTree
## Headless checks for the pre-rendered audio:
##   $GODOT --headless --path . --script res://src/audio/dev/check.gd [-- --sync=finale,scherzo --speed=16]
##
## 1. Every file the manifest names loads, and every stem of a song has the same length
##    and loop point as the manifest says.
## 2. Every recipe, voice, one-shot, harmony and chord reference resolves.
## 3. Stems stay in sync: each stem of a song plays on its own player (all started in
##    one mix), fast-forwarded with the playback speed scale through several loops, and
##    their playback positions are compared every frame.
## 4. The engine node runs a song through switches, restores and every effect without
##    errors.
## Prints a summary and quits with exit code 1 on any problem.

const OpusAudioScript := preload("res://src/audio/audio.gd")
const ROOT := "res://assets/audio/"

var problems: Array[String] = []
var m: Dictionary
var args := {}


func _initialize() -> void:
	# Players only play once the tree is running.
	await process_frame
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	m = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "audio.json"))
	_check_files()
	_check_refs()
	await _check_sync()
	await _check_engine()
	if problems.is_empty():
		print("AUDIO CHECK OK")
	else:
		print("AUDIO CHECK FAILED: %d problems" % problems.size())
		for p in problems.slice(0, 40):
			print("  ", p)
	quit(1 if not problems.is_empty() else 0)


func _fail(msg: String) -> void:
	problems.append(msg)


func _load(path: String) -> AudioStreamOggVorbis:
	if not ResourceLoader.exists(ROOT + path):
		_fail("missing " + path)
		return null
	var s = load(ROOT + path)
	if not s is AudioStreamOggVorbis:
		_fail("not an Ogg Vorbis stream: " + path)
		return null
	return s


func _check_files() -> void:
	var n := 0
	var bytes := 0
	var seconds := 0.0
	for id in m.songs:
		var info: Dictionary = m.songs[id]
		var sr := float(info.sr)
		for st in info.stems:
			var s := _load(st.file)
			if s == null:
				continue
			n += 1
			bytes += FileAccess.get_file_as_bytes(ROOT + String(st.file)).size()
			seconds += s.get_length()
			if absf(s.get_length() - float(info.frames) / sr) > 0.5 / sr:
				_fail("%s: %.6f s, manifest says %.6f s" % [st.file, s.get_length(), float(info.frames) / sr])
		if bool(info.loop) and int(info.loopStart) + int(info.bodyFrames) != int(info.frames):
			_fail("%s: loop start + body != frames" % id)
		print("song %-9s %2d stems  %6.1f s  loop %s at %.3f s  intro %.3f s" % [id, info.stems.size(), float(info.frames) / sr, info.loop, float(info.loopStart) / sr, float(info.introFrames) / sr])
	var files := {}
	for k in m.sfx.voices:
		for bus in m.sfx.voices[k]:
			files[m.sfx.voices[k][bus]] = true
	for id in m.sfx.oneshots:
		for bus in m.sfx.oneshots[id]:
			for f in m.sfx.oneshots[id][bus]:
				files[f] = true
	for id in m.sfx.ambience.files:
		for f in m.sfx.ambience.files[id]:
			files[f] = true
	for id in m.beds:
		files[m.beds[id]] = true
	for f in files:
		var s := _load(f)
		if s != null:
			n += 1
			bytes += FileAccess.get_file_as_bytes(ROOT + String(f)).size()
			seconds += s.get_length()
	print("loaded %d files, %.1f MB, %.0f s of audio" % [n, bytes / 1048576.0, seconds])


func _check_refs() -> void:
	var nh: int = m.harmonies.size()
	var nr: int = m.sfx.recipes.size()
	if m.sfx.table.size() != nh:
		_fail("effects table has %d rows for %d harmonies" % [m.sfx.table.size(), nh])
	for h in m.harmonies:
		if int(h.f) < 0 or int(h.f) >= nh:
			_fail("bad fallback harmony")
	for id in m.songs:
		for part in ["intro", "body"]:
			var tl = m.songs[id][part]
			if tl == null:
				continue
			for c in tl.chords:
				if int(c[1]) < 0 or int(c[1]) >= nh:
					_fail("%s %s: chord harmony %d out of range" % [id, part, int(c[1])])
	var used := 0
	for row in m.sfx.table:
		for mode in ["page", "stage"]:
			var r: Dictionary = row[mode]
			var refs: Array = []
			refs.append_array(r.note)
			refs.append_array(r.switch)
			refs.append_array(r.keyOn)
			refs.append_array(r.keyOff)
			for k in ["checkpoint", "death", "respawn", "bounce", "gateOn", "gateOff", "exit"]:
				refs.append(r[k])
			for i in refs:
				if int(i) < 0 or int(i) >= nr:
					_fail("recipe index %d out of range" % int(i))
			used += refs.size()
		for k in row.ui:
			if int(row.ui[k]) >= nr:
				_fail("ui recipe out of range")
		for pair in row.jump:
			for e in pair:
				_check_entry(e)
	for r in m.sfx.recipes:
		for e in r.e:
			_check_entry(e)
	print("harmonies %d, recipes %d (%d references), voices %d, one-shot ids %d" % [nh, nr, used, m.sfx.voices.size(), m.sfx.oneshots.size()])


func _check_entry(e: Dictionary) -> void:
	if e.has("voice"):
		if not m.sfx.voices.has(e.voice) or not m.sfx.voices[e.voice].has(e.bus):
			_fail("voice %s on %s has no file" % [e.voice, e.bus])
	elif not m.sfx.oneshots.has(e.sfx) or not m.sfx.oneshots[e.sfx].has(e.bus):
		_fail("one-shot %s on %s has no file" % [e.sfx, e.bus])


## Separate players per stem, started together, fast-forwarded through several loops.
func _check_sync() -> void:
	var ids: PackedStringArray = String(args.get("sync", "finale,scherzo,title")).split(",")
	var speed := float(args.get("speed", "16"))
	for id in ids:
		var info: Dictionary = m.songs[id]
		var sr := float(info.sr)
		var players: Array[AudioStreamPlayer] = []
		for st in info.stems:
			var s := _load(st.file)
			s.loop = true
			s.loop_offset = (float(info.loopStart) + 0.5) / sr
			var p := AudioStreamPlayer.new()
			p.stream = s
			p.volume_db = -80.0
			root.add_child(p)
			players.append(p)
		AudioServer.playback_speed_scale = speed
		AudioServer.lock()
		for p in players:
			p.play()
		AudioServer.unlock()
		var length := float(info.frames) / sr
		var loop_len := float(info.bodyFrames) / sr
		var target_loops := 3
		var wraps := 0
		var last := 0.0
		var worst := 0.0
		var polls := 0
		var t0 := Time.get_ticks_msec()
		while wraps < target_loops and Time.get_ticks_msec() - t0 < 120000:
			await process_frame
			var lo := INF
			var hi := -INF
			# Read every position between two mixes.
			AudioServer.lock()
			for p in players:
				var pos := p.get_playback_position()
				lo = minf(lo, pos)
				hi = maxf(hi, pos)
			AudioServer.unlock()
			if hi - lo > worst:
				worst = hi - lo
			if lo + 1.0 < last:
				wraps += 1
				# Positions advance a mix (fast-forwarded) at a time, so allow that much past the loop start.
				if lo < float(info.loopStart) / sr - 0.001 or lo > float(info.loopStart) / sr + speed * 0.12:
					_fail("%s: wrapped to %.3f s, loop start is %.3f s" % [id, lo, float(info.loopStart) / sr])
			last = lo
			polls += 1
		AudioServer.playback_speed_scale = 1.0
		for p in players:
			p.queue_free()
		print("sync %-9s %2d stems, %d polls through %d loops of %.1f s (file %.1f s): largest position spread %.6f s" % [id, players.size(), polls, wraps, loop_len, length, worst])
		if wraps < target_loops:
			_fail("%s: only %d loops played (is the audio driver running?)" % [id, wraps])
		if worst > 0.0005:
			_fail("%s: stems drifted apart by %.6f s" % [id, worst])


## The engine itself: a song through switches, restores, every effect and menu sound.
func _check_engine() -> void:
	var a: Node = OpusAudioScript.new()
	a.log_sounds = args.has("log")
	root.add_child(a)
	await process_frame
	var fake := {"mode": "3d"}
	for id in ["title", "overture", "finale", "ending"]:
		a.preload_song(id)
		a.play_song(id)
		for f in 30:
			await process_frame
		for d in 8:
			a.set_restored(d, 7)
			a.set_perspective(d / 7.0)
			a.set_time_scale(1.0 - 0.66 * sin(PI * d / 7.0))
			await process_frame
		var ev: Array = []
		for mode in ["2d", "3d"]:
			ev.append_array([
				{"t": "step", "mode": mode, "surface": 3},
				{"t": "jump", "mode": mode},
				{"t": "land", "mode": mode, "impact": 12.0, "surface": 9},
				{"t": "bonk"},
				{"t": "note", "id": 0, "count": 3, "total": 7},
				{"t": "note", "id": 1, "count": 7, "total": 7},
				{"t": "checkpoint", "id": 0},
				{"t": "death", "cause": "thorn", "pos": null},
				{"t": "respawn"},
				{"t": "switch", "mode": mode, "embedded": true},
				{"t": "bounce", "id": 0},
				{"t": "key", "id": 0, "group": 4, "on": true},
				{"t": "gate", "group": 4, "on": false},
				{"t": "exit"},
			])
		# One event every few frames, as in play.
		for e in ev:
			a.handle([e], fake)
			for f in 4:
				await process_frame
		for u in OpusAudioScript.UI_SOUNDS:
			a.ui(u)
			for f in 4:
				await process_frame
		a.set_paused(true)
		for f in 20:
			await process_frame
		a.set_paused(false)
		var st: Dictionary = a.stats()
		print("engine %-9s beat %.2f harmony %s, %d sounds played, %d stolen, %d dropped, %d voices now" % [id, a.beat(), st.harmony, st.played, st.stolen, st.dropped, st.voices])
		if st.dropped > 0:
			_fail("%s: %d sounds dropped (polyphony)" % [id, st.dropped])
	a.stop_song(0.5)
	for f in 60:
		await process_frame
	await a.prepare_quit()
	a.queue_free()
	await process_frame

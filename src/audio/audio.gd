class_name OpusAudio
extends Node
## The sound of Perspective Opus, played from files that tools/render_audio.ts renders
## out of the web build's own engine (described by assets/audio/audio.json). It keeps
## the web build's interface and behaviour (src/audio in ../PerspectiveOpus):
##
##   music     One composition per movement, arranged twice: the score (close, a small
##             room) and the stage (wide, a hall). Every arrangement and restore layer
##             is a stem; one AudioStreamSynchronized plays them all on one clock, the
##             perspective crossfades the arrangements with equal power, and layers
##             fade in as notes are found. Intros play once (the loop starts after them).
##   effects   Every game event in a page and a stage version. Tonal effects were
##             recorded per harmony as recipes of notes, so a pickup or a cadence fits
##             the chord sounding at that moment. Notes are placed with sub-frame
##             accuracy (each file starts with a little silence to skip into).
##   ambience  Each movement's looped noise bed and its scattered birds, drips, clanks.
##   desk      Buses created in code: Music, Ambience, Sfx (SfxPage, SfxStage, UI), and
##             on Master the web build's compressor and limiter (with the makeup gain Web
##             Audio adds) before a hard limiter. Menus muffle the music; a switch
##             breathes it into its room.
##
## API (the web build's AudioEngine, in snake_case):
##   unlock()                      no-op on Android (kept for the shared interface)
##   set_perspective(blend)        0 score, 1 stage; every frame with the view blend
##   play_song(id), stop_song(fade = 1.5), preload_song(id)   (`preload` is a GDScript keyword)
##   set_restored(found, total)    layers return as notes are found
##   handle(events, game)          effects for this frame's simulation events
##   ui(name)                      hover, confirm, back, pause, resume, start, complete, unlock, page
##   beat() -> float               music position in beats as heard, or -1
##   set_volumes(master, music, sfx) or set_volumes({master, music, sfx}),
##   set_paused(paused), set_time_scale(s)
##   stats() -> Dictionary         diagnostics
##   prepare_quit()                await before get_tree().quit() for an exit with nothing leaked

const MANIFEST := "res://assets/audio/audio.json"
const ROOT := "res://assets/audio/"
const SONG_IDS: Array[String] = ["title", "overture", "adagio", "scherzo", "nocturne", "toccata", "finale", "ending"]
const UI_SOUNDS: Array[String] = ["hover", "confirm", "back", "pause", "resume", "start", "complete", "unlock", "page"]
## Surface materials by index (src/game/level.gd), and the ones with their own footsteps.
const MAT_NAMES: Array[String] = ["empty", "stone", "brick", "wood", "brass", "dark", "crystal", "leaf", "thorn", "marble"]
const STEP_MATS: Array[String] = ["stone", "brick", "wood", "brass", "dark", "crystal", "leaf", "marble"]

const BUS_MUSIC := &"Music"
## Each arrangement plays on its own bus (filter, then its room), into Music.
const BUS_ARR: Array[StringName] = [&"MusicScore", &"MusicStage"]
const BUS_AMB := &"Ambience"
const BUS_SFX := &"Sfx"
const BUS_PAGE := &"SfxPage"
const BUS_STAGE := &"SfxStage"
const BUS_UI := &"UI"
const BUS_AMB_PANS: Array[StringName] = [&"AmbLeft", &"AmbCentre", &"AmbRight"]
const AMB_PANS: Array[float] = [-0.6, 0.0, 0.6]
## Voices per effect bus. When a bus is full its oldest voice makes way, as in the web build.
## (Voices here carry their room's tail, so they last longer than the web build's dry ones.)
const VOICES := {&"SfxPage": 32, &"SfxStage": 40, &"UI": 12, &"AmbLeft": 6, &"AmbCentre": 6, &"AmbRight": 6}

## Longest wait for a song's files before it starts anyway.
const LOAD_WAIT := 1.4
## A switch slows the game to about 0.34 at its middle.
const SWITCH_SLOW := 0.66
## The web build's room sends (score: a small room, stage: a hall). A switch raises them
## by up to 1.5 times again, and the world being left keeps ringing in its room after its
## sound has faded (the crossfade comes before the room there). The stems carry the steady
## room; Godot reverbs shaped like each room add the rest.
const SEND: Array[float] = [0.42, 0.62]
## Godot's reverb at wet 1 is louder than the web's unit-energy rooms: measured 1.22 times
## the input level with the room's settings and 3.70 times with the hall's.
const ROOM_GAIN: Array[float] = [1.0 / 1.22, 1.0 / 3.70]

var unlocked := true

var _m: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}  # path -> AudioStream
var _warm: Array[String] = []  # paths loading in the background

# Music.
var _song: Song = null
var _fading: Array[Song] = []
var _wanted := ""
var _loading := ""
var _preloaded := ""
var _load_started := 0.0
var _restored := 0
var _blend := 1.0

# The desk.
var _vol := {"master": 1.0, "music": 1.0, "sfx": 1.0}
var _paused := false
var _switch := 0.0
var _music_tc := 0.05
var _cut_log := log(20000.0)
var _music_level := 1.0
var _wet: Array[float] = [0.0, 0.0]
var _heard: Array[float] = [-INF, -INF]
var _amb_level := 1.0
var _duck := 1.0
var _duck_at := -1.0
var _duck_depth := 1.0
var _duck_until := 0.0
var _duck_release := 1.0
var _bus := {}  # name -> index
var _lowpass: Array[AudioEffectLowPassFilter] = []
var _room: Array[AudioEffectReverb] = []

# Effects.
var _pre := 0.06
## Effect files are stored quieter than unit velocity; velocities are scaled back by this.
var _shot_gain := 1.0
var _poly := {}  # bus name -> AudioStreamPlaybackPolyphonic
var _poly_players: Array[AudioStreamPlayer] = []
var _queue: Array[Dictionary] = []
var _voices := {}  # bus name -> Array of [id, started]
var _last_variant := {}
var _last_step := -1.0
var _ui_last := -1.0
var _jump_idx := 0
var _last_h := 0
var _played := 0
var _dropped := 0
var _stolen := 0

# Ambience.
var _amb_id := ""
var _beds: Array[Dictionary] = []
var _amb_voices: Array[Dictionary] = []

## Prints every sound as it plays (the dev scene sets this).
var log_sounds := false
## Under Movie Maker the mix follows game time, not the wall clock.
var _movie := OS.has_feature("movie")
var _game_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var text := FileAccess.get_file_as_string(MANIFEST)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[audio] cannot read %s" % MANIFEST)
		return
	_m = parsed
	_pre = float(_m.sfx.pre)
	_shot_gain = float(_m.sfx.get("gain", 1.0))
	_last_h = int(_m.defaultHarmony)
	_setup_buses()
	for bus in [BUS_PAGE, BUS_STAGE, BUS_UI, BUS_AMB_PANS[0], BUS_AMB_PANS[1], BUS_AMB_PANS[2]]:
		var p := AudioStreamPlayer.new()
		var s := AudioStreamPolyphonic.new()
		# Room beyond the cap: a stolen voice frees its slot only at the next mix.
		s.polyphony = mini(int(VOICES[bus]) * 3, 128)
		p.stream = s
		p.bus = bus
		add_child(p)
		p.play()
		_poly_players.append(p)
		_poly[bus] = p.get_stream_playback()
		_voices[bus] = []
	# Load every effect in the background; the songs load when asked for (or preloaded).
	for path in _effect_files():
		if ResourceLoader.load_threaded_request(path) == OK:
			_warm.append(path)
	_apply_volumes()


# ------------------------------------------------------------------ the desk

func _setup_buses() -> void:
	var master := 0
	if AudioServer.get_bus_effect_count(master) == 0:
		# The web build's master chain. Web Audio compressors add their own makeup gain
		# (tools/render_audio.ts measures it in Chrome); Godot's need it set.
		var mk: Dictionary = _m.get("master", {})
		var comp := AudioEffectCompressor.new()
		# Chrome's -16 dB threshold has a 10 dB soft knee; above it the curve is a 2.5:1
		# line through -11 dB, which a hard knee there follows within half a decibel.
		comp.threshold = -11.0
		comp.ratio = 2.5
		comp.gain = float(mk.get("compMakeupDb", 3.99))
		comp.attack_us = 2000.0
		comp.release_ms = 250.0
		AudioServer.add_bus_effect(master, comp)
		var lim := AudioEffectCompressor.new()
		lim.threshold = -4.0
		lim.ratio = 20.0
		lim.gain = float(mk.get("limitMakeupDb", 2.28))
		lim.attack_us = 1000.0
		lim.release_ms = 80.0
		AudioServer.add_bus_effect(master, lim)
		# Never clip.
		var hard := AudioEffectHardLimiter.new()
		hard.ceiling_db = -0.3
		hard.release = 0.1
		AudioServer.add_bus_effect(master, hard)
	_bus[&"Master"] = master
	_add_bus(BUS_MUSIC, &"Master")
	_add_bus(BUS_AMB, &"Master")
	for i in 3:
		var b := _add_bus(BUS_AMB_PANS[i], BUS_AMB)
		if AudioServer.get_bus_effect_count(b) == 0:
			var pan := AudioEffectPanner.new()
			pan.pan = AMB_PANS[i]
			AudioServer.add_bus_effect(b, pan)
	_add_bus(BUS_SFX, &"Master")
	_add_bus(BUS_PAGE, BUS_SFX)
	_add_bus(BUS_STAGE, BUS_SFX)
	_add_bus(BUS_UI, BUS_SFX)
	for a in 2:
		var b := _add_bus(BUS_ARR[a], BUS_MUSIC)
		if AudioServer.get_bus_effect_count(b) == 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			lp.resonance = 0.5
			AudioServer.add_bus_effect(b, lp)
			var rv := AudioEffectReverb.new()
			# The score's small wooden room (RT60 0.55 s), the stage's hall (2.5 s); both
			# keep out of the low end like the web build's (high pass near 110 and 150 Hz).
			rv.room_size = 0.0 if a == 0 else 0.8
			rv.damping = 0.6 if a == 0 else 0.5
			rv.predelay_msec = 4.0 if a == 0 else 24.0
			rv.spread = 1.0
			rv.hipass = 0.02
			rv.dry = 1.0
			rv.wet = 0.0
			AudioServer.add_bus_effect(b, rv)
		_lowpass.append(AudioServer.get_bus_effect(b, 0))
		_room.append(AudioServer.get_bus_effect(b, 1))
		AudioServer.set_bus_effect_enabled(b, 0, false)
		AudioServer.set_bus_effect_enabled(b, 1, false)


func _add_bus(name: StringName, send: StringName) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	_bus[name] = i
	return i


## Faders 0..1: set_volumes(master, music, sfx), or one Dictionary {master, music, sfx}
## as the web build's setVolumes takes.
func set_volumes(master, music = null, sfx = null) -> void:
	var v := {"master": master, "music": music, "sfx": sfx}
	if master is Dictionary:
		v = master
	var fader := func(x) -> float:
		# Faders feel even when squared.
		return pow(clampf(float(x) if x != null else 1.0, 0.0, 1.0), 2.0)
	_vol = {"master": fader.call(v.get("master")), "music": fader.call(v.get("music")), "sfx": fader.call(v.get("sfx"))}
	_music_tc = 0.05
	_apply_volumes()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_bus[&"Master"], _db(_vol.master))
	AudioServer.set_bus_volume_db(_bus[BUS_SFX], _db(_vol.sfx))


## Muffles the music (and quietens the ambience) under menus.
func set_paused(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	_music_tc = 0.12 if paused else 0.2


## Game-time multiplier while the world turns: the music breathes into its room.
func set_time_scale(s: float) -> void:
	var w := clampf((1.0 - clampf(s, 0.0, 1.0)) / SWITCH_SLOW, 0.0, 1.0)
	if absf(w - _switch) < 0.004:
		return
	_switch = w
	_music_tc = 0.03


func _update_desk(dt: float) -> void:
	var w := _switch
	var paused_cut := 750.0 if _paused else 20000.0
	var switch_cut := exp(log(20000.0) + (log(2400.0) - log(20000.0)) * pow(w, 0.8))
	var k := 1.0 - exp(-dt / maxf(0.005, _music_tc))
	_cut_log += (log(minf(paused_cut, switch_cut)) - _cut_log) * k
	var level: float = _vol.music * (0.42 if _paused else 1.0) * (1.0 - 0.2 * w)
	_music_level += (level - _music_level) * k
	# The music dips for a moment on a death, the seventh note and the exit cadence.
	var now := _clock()
	if _duck_at >= 0.0 and now >= _duck_at:
		var target := _duck_depth if now < _duck_until else 1.0
		var tc := 0.04 if now < _duck_until else _duck_release / 3.0
		_duck += (target - _duck) * (1.0 - exp(-dt / tc))
		if now >= _duck_until and absf(_duck - 1.0) < 0.001:
			_duck = 1.0
			_duck_at = -1.0
	AudioServer.set_bus_volume_db(_bus[BUS_MUSIC], _db(_music_level * _duck))
	var cut := exp(_cut_log)
	var filtering := cut < 19000.0
	var arr := [cos(_blend * PI * 0.5), sin(_blend * PI * 0.5)]
	for a in 2:
		var b: int = _bus[BUS_ARR[a]]
		if filtering:
			_lowpass[a].cutoff_hz = cut
		if AudioServer.is_bus_effect_enabled(b, 0) != filtering:
			AudioServer.set_bus_effect_enabled(b, 0, filtering)
		# The room's extra: the switch's raised send, and the ring of a world being left.
		var g: float = arr[a]
		if g > 0.001:
			_heard[a] = now
		# The web build raises the send to 1 + 1.5w of itself, adding coherently to the room the
		# stems already carry; a separate room matches that energy at sqrt((1 + 1.5w)^2 - 1).
		var boost := sqrt(pow(1.0 + 1.5 * w, 2.0) - 1.0)
		var target: float = SEND[a] * ROOM_GAIN[a] * (boost + (1.0 - g))
		_wet[a] += (target - _wet[a]) * (1.0 - exp(-dt / (0.03 if target > _wet[a] else 0.6)))
		# Off once its room has rung out with nothing new coming in.
		var on := _wet[a] > 0.002 and now - _heard[a] < 4.0
		if on:
			_room[a].wet = _wet[a]
		if AudioServer.is_bus_effect_enabled(b, 1) != on:
			AudioServer.set_bus_effect_enabled(b, 1, on)
	# Ambience: under the music, louder on the stage, quieter in menus.
	_amb_level += (0.35 + 0.65 * _blend - _amb_level) * (1.0 - exp(-dt / 0.2))
	var amb: float = _vol.sfx * (0.4 if _paused else 1.0) * _amb_level
	AudioServer.set_bus_volume_db(_bus[BUS_AMB], _db(amb))


func _duck_music(depth: float, hold: float, release: float, at: float) -> void:
	_duck_at = at
	_duck_depth = depth
	_duck_until = at + hold
	_duck_release = release


# ------------------------------------------------------------------ the two worlds

## 0 = score arrangement, 1 = stage arrangement. Called every frame with the view blend.
func set_perspective(blend: float) -> void:
	_blend = clampf(blend, 0.0, 1.0)


## Starts the audio. Nothing to unlock on Android; kept for the shared interface.
func unlock() -> void:
	unlocked = true


# ------------------------------------------------------------------ music

func play_song(id: String) -> void:
	if _m.is_empty() or not _m.songs.has(id):
		return
	if _wanted == id and ((_song != null and _song.id == id) or _loading == id):
		return
	_wanted = id
	_loading = id
	_load_started = _clock()
	_request_song(id)
	_try_start()


## Loads a song's files ahead of time (for example while a menu is open).
func preload_song(id: String) -> void:
	if _m.is_empty() or not _m.songs.has(id):
		return
	_preloaded = id
	_request_song(id)


func stop_song(fade := 1.5) -> void:
	_wanted = ""
	_loading = ""
	if _song != null:
		_song.fade_out(fade, _clock())
		_fading.append(_song)
		_song = null
	_amb_stop(fade)


## How much of the movement's music has been restored (notes found of total).
func set_restored(found: int, total: int) -> void:
	_restored = clampi(roundi(float(found) / float(total) * 7.0), 0, 7) if total > 0 else 0


func _song_files(id: String) -> Array[String]:
	var out: Array[String] = []
	for st in _m.songs[id].stems:
		out.append(ROOT + String(st.file))
	return out


func _request_song(id: String) -> void:
	for path in _song_files(id):
		if not _streams.has(path) and not _warm.has(path):
			if ResourceLoader.load_threaded_request(path) == OK:
				_warm.append(path)


func _try_start() -> void:
	if _loading == "":
		return
	var files := _song_files(_loading)
	var ready := true
	for path in files:
		if not _streams.has(path) and _warm.has(path) and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			ready = false
	if not ready and _clock() - _load_started < LOAD_WAIT:
		return
	var id := _loading
	_loading = ""
	_start_song(id)


func _start_song(id: String) -> void:
	var now := _clock()
	if _song != null:
		_song.fade_out(1.2, now)
		_fading.append(_song)
	var info: Dictionary = _m.songs[id]
	var stems: Array[AudioStream] = []
	for path in _song_files(id):
		var s := _stream(path) as AudioStreamOggVorbis
		s.loop = bool(info.loop)
		# Half a frame past the loop start, so seconds -> frames never truncates a frame short.
		s.loop_offset = (float(info.loopStart) + 0.5) / float(info.sr)
		stems.append(s)
	_song = Song.new(id, info, stems, _restored, _blend, self)
	_song.play()
	_evict()
	_amb_start(String(info.ambience) if info.ambience != null else "")
	if log_sounds:
		print("[audio] song %s: %d stems, restored %d" % [id, stems.size(), _restored])


## Lets go of the stems of songs that are not playing, fading, loading or preloaded.
func _evict() -> void:
	var keep := {}
	for id in [_wanted, _loading, _preloaded]:
		keep[id] = true
	for s in _fading:
		keep[s.id] = true
	for id in SONG_IDS:
		if keep.has(id) or not _m.songs.has(id):
			continue
		for path in _song_files(id):
			_streams.erase(path)


func _update_music(dt: float) -> void:
	_try_start()
	var now := _clock()
	if _song != null:
		_song.restored = _restored
		_song.update(dt, _blend)
		if _song.finished():
			_song.free_players()
			_song = null
	for i in range(_fading.size() - 1, -1, -1):
		var f := _fading[i]
		f.update(dt, _blend)
		if now > f.stop_at or f.finished():
			f.free_players()
			_fading.remove_at(i)


## Music position in beats as heard (output latency corrected), or -1 when silent.
func beat() -> float:
	if _song == null or not _song.playing():
		return -1.0
	var t := _song.time_mix() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return _song.beat_at(t)


## The harmony (index into the manifest) sounding `ahead` seconds after the next mix.
func _harmony(ahead := 0.0) -> int:
	if _song != null and _song.playing():
		var h := _song.harmony_at(_song.time_mix() + ahead)
		if h >= 0:
			_last_h = int(_m.harmonies[h].f)
			return h
	return _last_h


## Seconds from now to the next beat boundary (multiples of `div`) after `after` seconds.
func _next_beat(after: float, div := 1.0) -> float:
	if _song == null or not _song.playing():
		return after
	var t := _song.time_mix() + after
	var b := _song.beat_at(t)
	if b < 0.0:
		return after
	var nb := ceilf(b / div - 1e-6) * div
	return after + (nb - b) * 60.0 / _song.bpm_at(t)


# ------------------------------------------------------------------ effects

## Sound effects for this frame's simulation events (page or stage by each event's mode).
func handle(events: Array, game = null) -> void:
	if _m.is_empty():
		return
	var mode := "3d"
	if game is Object and game.get("mode") != null:
		mode = String(game.get("mode"))
	for e in events:
		_event(e, String(e.get("mode", mode)))
	_flush()


func _event(e: Dictionary, mode: String) -> void:
	var page := mode == "2d"
	var m := "page" if page else "stage"
	var bus := BUS_PAGE if page else BUS_STAGE
	var t := _mix_time()
	match String(e.t):
		"step":
			if t - _last_step < 0.09:
				return
			_last_step = t
			_shot("step.%s.%s" % [m, _mat(e.surface)], m, t, 0.42 if page else 0.3, 0.94 + _rng.randf() * 0.12)
		"jump":
			_shot("jump." + m, m, t, 0.46 if page else 0.32, 0.95 + _rng.randf() * 0.1)
			var tones: Array = _row().jump
			if not tones.is_empty():
				var pair: Array = tones[_jump_idx % tones.size()]
				_jump_idx += 1
				_entry(pair[0 if page else 1], t)
		"land":
			var impact := float(e.impact)
			var k := clampf((impact - 4.0) / 14.0, 0.0, 1.0)
			var step := "step.%s.%s" % [m, _mat(e.surface)]
			if impact < 3.0:
				_shot(step, m, t, 0.34 if page else 0.24)
				return
			_shot("land." + m, m, t, (0.2 + 0.34 * k) if page else (0.1 + 0.22 * k), 1.05 - 0.12 * k)
			_shot(step, m, t + 0.004, (0.34 + 0.25 * k) if page else (0.22 + 0.16 * k))
		"bonk":
			_shot("bonk." + m, m, t, 0.56 if page else 0.38)
		"note":
			var total := maxi(1, int(e.total))
			var d := clampi(roundi(float(e.count) / float(total) * 7.0), 1, 7)
			_recipe(_row()[m].note[d - 1], t)
		"checkpoint":
			# A click now, a second on the next beat with the chord.
			_shot("metronome", m, t, 0.5, 1.0, 0)
			var ahead := minf(_next_beat(0.08), 0.45)
			_recipe(_row(ahead)[m].checkpoint, t + ahead)
		"death":
			_recipe(_row()[m].death, t)
		"respawn":
			_recipe(_row(0.45)[m].respawn, t)
		"switch":
			_recipe(_row()[m].switch[1 if bool(e.get("embedded", false)) else 0], t)
		"bounce":
			_recipe(_row()[m].bounce, t)
		"key":
			var list: Array = _row()[m].keyOn if bool(e.on) else _row()[m].keyOff
			_recipe(list[clampi(int(e.group), 0, list.size() - 1)], t)
		"gate":
			_recipe(_row()[m].gateOn if bool(e.on) else _row()[m].gateOff, t)
		"exit":
			_recipe(_row()[m].exit, t)


## Menu sounds: hover, confirm, back, pause, resume, start, complete, unlock, page.
func ui(name: String) -> void:
	if _m.is_empty():
		return
	var t := _mix_time()
	match name:
		"hover":
			if t - _ui_last < 0.04:
				return
			_ui_last = t
			_shot("tap", "ui", t, 0.42, 1.0 + _rng.randf() * 0.1)
		"page":
			_shot("pageturn", "ui", t, 0.42)
		_:
			var row: Dictionary = _row().ui
			if row.has(name):
				_recipe(row[name], t)
	_flush()


func _row(ahead := 0.0) -> Dictionary:
	return _m.sfx.table[_harmony(ahead)]


func _mat(surface) -> String:
	var i := int(surface)
	var name := MAT_NAMES[i] if i >= 0 and i < MAT_NAMES.size() else "stone"
	return name if STEP_MATS.has(name) else "stone"


func _recipe(index: int, at: float) -> void:
	var r: Dictionary = _m.sfx.recipes[index]
	if r.has("duck"):
		var d: Array = r.duck
		_duck_music(float(d[0]), float(d[1]), float(d[2]), at + float(d[3]))
	for e in r.e:
		_entry(e, at)


func _entry(e: Dictionary, at: float) -> void:
	var when := at + float(e.at)
	if e.has("voice"):
		var files: Dictionary = _m.sfx.voices[e.voice]
		_schedule(when, ROOT + String(files[e.bus]), float(e.vel), 1.0, String(e.bus))
	else:
		_shot(String(e.sfx), String(e.bus), when, float(e.vel), float(e.get("rate", 1.0)), int(e.get("variant", -1)))


## A one-shot sample: a variant (random, never the same twice running, unless given).
func _shot(id: String, bus: String, at: float, vel: float, rate := 1.0, variant := -1) -> void:
	var by_bus: Dictionary = _m.sfx.oneshots.get(id, {})
	if not by_bus.has(bus):
		return
	var files: Array = by_bus[bus]
	var v := variant
	if v < 0:
		v = _rng.randi() % files.size()
		if files.size() > 1 and v == int(_last_variant.get(id, -1)):
			v = (v + 1) % files.size()
	_last_variant[id] = v
	_schedule(at, ROOT + String(files[clampi(v, 0, files.size() - 1)]), vel, rate, bus)


func _schedule(at: float, path: String, vel: float, rate: float, bus: String) -> void:
	if vel <= 0.0:
		return
	var b: StringName = BUS_PAGE if bus == "page" else BUS_STAGE if bus == "stage" else BUS_UI if bus == "ui" else StringName(bus)
	_queue.append({"at": at, "path": path, "vel": vel * _shot_gain, "rate": rate, "bus": b})


## Starts every queued sound whose onset falls within the files' lead-in, skipping into
## that silence so the onset lands exactly where it was scheduled.
func _flush() -> void:
	if _queue.is_empty():
		return
	var mix := _mix_time()
	var keep: Array[Dictionary] = []
	for v in _queue:
		var rate: float = v.rate
		var ahead: float = (float(v.at) - mix) * rate
		if ahead > _pre:
			keep.append(v)
			continue
		var from := clampf(_pre - ahead, 0.0, _pre)
		var s := _stream(v.path)
		var pb: AudioStreamPlaybackPolyphonic = _poly[v.bus]
		var list: Array = _voices[v.bus]
		if list.size() >= int(VOICES[v.bus]):
			_prune(v.bus)
			if list.size() >= int(VOICES[v.bus]):
				pb.stop_stream(list.pop_front()[0])
				_stolen += 1
		var id := pb.play_stream(s, from, _db(v.vel), rate, AudioServer.PLAYBACK_TYPE_DEFAULT, v.bus)
		if id == AudioStreamPlaybackPolyphonic.INVALID_ID:
			_dropped += 1
			if log_sounds:
				print("[audio]   dropped on %s (%d voices)" % [v.bus, list.size()])
			continue
		_played += 1
		list.append([id, mix])
		if log_sounds:
			print("[audio]   %s %s vel %.3f rate %.3f late %.1f ms" % [v.bus, String(v.path).get_file(), v.vel, rate, maxf(0.0, -ahead / rate) * 1000.0])
	_queue = keep


# ------------------------------------------------------------------ ambience

func _amb_start(id: String) -> void:
	if id == _amb_id:
		return
	_amb_stop(1.5)
	_amb_id = id
	if id == "" or not _m.beds.has(id):
		return
	var s := _stream(ROOT + String(_m.beds[id])) as AudioStreamOggVorbis
	s.loop = true
	s.loop_offset = 0.0
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = BUS_AMB
	p.volume_db = -80.0
	add_child(p)
	p.play(_rng.randf() * s.get_length() * 0.8)
	_beds.append({"player": p, "gain": 0.0, "target": 1.0, "tc": 1.2, "stop_at": INF})
	var now := _clock()
	for spec in _m.sfx.ambience.events[id]:
		var n := int(spec.get("chorus", 1))
		for i in n:
			_amb_voices.append({
				"spec": spec,
				"next": now + _rng.randf_range(1.0, 4.0),
				"period": _rng.randf_range(float(spec.every[0]), float(spec.every[1])),
				"rate": _rng.randf_range(float(spec.rate[0]), float(spec.rate[1])),
				"pan": _rng.randi() % 3,
				"rest": 0.0,
			})


func _amb_stop(fade: float) -> void:
	_amb_id = ""
	_amb_voices.clear()
	var now := _clock()
	for b in _beds:
		if b.target > 0.0:
			b.target = 0.0
			b.tc = maxf(0.02, fade) / 4.0
			b.stop_at = now + fade + 0.1


func _update_ambience(dt: float) -> void:
	var now := _clock()
	for i in range(_beds.size() - 1, -1, -1):
		var b: Dictionary = _beds[i]
		b.gain += (float(b.target) - float(b.gain)) * (1.0 - exp(-dt / float(b.tc)))
		var p: AudioStreamPlayer = b.player
		p.volume_db = _db(b.gain)
		if now > float(b.stop_at):
			p.queue_free()
			_beds.remove_at(i)
	if _amb_id == "":
		return
	var until := now + 0.3
	var files: Dictionary = _m.sfx.ambience.files
	for v in _amb_voices:
		var spec: Dictionary = v.spec
		var chorus := spec.has("chorus")
		while float(v.next) < until:
			var at := float(v.next)
			if chorus:
				# Crickets keep a steady period, and rest now and then.
				v.next = at + float(v.period) * _rng.randf_range(0.97, 1.03)
				if at < float(v.rest):
					continue
				if _rng.randf() < 0.04:
					v.rest = at + _rng.randf_range(2.0, 6.0)
			else:
				v.next = at + _rng.randf_range(float(spec.every[0]), float(spec.every[1]))
			if at < now:
				continue
			var list: Array = files[spec.id]
			var path := ROOT + String(list[_rng.randi() % list.size()])
			var rate: float = float(v.rate) if chorus else _rng.randf_range(float(spec.rate[0]), float(spec.rate[1]))
			var pan: int = int(v.pan) if chorus else _rng.randi() % 3
			_schedule(at, path, _rng.randf_range(float(spec.gain[0]), float(spec.gain[1])), rate, String(BUS_AMB_PANS[pan]))


# ------------------------------------------------------------------ the loop

func _exit_tree() -> void:
	release()


## For a clean exit: stops and releases everything, then waits until the audio server has
## dropped its playbacks (it deletes them on the main thread a frame after they stop, and
## no frame runs after quit()). `await audio.prepare_quit()` before `get_tree().quit()`.
func prepare_quit() -> void:
	release()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame


## Stops every sound and lets go of every stream, so nothing is left playing or loaded
## (called when the node leaves the tree, for example when the game quits).
func release() -> void:
	for bus in _poly:
		var pb: AudioStreamPlaybackPolyphonic = _poly[bus]
		for v in _voices[bus]:
			pb.stop_stream(v[0])
	for p in _poly_players:
		p.stop()
		p.stream = null
	_poly.clear()
	_poly_players.clear()
	_voices.clear()
	_queue.clear()
	for s in [_song] + _fading:
		if s != null:
			s.release()
	_song = null
	_fading.clear()
	_loading = ""
	_wanted = ""
	for b in _beds:
		var p: AudioStreamPlayer = b.player
		p.stop()
		p.stream = null
	_beds.clear()
	_amb_voices.clear()
	_amb_id = ""
	# Collect background loads still held by the loader, then drop everything.
	for path in _warm:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_warm.clear()
	_streams.clear()
	_m = {}


func _process(delta: float) -> void:
	if _m.is_empty():
		return
	_game_time += delta
	var dt := minf(delta, 0.1)
	_warm_up()
	_update_music(dt)
	_update_ambience(dt)
	_update_desk(dt)
	_flush()
	if Engine.get_process_frames() % 30 == 0:
		for bus in _voices:
			_prune(bus)


func _warm_up() -> void:
	# Move finished background loads into the cache, a few per frame.
	var n := 0
	for i in range(_warm.size() - 1, -1, -1):
		var path := _warm[i]
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_streams[path] = ResourceLoader.load_threaded_get(path)
			_warm.remove_at(i)
			n += 1
			if n >= 24:
				return
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_warm.remove_at(i)


func _stream(path: String) -> AudioStream:
	var s: AudioStream = _streams.get(path)
	if s == null:
		if _warm.has(path):
			s = ResourceLoader.load_threaded_get(path)
			_warm.erase(path)
		else:
			s = load(path)
		_streams[path] = s
	return s


func _prune(bus: StringName) -> void:
	var pb: AudioStreamPlaybackPolyphonic = _poly[bus]
	var list: Array = _voices[bus]
	for i in range(list.size() - 1, -1, -1):
		if not pb.is_stream_playing(list[i][0]):
			list.remove_at(i)


func _effect_files() -> Array[String]:
	var out: Array[String] = []
	for k in _m.sfx.voices:
		for bus in _m.sfx.voices[k]:
			out.append(ROOT + String(_m.sfx.voices[k][bus]))
	for id in _m.sfx.oneshots:
		for bus in _m.sfx.oneshots[id]:
			for f in _m.sfx.oneshots[id][bus]:
				out.append(ROOT + String(f))
	for id in _m.sfx.ambience.files:
		for f in _m.sfx.ambience.files[id]:
			out.append(ROOT + String(f))
	for id in _m.beds:
		out.append(ROOT + String(_m.beds[id]))
	return out


func _clock() -> float:
	return _game_time if _movie else float(Time.get_ticks_usec()) * 1e-6


## When the next mix begins: a sound started now is first heard from there.
func _mix_time() -> float:
	var ttn := 0.0 if _movie else AudioServer.get_time_to_next_mix()
	return _clock() + (ttn if ttn > 0.0 and ttn < 0.05 else 0.0)


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 1e-6))


## Diagnostics, like the web build's stats().
func stats() -> Dictionary:
	return {
		"song": _song.id if _song != null else "",
		"loading": _loading,
		"restored": _restored,
		"blend": _blend,
		"beat": beat(),
		"harmony": String(_m.harmonies[_harmony()].symbol) if not _m.is_empty() else "",
		"voices": _voices.values().reduce(func(n, l): return n + l.size(), 0),
		"queued": _queue.size(),
		"played": _played,
		"dropped": _dropped,
		"stolen": _stolen,
		"fading_songs": _fading.size(),
		"ambience": _amb_id,
		"loaded_files": _streams.size(),
		"loading_files": _warm.size(),
		"mix_rate": AudioServer.get_mix_rate(),
		"output_latency": AudioServer.get_output_latency(),
	}


# ------------------------------------------------------------------ a playing song

class Song:
	## One playing song: its stems on one clock, their gains, and where it is. Each
	## arrangement's stems play in an AudioStreamSynchronized on that arrangement's bus;
	## the two start in the same mix, and every stem has the same length and loop point.
	var id: String
	var info: Dictionary
	var players: Array[AudioStreamPlayer] = []
	var syncs: Array[AudioStreamSynchronized] = []
	var stems: Array[Dictionary] = []
	var full: bool
	var loop: bool
	var sr: float
	var intro_s: float
	var body_s: float
	var gain := 0.0
	var target := 1.0
	var tc := 0.4 / 3.0
	var stop_at := INF
	var wraps := 0
	var last_pos := 0.0
	var started := false
	## Notes restored (0 to 7). Only the current song follows changes; a fading one keeps its own.
	var restored := 0

	func _init(song_id: String, song: Dictionary, streams: Array[AudioStream], level: int, blend: float, parent: Node) -> void:
		id = song_id
		info = song
		full = bool(song.full)
		loop = bool(song.loop)
		sr = float(song.sr)
		intro_s = float(song.introFrames) / sr
		body_s = float(song.bodyFrames) / sr
		restored = level
		var count := [0, 0]
		for st in song.stems:
			count[1 if st.arr == "stage" else 0] += 1
		for a in 2:
			var sync := AudioStreamSynchronized.new()
			sync.stream_count = count[a]
			syncs.append(sync)
			var p := AudioStreamPlayer.new()
			p.stream = sync
			p.bus = BUS_ARR[a]
			p.volume_db = -80.0
			parent.add_child(p)
			players.append(p)
		var slot := [0, 0]
		for i in streams.size():
			var st: Dictionary = song.stems[i]
			var a := 1 if st.arr == "stage" else 0
			var on := full or int(st.layer) <= level
			stems.append({"arr": a, "slot": slot[a], "layer": int(st.layer), "fade": float(st.fade), "g": 1.0 if on else 0.0, "db": 0.0})
			syncs[a].set_sync_stream(slot[a], streams[i])
			slot[a] += 1
		_apply(blend)

	## Starts both arrangements in the same mix.
	func play() -> void:
		AudioServer.lock()
		for p in players:
			p.play()
		AudioServer.unlock()

	func playing() -> bool:
		return players[0].playing or players[1].playing

	func free_players() -> void:
		release()
		for p in players:
			p.queue_free()

	func release() -> void:
		for p in players:
			p.stop()
			p.stream = null
		for sync in syncs:
			for i in sync.stream_count:
				sync.set_sync_stream(i, null)
		syncs.clear()

	func fade_out(seconds: float, now: float) -> void:
		target = 0.0
		tc = maxf(0.02, seconds) / 4.0
		stop_at = minf(stop_at, now + seconds + 0.5)

	func update(dt: float, blend: float) -> void:
		gain += (target - gain) * (1.0 - exp(-dt / tc))
		for p in players:
			p.volume_db = linear_to_db(maxf(gain, 1e-6))
		for st in stems:
			var on := full or int(st.layer) <= restored
			var t := float(st.fade) / 3.0 if on else 0.5
			st.g = float(st.g) + ((1.0 if on else 0.0) - float(st.g)) * (1.0 - exp(-dt / t))
		_apply(blend)
		var pos := players[0].get_playback_position()
		if playing():
			started = true
			if pos + 1.0 < last_pos:
				wraps += 1
			last_pos = pos

	func _apply(blend: float) -> void:
		# Equal power: score cos, stage sin, before each arrangement's room.
		var a := blend * PI * 0.5
		var arr := [cos(a), sin(a)]
		for st in stems:
			var db := linear_to_db(maxf(float(arr[st.arr]) * float(st.g), 1e-6))
			if absf(db - float(st.db)) > 0.01:
				st.db = db
				syncs[st.arr].set_sync_stream_volume(st.slot, db)

	func finished() -> bool:
		return started and not playing()

	## Seconds into the song's timeline (intro, then the body pass after pass) at the next mix.
	func time_mix() -> float:
		var pos := players[0].get_playback_position()
		var w := wraps
		if pos + 1.0 < last_pos:
			w += 1
		return pos + float(w) * body_s

	func _locate(t: float) -> Array:
		# [timeline, seconds into it, beats before it], or [] when outside the song.
		if t < 0.0:
			return []
		if info.intro != null and t < intro_s:
			return [info.intro, t, 0.0]
		var b := t - intro_s
		var intro_beats := float(info.intro.beats) if info.intro != null else 0.0
		if not loop:
			return [info.body, b, intro_beats] if b < float(info.body.duration) else []
		var k := floorf(b / body_s)
		return [info.body, b - k * body_s, intro_beats + k * float(info.body.beats)]

	func beat_at(t: float) -> float:
		var l := _locate(t)
		if l.is_empty():
			return -1.0
		var tempo: Array = l[0].tempo
		var a: Dictionary = tempo[0]
		for x in tempo:
			if float(x.t) <= float(l[1]):
				a = x
		return float(l[2]) + float(a.beat) + (float(l[1]) - float(a.t)) * float(a.bpm) / 60.0

	func bpm_at(t: float) -> float:
		var l := _locate(t)
		if l.is_empty():
			return float(info.bpm)
		var bpm := float(info.bpm)
		for x in l[0].tempo:
			if float(x.t) <= float(l[1]):
				bpm = float(x.bpm)
		return bpm

	func harmony_at(t: float) -> int:
		var l := _locate(maxf(t, 0.0))
		if l.is_empty():
			return -1
		var c: Array = l[0].chords
		var lo := 0
		var hi := c.size() - 1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if float(c[mid][0]) <= float(l[1]):
				lo = mid
			else:
				hi = mid - 1
		return int(c[lo][1]) if c.size() > 0 else -1

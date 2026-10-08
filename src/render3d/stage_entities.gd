class_name StageEntities
extends RefCounted
## The cast and props the simulation moves (notes, metronomes, the Fermata arch, drums,
## piano keys, staff gates, music-stand platforms, Discords), animated from game state:
## a port of the web Stage's entities.ts and gates.ts updates. The meshes are baked.

const DISCORD_RED_HEX := "#ff3a2a"

var _bake: StageBake
var _lv: Level
var _notes: Array = []
var _checks: Array = []
var _drums: Array = []
var _keys: Array = []
var _gates: Array = []
var _plats: Array = []
var _discords: Array = []
var _veil_mats: Array = []
var _fermata: Node3D
var _gold := Vector3.ONE
var _red := StageUtil.col(DISCORD_RED_HEX)


func setup(bake: StageBake, lv: Level) -> void:
	_bake = bake
	_lv = lv
	var s: Dictionary = bake.module("entities")
	_notes = s.notes
	_checks = s.checks
	_drums = s.drums
	_keys = s.keys
	_gates = s.gates
	_plats = s.plats
	_discords = s.discords
	_veil_mats = bake.mats_of(s.veil)
	_fermata = s.fermata
	_gold = s.glowCol
	for c in _checks:
		c.lamp_mats = [(c.lamp as MeshInstance3D).material_override]
	for k in _keys:
		k.inlay_mats = bake.mats_of(k.inlay)
	for g in _gates:
		var gd: Dictionary = lv.gates[int(g.i)]
		var mn: V3 = gd.min
		var mx: V3 = gd.max
		var sx := mx.x - mn.x
		var sy := mx.y - mn.y
		var sz := mx.z - mn.z
		var axis_z := sz > sx
		var length := sz if axis_z else sx
		var upright := sy > 1.01 or length <= 1.0
		var sweep := Vector4(0, 1.0 / sy, 0, 0) if upright else (Vector4(0, 0, 1.0 / length, 0.5) if axis_z else Vector4(1.0 / length, 0, 0, 0.5))
		var body := g.body as GeometryInstance3D
		body.material_override.set_shader_parameter("sweep", sweep)
		g.body_mat = body.material_override
		g.ghost_mats = [(g.ghost as GeometryInstance3D).material_override]


func update(game: Sim, frame: Dictionary, halos: StageEffects.Halos, feet: Vector3, clock: float) -> void:
	var lv := _lv
	var t := game.time
	var a: float = frame.alpha
	var gold := _gold

	for n in _notes:
		var i := int(n.i)
		var mesh: Node3D = n.mesh
		var pos: V3 = lv.notes[i].pos
		var taken: bool = game.notes_taken[i]
		var since := t - game.note_taken_at[i] if taken else 0.0
		if taken and since > 0.35:
			mesh.visible = false
			continue
		mesh.visible = true
		var bob := sin(clock * 2.1 + i * 1.7) * 0.07
		mesh.position = Vector3(pos.x, pos.y + bob + (since * 2.5 if taken else 0.0), pos.z)
		mesh.rotation.y = clock * 1.4 + i * 0.9 + (since * 30.0 if taken else 0.0)
		var s := maxf(0.01, 1.0 - since / 0.35) * (1.0 + since * 2.0) if taken else 1.0
		mesh.scale = Vector3.ONE * (s * 1.05)
		halos.add(pos.x, pos.y + bob, pos.z, 1.1 * s, gold, 0.45 + sin(clock * 3.0 + i) * 0.08)

	var beat: float = frame.beat if float(frame.beat) >= 0.0 else t * 1.6
	for c in _checks:
		var i := int(c.i)
		var on := game.checkpoint_on == i
		var lit := game.checkpoint_at[i] >= 0.0
		var target := 1.0 if on else 0.0
		c.swing += (target - float(c.swing)) * minf(1.0, float(frame.dt) * 3.0)
		(c.arm as Node3D).rotation.z = cos(PI * beat) * 0.42 * c.swing + (1.0 - c.swing) * 0.05
		var k := 1.0 if on else (0.35 if lit else 0.0)
		for m in c.lamp_mats:
			m.set_shader_parameter("color", gold * (0.25 + k * 2.6))
		var p: V3 = lv.checkpoints[i].pos
		if k > 0.0:
			halos.add(p.x, p.y + 1.12, p.z - 0.03, 0.9 + k * 0.4, gold, 0.25 + 0.35 * k)

	if not _veil_mats.is_empty() and _fermata != null:
		var ex := lv.exit_pos
		var d := Vector3(feet.x - ex.x, (feet.y - ex.y) * 0.5, (feet.z - ex.z) * 0.6).length()
		var near := clampf(1.0 - (d - 1.0) / 7.0, 0.0, 1.0)
		var fin := clampf((t - game.finished_at) / 0.8, 0.0, 1.0) if game.finished else 0.0
		for m in _veil_mats:
			m.set_shader_parameter("time", clock)
			m.set_shader_parameter("glow", 0.35 + near * 0.55 + fin * 0.8)
		_fermata.rotation.y = sin(clock * 0.8) * 0.25
		_fermata.position.y = 2.3 + 1.2 + 0.32 + sin(clock * 1.6) * 0.04
		halos.add(ex.x, ex.y + 3.86, ex.z, 1.4, gold, 0.4 + near * 0.3)
		halos.add(ex.x, ex.y + 1.4, ex.z, 3.2, gold, 0.12 + near * 0.25 + fin * 0.5)

	for dr in _drums:
		var hit: float = game.drum_hit[int(dr.i)]
		(dr.head as GeometryInstance3D).material_override.set_shader_parameter("hit", hit)
		var sq := 1.0 - sin((hit / 0.4) * PI) * 0.08 * exp(-hit * 4.0) if hit < 0.4 else 1.0
		(dr.group as Node3D).scale = Vector3(1.0 + (1.0 - sq) * 0.6, sq, 1.0 + (1.0 - sq) * 0.6)

	for k in _keys:
		var i := int(k.i)
		var v: float = game.key_vis[i]
		(k.plate as Node3D).position.y = 0.07 - v * 0.11
		var on: bool = game.groups[int(lv.keys[i].group)]
		var b := (1.2 if on else 0.7) + v * 1.8
		for m in k.inlay_mats:
			m.set_shader_parameter("color", k.base * b)
		var ce: Vector3 = k.centre
		halos.add(ce.x, ce.y, ce.z, 1.0 + v * 0.5, k.base, 0.08 + b * 0.1)

	for g in _gates:
		var i := int(g.i)
		var v: float = game.gate_vis[i]
		var bm: ShaderMaterial = g.body_mat
		bm.set_shader_parameter("vis", v)
		bm.set_shader_parameter("glow", 0.85 + 0.15 * sin(clock * 2.2 + i * 1.3))
		var body := g.body as GeometryInstance3D
		body.visible = v > 0.01
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if v > 0.6 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for m in g.ghost_mats:
			m.set_shader_parameter("opacity", (1.0 - v) * 0.55)
		(g.ghost as Node3D).visible = v < 0.97
		if v > 0.05:
			for p in g.glows:
				halos.add(p.x, p.y, p.z, 1.1, gold, 0.22 * v)

	for p in _plats:
		var body: Sim.Body = game.platforms[int(p.i)].body
		var gp := Vector3(body.min.x - body.delta.x * (1.0 - a), body.min.y - body.delta.y * (1.0 - a), body.min.z - body.delta.z * (1.0 - a))
		(p.group as Node3D).position = gp
		var size: Vector3 = p.size
		halos.add(gp.x + size.x / 2.0, gp.y + size.y - 0.55, gp.z + size.z / 2.0, 1.4, gold, 0.18)

	for d in _discords:
		var s: Sim.DiscordState = game.discords[int(d.i)]
		var x := s.prev.x + (s.pos.x - s.prev.x) * a
		var y := s.prev.y + (s.pos.y - s.prev.y) * a
		var z := s.prev.z + (s.pos.z - s.prev.z) * a
		var j := 0.025
		(d.group as Node3D).position = Vector3(x + (randf() - 0.5) * j, y + (randf() - 0.5) * j, z + (randf() - 0.5) * j)
		(d.shell as Node3D).rotation = Vector3(clock * 0.7 + randf() * 0.05, clock * 1.1, clock * 0.4)
		var pulse := 0.85 + 0.25 * sin(clock * 9.0 + int(d.i)) + (randf() - 0.5) * 0.1
		(d.core as Node3D).scale = Vector3.ONE * (0.27 * pulse)
		halos.add(x, y, z, 1.4, _red, 0.5 * pulse)

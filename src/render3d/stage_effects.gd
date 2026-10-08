class_name StageEffects
extends Node3D
## One-off effects from game events (dust, sparks, ink, rings), ambient particles per
## palette, and the glow halos lights place every frame: a port of the web Stage's
## effects.ts. Lives inside the mirrored world node, so positions are simulation space.

const SPRITE := {"dot": 0, "star": 1, "drop": 2, "leaf": 3, "petal": 4, "puff": 5, "ring": 6, "streak": 7, "note": 8, "sparkle": 9, "halo": 10, "mist": 11, "fly": 12}


## Instanced camera-facing sprites: the web build's Pool and Halos share this.
class Billboards:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	var buf := PackedFloat32Array()
	var max_n := 0
	var n := 0

	func _init(mx: int, additive: bool, order: int, factory: StageMaterials) -> void:
		max_n = mx
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = StageUtil.quad()
		mm.instance_count = mx
		mm.visible_instance_count = 0
		buf.resize(mx * 20)
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := factory.unlit("billboard_add" if additive else "billboard_mix")
		m.set_shader_parameter("tex", factory.sprites)
		m.render_priority = order
		mmi.material_override = m

	func put(i: int, x: float, y: float, z: float, size: float, rot: float, cell: float, r: float, g: float, b: float, a: float) -> void:
		var o := i * 20
		buf[o] = 1.0
		buf[o + 3] = x
		buf[o + 5] = 1.0
		buf[o + 7] = y
		buf[o + 10] = 1.0
		buf[o + 11] = z
		buf[o + 12] = r
		buf[o + 13] = g
		buf[o + 14] = b
		buf[o + 15] = a
		buf[o + 16] = size
		buf[o + 17] = rot
		buf[o + 18] = cell

	func commit(count: int) -> void:
		n = count
		if count > 0:
			mm.buffer = buf
		mm.visible_instance_count = count


## A pool of simulated particles (the web build's Pool).
class Pool:
	var bb: Billboards
	## Each particle: [x, y, z, vx, vy, vz, life, max, s0, s1, r, g, b, a, grav, drag, rot, spin, cell, fin, tx, ty, tz, has_target]
	var ps: Array = []
	var max_n := 0

	func _init(mx: int, additive: bool, factory: StageMaterials) -> void:
		max_n = mx
		bb = Billboards.new(mx, additive, 12 if additive else 11, factory)

	func clear() -> void:
		ps.clear()
		bb.commit(0)

	func spawn(x: float, y: float, z: float, o: Dictionary) -> void:
		if ps.size() >= max_n:
			ps.pop_front()
		var c: Vector3 = o.get("color", Vector3.ONE)
		var life: float = o.get("life", 0.6)
		var vel: Array = o.get("vel", [0.0, 0.0, 0.0])
		var size: float = o.get("size", 0.2)
		var tgt: Array = o.get("target", [])
		ps.append([
			x, y, z, float(vel[0]), float(vel[1]), float(vel[2]), life, life,
			size, float(o.get("size1", size)), c.x, c.y, c.z, float(o.get("alpha", 1.0)),
			float(o.get("grav", 0.0)), float(o.get("drag", 0.0)), float(o.get("rot", randf() * 6.28)),
			float(o.get("spin", 0.0)), float(o.get("cell", SPRITE.dot)), float(o.get("fin", 0.08)),
			float(tgt[0]) if tgt.size() > 0 else 0.0, float(tgt[1]) if tgt.size() > 0 else 0.0,
			float(tgt[2]) if tgt.size() > 0 else 0.0, tgt.size() > 0,
		])

	func update(dt: float) -> void:
		var alive: Array = []
		for p in ps:
			p[6] -= dt
			if p[6] <= 0.0:
				continue
			if p[23]:
				var k := minf(1.0, dt / maxf(0.02, p[6]))
				p[0] += (p[20] - p[0]) * k
				p[1] += (p[21] - p[1]) * k
				p[2] += (p[22] - p[2]) * k
			else:
				var d := exp(-p[15] * dt)
				p[3] *= d
				p[4] = p[4] * d - p[14] * dt
				p[5] *= d
				p[0] += p[3] * dt
				p[1] += p[4] * dt
				p[2] += p[5] * dt
			p[16] += p[17] * dt
			alive.append(p)
		ps = alive
		var i := 0
		for p in ps:
			var t: float = 1.0 - p[6] / p[7]
			var fade := minf(1.0, t / maxf(1e-3, p[19])) * minf(1.0, (1.0 - t) * 3.0)
			bb.put(i, p[0], p[1], p[2], p[8] + (p[9] - p[8]) * t, p[16], p[18], p[10], p[11], p[12], p[13] * fade)
			i += 1
		bb.commit(i)


## Glow halos placed fresh every frame by whoever owns a light (the web build's Halos).
class Halos:
	var bb: Billboards
	var n := 0
	var scale := 1.0

	func _init(factory: StageMaterials) -> void:
		bb = Billboards.new(320, true, 13, factory)

	func begin() -> void:
		n = 0

	func add(x: float, y: float, z: float, size: float, color: Vector3, intensity: float = 1.0, cell: int = 10) -> void:
		if n >= bb.max_n:
			return
		var k := intensity * scale
		bb.put(n, x, y, z, size, 0.0, cell, color.x * k, color.y * k, color.z * k, 1.0)
		n += 1

	func end() -> void:
		bb.commit(n)


var halos: Halos
var _soft: Pool
var _glow: Pool
var _factory: StageMaterials
## Each: {mesh, mat, t, dur, size}
var _rings: Array = []
## Each: {mmi, mat, spec}
var _ambients: Array = []
var _pal: Dictionary = {}
var _dust := Vector3.ONE
var _gold := Vector3.ONE
var _ink := StageUtil.col("#0c0a12")
var _gather_acc := 0.0
var _quality := "high"


func setup(factory: StageMaterials) -> void:
	_factory = factory
	halos = Halos.new(factory)
	_soft = Pool.new(1400, false, factory)
	_glow = Pool.new(1400, true, factory)
	add_child(_soft.bb.mmi)
	add_child(_glow.bb.mmi)
	add_child(halos.bb.mmi)
	var torus := StageUtil.torus(1.0, 0.035, 6, 48)
	for i in 8:
		var mesh := MeshInstance3D.new()
		mesh.mesh = torus
		var m := factory.unlit("basic_add")
		m.set_shader_parameter("use_fog", true)
		m.render_priority = 12
		mesh.material_override = m
		mesh.rotation.x = PI / 2.0
		mesh.visible = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		_rings.append({"mesh": mesh, "mat": m, "t": 1.0, "dur": 1.0, "size": 1.0})


func load_palette(p: Dictionary, look: Dictionary) -> void:
	_pal = p
	_soft.clear()
	_glow.clear()
	for r in _rings:
		r.t = r.dur
		r.mesh.visible = false
	for a in _ambients:
		a.mmi.queue_free()
	_ambients.clear()
	var specs := _ambient_specs(p, look)
	for i in specs.size():
		var s: Dictionary = specs[i]
		var count: int = s.count
		var r := StageUtil.Rng.new(77 + i * 13)
		var buf := PackedFloat32Array()
		buf.resize(count * 16)
		for k in count:
			var o := k * 16
			buf[o] = 1.0
			buf[o + 5] = 1.0
			buf[o + 10] = 1.0
			for q in 4:
				buf[o + 12 + q] = r.next()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = StageUtil.quad()
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := _factory.unlit("ambient_add" if s.additive else "ambient_mix")
		m.set_shader_parameter("tex", _factory.sprites)
		m.set_shader_parameter("vel", s.vel)
		m.set_shader_parameter("wobble", s.wobble)
		m.set_shader_parameter("size", s.size)
		m.set_shader_parameter("spin", s.spin)
		m.set_shader_parameter("kind", s.kind)
		m.set_shader_parameter("cell", float(s.cell))
		m.set_shader_parameter("col_a", s.a)
		m.set_shader_parameter("col_b", s.b)
		m.set_shader_parameter("alpha", s.alpha)
		m.render_priority = 10
		mmi.material_override = m
		add_child(mmi)
		_ambients.append({"mmi": mmi, "mat": m, "spec": s})
	_dust = StageUtil.mixc(StageUtil.col(p.mats.stone.color), StageUtil.col(p.fog), 0.45) * 1.1
	_gold = StageUtil.col(p.glow)
	set_quality(_quality)


func set_quality(q: String) -> void:
	_quality = q
	var k := 1.0 if q == "high" else (0.55 if q == "medium" else 0.3)
	for a in _ambients:
		var mm: MultiMesh = a.mmi.multimesh
		mm.visible_instance_count = mini(mm.instance_count, maxi(0, roundi(a.spec.count * k)))
	halos.scale = 1.6 if q == "low" else 1.0


func _ambient_specs(p: Dictionary, look: Dictionary) -> Array:
	var glow := StageUtil.col(p.glow)
	var out: Array = []
	var motes := func(count: int) -> Dictionary:
		return {
			"count": count, "additive": true, "kind": 1.0, "cell": SPRITE.dot, "size": 0.05,
			"vel": Vector3(0.12, 0.05, 0.04), "wobble": 0.5, "spin": 0.0,
			"a": glow * 1.6, "b": StageUtil.col("#ffffff") * 1.2, "alpha": 0.85, "y": Vector2(-4, 9),
		}
	match String(p.ambient):
		"motes":
			out.append(motes.call(260))
		"mist":
			out.append({
				"count": 70, "additive": false, "kind": 0.0, "cell": SPRITE.mist, "size": 5.0,
				"vel": Vector3(0.35, 0.0, 0.05), "wobble": 0.8, "spin": 0.0,
				"a": StageUtil.col(p.fog) * 1.05, "b": StageUtil.col(p.skyHorizon), "alpha": 0.32, "y": Vector2(-6, 1),
			})
		"leaves", "petals":
			out.append({
				"count": 120, "additive": false, "kind": 0.0, "cell": SPRITE.leaf if p.ambient == "leaves" else SPRITE.petal, "size": 0.14,
				"vel": Vector3(0.6, -0.8, 0.15), "wobble": 0.9, "spin": 1.0,
				"a": StageUtil.col(p.mats.leaf.color), "b": StageUtil.col("#e3a23c") if p.ambient == "leaves" else StageUtil.col("#f6d3e4"),
				"alpha": 1.0, "y": Vector2(-5, 10),
			})
		"fireflies":
			out.append({
				"count": 110, "additive": true, "kind": 2.0, "cell": SPRITE.fly, "size": 0.16,
				"vel": Vector3(0.05, 0.03, 0.05), "wobble": 1.4, "spin": 0.0,
				"a": StageUtil.col("#d8ff8a") * 2.6, "b": StageUtil.col("#ffe68a") * 2.2, "alpha": 1.0, "y": Vector2(-3, 6),
			})
		"sparks":
			out.append({
				"count": 140, "additive": true, "kind": 3.0, "cell": SPRITE.dot, "size": 0.05,
				"vel": Vector3(0.2, 1.4, 0.05), "wobble": 0.25, "spin": 0.0,
				"a": StageUtil.col("#ffb24a") * 2.4, "b": StageUtil.col("#ffe0a0") * 2.0, "alpha": 1.0, "y": Vector2(-5, 10),
			})
		"embers":
			out.append({
				"count": 150, "additive": true, "kind": 3.0, "cell": SPRITE.dot, "size": 0.06,
				"vel": Vector3(0.15, 0.55, 0.05), "wobble": 0.6, "spin": 0.0,
				"a": StageUtil.col("#ff7a3a") * 2.4, "b": StageUtil.col("#ffc46a") * 2.0, "alpha": 1.0, "y": Vector2(-5, 10),
			})
	if float(look.motes) > 0.0 and p.ambient != "motes":
		out.append(motes.call(roundi(200.0 * float(look.motes))))
	return out


## Spawns a ring that expands flat on the ground.
func ring(x: float, y: float, z: float, size: float, color: Vector3, dur: float = 0.8) -> void:
	var r: Dictionary = _rings[0]
	for q in _rings:
		if q.t >= q.dur:
			r = q
			break
	r.t = 0.0
	r.dur = dur
	r.size = size
	r.mesh.position = Vector3(x, y, z)
	r.mat.set_shader_parameter("color", color)
	r.mesh.visible = true


func burst(x: float, y: float, z: float, n: int, o: Dictionary, additive: bool) -> void:
	var pool := _glow if additive else _soft
	var speed: float = o.speed
	var up: float = o.get("up", 0.0)
	var flat: bool = o.get("flat", false)
	var spread: float = o.get("spread", 0.0)
	for i in n:
		var a := randf() * PI * 2.0
		var e := (randf() - 0.3) * 0.4 if flat else asin(randf() * 2.0 - 1.0)
		var sp := speed * (0.5 + randf() * 0.7)
		var o2 := o.duplicate()
		o2.vel = [cos(a) * cos(e) * sp, sin(e) * sp + up, sin(a) * cos(e) * sp]
		o2.life = float(o.get("life", 0.6)) * (0.7 + randf() * 0.6)
		o2.size = float(o.get("size", 0.2)) * (0.7 + randf() * 0.6)
		if o.has("size1"):
			o2.size1 = float(o.size1)
		o2.spin = o.spin if o.has("spin") else (randf() - 0.5) * 4.0
		pool.spawn(x + (randf() - 0.5) * spread, y + (randf() - 0.5) * spread, z + (randf() - 0.5) * spread, o2)


func _puff(x: float, y: float, z: float, n: int, speed: float, size: float, color: Vector3, life: float = 0.5) -> void:
	burst(x, y + 0.05, z, n, {"speed": speed, "up": 0.4, "flat": true, "size": size * 0.6, "size1": size * 1.6, "color": color, "alpha": 0.55, "drag": 5.0, "life": life, "cell": SPRITE.puff, "fin": 0.05}, false)


func handle(events: Array, game: Sim, feet: Vector3) -> void:
	if _pal.is_empty():
		return
	var lv := game.level
	for e in events:
		match String(e.t):
			"jump":
				_puff(feet.x, feet.y, feet.z, 7, 1.6, 0.28, _dust)
			"land":
				var k := minf(1.0, float(e.impact) / 21.0)
				_puff(feet.x, feet.y, feet.z, roundi(5 + k * 12), 1.2 + k * 3.0, 0.24 + k * 0.3, _dust, 0.45 + k * 0.3)
				if k > 0.55:
					burst(feet.x, feet.y + 0.05, feet.z, 8, {"speed": 2.5, "up": 2.5, "size": 0.05, "color": StageUtil.shade(_dust, 0.7), "alpha": 1.0, "grav": 14.0, "life": 0.6, "cell": SPRITE.dot}, false)
				var surf := int(e.get("surface", 0))
				if surf == Level.MAT_STONE or surf == Level.MAT_MARBLE:
					ring(feet.x, feet.y + 0.03, feet.z, 0.4 + k * 0.9, _dust * (0.25 * k), 0.4)
			"step":
				_puff(feet.x, feet.y, feet.z, 2, 0.6, 0.16, _dust, 0.35)
			"note":
				var n: V3 = lv.notes[int(e.id)].pos
				burst(n.x, n.y, n.z, 34, {"speed": 4.5, "size": 0.14, "size1": 0.02, "color": _gold * 3.0, "drag": 3.0, "grav": 2.0, "life": 0.8, "cell": SPRITE.sparkle}, true)
				burst(n.x, n.y, n.z, 5, {"speed": 1.0, "up": 1.4, "size": 0.22, "color": _gold * 2.2, "drag": 1.0, "life": 1.4, "cell": SPRITE.note, "spin": 0.0}, true)
				_glow.spawn(n.x, n.y, n.z, {"size": 0.4, "size1": 2.6, "color": _gold * 2.0, "life": 0.35, "cell": SPRITE.halo, "fin": 0.01})
			"checkpoint":
				var c: V3 = lv.checkpoints[int(e.id)].pos
				ring(c.x, c.y + 0.05, c.z, 1.6, _gold * 2.2, 0.9)
				burst(c.x, c.y + 0.6, c.z, 22, {"speed": 1.2, "up": 2.2, "size": 0.1, "size1": 0.02, "color": _gold * 2.5, "drag": 1.5, "life": 1.1, "cell": SPRITE.sparkle, "spread": 0.5}, true)
			"death":
				var q := _pos_of(e.pos)
				burst(q.x, q.y + 0.45, q.z, 48, {"speed": 5.5, "up": 2.5, "size": 0.17, "size1": 0.08, "color": _ink, "alpha": 1.0, "grav": 16.0, "drag": 0.6, "life": 0.9, "cell": SPRITE.drop, "fin": 0.01}, false)
				burst(q.x, q.y + 0.45, q.z, 10, {"speed": 2.2, "up": 3.0, "size": 0.3, "size1": 0.12, "color": _ink, "alpha": 1.0, "grav": 12.0, "drag": 0.4, "life": 0.8, "cell": SPRITE.drop, "fin": 0.01}, false)
				burst(q.x, q.y + 0.45, q.z, 8, {"speed": 1.4, "size": 0.4, "size1": 1.1, "color": _ink, "alpha": 0.5, "drag": 4.0, "life": 0.6, "cell": SPRITE.puff}, false)
				_glow.spawn(q.x, q.y + 0.45, q.z, {"size": 0.3, "size1": 2.2, "color": StageUtil.col(_pal.rubric) * 1.6, "life": 0.3, "cell": SPRITE.halo, "fin": 0.01})
			"respawn":
				var q2 := game.player.pos
				ring(q2.x, q2.y + 0.04, q2.z, 0.9, _gold * 1.6, 0.6)
				_glow.spawn(q2.x, q2.y + 0.45, q2.z, {"size": 0.2, "size1": 1.8, "color": _gold * 1.4, "life": 0.35, "cell": SPRITE.halo, "fin": 0.01})
			"bounce":
				var d: V3 = lv.drums[int(e.id)].pos
				ring(d.x + 0.5, d.y + 0.74, d.z + 0.5, 0.9, _gold * 1.8, 0.5)
				ring(d.x + 0.5, d.y + 0.74, d.z + 0.5, 1.5, _gold * 0.9, 0.8)
				burst(d.x + 0.5, d.y + 0.9, d.z + 0.5, 6, {"speed": 0.8, "up": 2.5, "size": 0.2, "color": _gold * 2.0, "drag": 1.0, "life": 1.1, "cell": SPRITE.note, "spin": 0.0}, true)
			"key":
				var kd: Dictionary = lv.keys[int(e.id)]
				var kp: V3 = kd.pos
				var gc := StageUtil.group_color(int(e.group)) * 2.2
				burst(kp.x + kd.width / 2.0, kp.y + 0.1, kp.z + 0.5, 16, {"speed": 1.5, "up": 1.6, "size": 0.1, "size1": 0.02, "color": gc, "drag": 2.0, "life": 0.7, "cell": SPRITE.sparkle, "spread": 0.6}, true)
				ring(kp.x + kd.width / 2.0, kp.y + 0.06, kp.z + 0.5, 0.8 + kd.width * 0.3, gc * 0.7, 0.5)
			"gate":
				for gd in lv.gates:
					if int(gd.group) != int(e.group):
						continue
					var mn: V3 = gd.min
					var mx: V3 = gd.max
					for i in 18:
						var x := mn.x + randf() * (mx.x - mn.x)
						var y := mn.y + randf() * (mx.y - mn.y)
						var z := mn.z + randf() * (mx.z - mn.z)
						_glow.spawn(x, y, z, {"vel": [0.0, 0.6, 0.0], "size": 0.12, "size1": 0.02, "color": _gold * 2.2, "life": 0.7, "cell": SPRITE.sparkle, "drag": 1.0})
			"exit":
				var x2 := lv.exit_pos
				burst(x2.x, x2.y + 1.3, x2.z, 50, {"speed": 4.0, "size": 0.16, "size1": 0.02, "color": _gold * 3.0, "drag": 2.0, "grav": 0.5, "life": 1.3, "cell": SPRITE.sparkle}, true)
				burst(x2.x, x2.y + 0.5, x2.z, 12, {"speed": 0.6, "up": 2.0, "size": 0.25, "color": _gold * 2.0, "drag": 0.6, "life": 2.2, "cell": SPRITE.note, "spin": 0.0, "spread": 1.2}, true)
				ring(x2.x, x2.y + 0.05, x2.z, 2.4, _gold * 2.0, 1.2)
			"switch":
				burst(feet.x, feet.y + 0.45, feet.z, 12, {"speed": 1.6, "size": 0.08, "size1": 0.01, "color": _gold * 2.0, "drag": 3.0, "life": 0.5, "cell": SPRITE.sparkle}, true)
			"bonk":
				burst(feet.x, feet.y + 0.9, feet.z, 5, {"speed": 1.6, "up": 0.6, "size": 0.12, "color": StageUtil.col("#fff3c4") * 2.0, "drag": 3.0, "life": 0.4, "cell": SPRITE.star}, true)


static func _pos_of(p: Variant) -> Vector3:
	if p is V3:
		return Vector3(p.x, p.y, p.z)
	if p is Vector3:
		return p
	if p is Dictionary:
		return Vector3(float(p.x), float(p.y), float(p.z))
	return Vector3.ZERO


func update(dt: float, game: Sim, focus: Vector3, time: float) -> void:
	_soft.update(dt)
	_glow.update(dt)
	for r in _rings:
		if r.t >= r.dur:
			continue
		r.t += dt
		var k := minf(1.0, r.t / r.dur)
		var s: float = r.size * (0.3 + 0.7 * (1.0 - pow(1.0 - k, 3.0)))
		r.mesh.scale = Vector3(s, s, 1.0)
		r.mat.set_shader_parameter("opacity", 1.0 - k)
		if k >= 1.0:
			r.mesh.visible = false
	# Ink gathering back at the respawn point near the end of the death timer.
	var pl := game.player
	if pl.dead > 0.0 and pl.dead < 0.45:
		_gather_acc += dt * 70.0
		var t: V3 = game.respawn_pos
		while _gather_acc > 1.0:
			_gather_acc -= 1.0
			var a := randf() * PI * 2.0
			var rr := 0.6 + randf() * 0.9
			_soft.spawn(t.x + cos(a) * rr, t.y + 0.45 + (randf() - 0.3) * 1.2, t.z + sin(a) * rr, {
				"size": 0.1, "size1": 0.04, "color": _ink, "alpha": 1.0, "life": maxf(0.05, pl.dead),
				"cell": SPRITE.drop, "target": [t.x, t.y + 0.45, t.z], "fin": 0.2,
			})
	else:
		_gather_acc = 0.0
	for a in _ambients:
		var s: Dictionary = a.spec
		var m: ShaderMaterial = a.mat
		m.set_shader_parameter("time", time)
		var size := Vector3(44, s.y.y - s.y.x, 28)
		m.set_shader_parameter("box_size", size)
		m.set_shader_parameter("box_min", Vector3(focus.x - size.x / 2.0, focus.y + s.y.x, -6))

class_name StageQuaver
extends RefCounted
## Quaver on the stage, animated from the simulation: a port of the web Stage's quaver.ts
## update. The meshes come from the bake; the flag and the two scarf tails are spring
## chains whose ribbons are rebuilt here every frame.

const HEAD_Y := 0.4
const LEG_H := 0.15
const RUN := 6.1


class Chain:
	var p: Array[Vector3] = []
	var q: Array[Vector3] = []
	var n := 0
	var seg := 0.0

	func _init(count: int, s: float) -> void:
		n = count
		seg = s
		for i in n:
			p.append(Vector3.ZERO)
			q.append(Vector3.ZERO)

	func reset(anchor: Vector3, dir: Vector3) -> void:
		for i in n:
			p[i] = anchor + dir * (i * seg)
			q[i] = p[i]

	## Verlet step with a shape memory towards rest(i) (the unit direction of segment i).
	func step(anchor: Vector3, rest: Callable, dt: float, stiff: float, grav: float, extra: Callable) -> void:
		p[0] = anchor
		q[0] = anchor
		var damp := pow(0.04, dt)
		for i in range(1, n):
			var cur := p[i]
			var tmp := (cur - q[i]) * damp
			q[i] = cur
			var f: Vector3 = extra.call(i, Vector3(0, -grav, 0))
			cur += tmp + f * (dt * dt)
			var want := p[i - 1] + (rest.call(i) as Vector3) * seg
			cur = cur.lerp(want, minf(1.0, stiff * dt))
			p[i] = cur
		for it in 3:
			for i in range(1, n):
				var a := p[i - 1]
				var d := p[i] - a
				var l := d.length()
				if l == 0.0:
					l = 1e-5
				p[i] = a + d * (seg / l)


class Ribbon:
	var chain: Chain
	var w0 := 0.0
	var w1 := 0.0
	var align := 0
	var node: MeshInstance3D
	var mesh := ArrayMesh.new()
	var _idx := PackedInt32Array()
	var _mat: Material

	func _init(c: Chain, a: float, b: float, al: int, mi: MeshInstance3D) -> void:
		chain = c
		w0 = a
		w1 = b
		align = al
		node = mi
		_mat = mi.material_override
		mi.mesh = mesh
		mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		for i in c.n - 1:
			var k := i * 2
			# The web build's (a, a+1, a+2), (a+1, a+3, a+2), reversed.
			_idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])

	func update(side: Vector3, curl: float = 0.0) -> void:
		var c := chain
		var pos := PackedVector3Array()
		var nor := PackedVector3Array()
		pos.resize(c.n * 2)
		nor.resize(c.n * 2)
		for i in c.n:
			var a := c.p[maxi(0, i - 1)]
			var b := c.p[mini(c.n - 1, i + 1)]
			var d := (b - a).normalized()
			var w := d.cross(side).normalized()
			if w.y > 0.0:
				w = -w
			var t := float(i) / (c.n - 1)
			var width := w0 + (w1 - w0) * t
			var off := curl * t * t + (-width / 2.0 if align == 0 else 0.0)
			var p := c.p[i]
			pos[i * 2] = p + w * off
			pos[i * 2 + 1] = p + w * (off + width)
			var nrm := d.cross(w).normalized()
			nor[i * 2] = nrm
			nor[i * 2 + 1] = nrm
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nor
		arrays[Mesh.ARRAY_INDEX] = _idx
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


var feet := Vector3.ZERO
var _group: Node3D
var _root: Node3D
var _body: Node3D
var _head: Node3D
var _eyes: Array = []
var _legs: Array = []
var _stem_top: Node3D
var _neck: Node3D
var _xray: Array = []
var _blob: Node3D
var _blob_mats: Array = []
var _flag: Chain
var _scarf_a: Chain
var _scarf_b: Chain
var _ribbons: Array = []
var _yaw := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _last_since_land := 9.0
var _last_since_jump := 9.0
var _blink_at := 2.0
var _blink_t := 1.0
var _pop := 1.0
var _was_dead := false
var _initialised := false
var _lean := 0.0
var _prev_vel := Vector3.ZERO


func setup(bake: StageBake) -> void:
	var s: Dictionary = bake.module("quaver")
	_group = s.group
	_root = s.root
	_body = s.body
	_head = s.headPivot
	_eyes = s.eyes
	_legs = s.legs
	_stem_top = s.stemTop
	_neck = s.neck
	_xray = s.xray
	_blob = s.blob
	_blob_mats = [(_blob as MeshInstance3D).material_override]
	var rs: Array = s.ribbons
	_flag = Chain.new(int(rs[0].n), float(rs[0].seg))
	_scarf_a = Chain.new(int(rs[1].n), float(rs[1].seg))
	_scarf_b = Chain.new(int(rs[2].n), float(rs[2].seg))
	var chains := [_flag, _scarf_a, _scarf_b]
	_ribbons.clear()
	for i in 3:
		var r: Dictionary = rs[i]
		_ribbons.append(Ribbon.new(chains[i], float(r.w0), float(r.w1), int(r.align), r.mesh))
	reset()


func reset() -> void:
	_initialised = false
	_pop = 1.0
	_was_dead = false
	_squash = 0.0
	_squash_v = 0.0


func update(game: Sim, frame: Dictionary, sim: Node3D) -> void:
	var pl := game.player
	var a: float = frame.alpha
	var dt := minf(0.05, float(frame.game_dt))
	var now: float = frame.now
	var t := game.time
	feet = Vector3(pl.prev.x + (pl.pos.x - pl.prev.x) * a, pl.prev.y + (pl.pos.y - pl.prev.y) * a, pl.prev.z + (pl.pos.z - pl.prev.z) * a)
	var dead := pl.dead > 0.0
	if _was_dead and not dead:
		_pop = 0.0
	_was_dead = dead
	_root.visible = not dead
	for r in _ribbons:
		r.node.visible = not dead
	_root.position = feet

	var speed := Vector2(pl.vel.x, pl.vel.z).length()
	var run_k := clampf(speed / RUN, 0.0, 1.0)
	var idle := speed < 0.3 and pl.grounded
	var target := StageUtil.lerp_angle(pl.heading, -PI / 2.0, 0.45 if idle else 0.28)
	if game.finished:
		var ft := t - game.finished_at
		var spin := StageUtil.ease_in_out(clampf(ft / 1.1, 0.0, 1.0)) * PI * 2.0
		target = StageUtil.lerp_angle(pl.heading, -PI / 2.0, clampf(ft / 1.1, 0.0, 1.0)) + spin
		_yaw = target
	else:
		_yaw = StageUtil.lerp_angle(_yaw, target, StageUtil.kdamp(14.0, dt if dt > 0.0 else 1.0 / 60.0))
	_root.rotation.y = -_yaw

	# Squash and stretch spring: kicked by jumps and landings.
	if pl.since_land < _last_since_land - 1e-4 and pl.since_land < 0.1:
		_squash_v -= clampf(pl.last_impact / 21.0, 0.15, 1.0) * 5.5
	if pl.since_jump < _last_since_jump - 1e-4 and pl.since_jump < 0.1:
		_squash_v += 4.2
	_last_since_land = pl.since_land
	_last_since_jump = pl.since_jump
	if dt > 0.0:
		var acc := -190.0 * _squash - 13.0 * _squash_v
		_squash_v += acc * dt
		_squash = clampf(_squash + _squash_v * dt, -0.38, 0.32)
	var air := 0.0 if pl.grounded else clampf(pl.vel.y / 32.0, -0.07, 0.12)
	var breath := sin(now * 2.3) * 0.022 * (1.0 - run_k) * (1.0 if pl.grounded else 0.0)
	var phase := (pl.walk / 0.44) * PI
	var bob := absf(sin(phase)) * 0.055 * run_k * (1.0 if pl.grounded else 0.0)
	var step_squash := -cos(phase * 2.0) * 0.035 * run_k * (1.0 if pl.grounded else 0.0)
	var sy := 1.0 + _squash + air + breath + step_squash
	var hop := 0.0
	if game.finished:
		var ft2 := t - game.finished_at
		hop = sin((ft2 / 0.7) * PI) * 0.35 if ft2 < 0.7 else absf(sin((ft2 - 0.7) * 3.2)) * 0.06
		sy += 0.08 if ft2 < 0.7 else 0.0
	var pop_s := StageUtil.ease_out_back(_pop) if _pop < 1.0 else 1.0
	if _pop < 1.0:
		var fdt: float = frame.dt
		_pop = minf(1.0, _pop + (fdt if fdt != 0.0 else 0.016) * 3.2)
	var sxz := 1.0 / sqrt(maxf(0.4, sy))
	_body.scale = Vector3(sxz * pop_s, sy * pop_s, sxz * pop_s)
	_body.position.y = bob + hop

	# Lean into acceleration and speed.
	var ax := (pl.vel.x - _prev_vel.x) / dt if dt > 0.0 else 0.0
	var az := (pl.vel.z - _prev_vel.z) / dt if dt > 0.0 else 0.0
	_prev_vel = Vector3(pl.vel.x, pl.vel.y, pl.vel.z)
	var fwd_acc := ax * cos(_yaw) + az * sin(_yaw)
	var lean_t := -run_k * 0.14 - clampf(fwd_acc / 120.0, -0.12, 0.12)
	_lean += (lean_t - _lean) * StageUtil.kdamp(10.0, dt if dt > 0.0 else 1.0 / 60.0)
	_head.rotation.z = -0.2 + _lean + (0.0 if pl.grounded else clampf(-pl.vel.y * 0.006, -0.1, 0.12))

	# Legs: stride on the ground, tuck while rising, dangle while falling.
	for i in 2:
		var leg: Node3D = _legs[i]
		var s := 1.0 if i == 0 else -1.0
		var ang := sin(phase) * 0.85 * run_k * s
		if not pl.grounded:
			ang = 0.5 * s * 0.3 + 0.35 if pl.vel.y > 0.0 else -0.25 + sin(now * 14.0 + i) * 0.12
		if game.finished:
			ang = sin(now * 10.0 + i * 3) * 0.3
		leg.rotation.z = ang
		leg.position.y = LEG_H + 0.04 + (maxf(0.0, sin(phase + (PI if i == 1 else 0.0))) * 0.05 * run_k if pl.grounded else 0.03)
		leg.scale = Vector3(pop_s, pop_s, pop_s)

	# Blinks and gaze.
	_blink_t += float(frame.dt)
	if now > _blink_at:
		_blink_t = 0.0
		_blink_at = now + 1.8 + randf() * 3.4
	var blink := 1.0 - sin((_blink_t / 0.13) * PI) if _blink_t < 0.13 else 1.0
	var happy := 0.4 if game.finished else 1.0
	var wide := 1.12 if (not pl.grounded and pl.vel.y < -8.0) else 1.0
	for e in _eyes:
		var white: Node3D = e.white
		var pupil: Node3D = e.pupil
		var glint: Node3D = e.glint
		white.scale.y = 0.112 * maxf(0.08, blink * happy) * wide
		pupil.scale.y = 0.058 * maxf(0.05, blink * happy)
		glint.visible = blink > 0.5
		pupil.position.y = -0.01 + clampf(pl.vel.y * 0.0015, -0.02, 0.02)
		pupil.position.z = 0.0

	# Contact shadow on whatever is below.
	var gy := _ground_below(game, feet)
	var hgt := maxf(0.0, feet.y - gy)
	_blob.visible = not dead and gy > -50.0
	_blob.position = Vector3(feet.x, gy + 0.02, feet.z)
	var bs := (0.75 - minf(0.35, hgt * 0.08)) * pop_s
	_blob.scale = Vector3(bs, 1.0, bs * 0.85)
	for m in _blob_mats:
		m.set_shader_parameter("opacity", 0.42 * maxf(0.0, 1.0 - hgt / 6.0))

	# Flag and scarf chains in simulation space.
	var inv := sim.global_transform.affine_inverse()
	var top := inv * _stem_top.global_position
	var neck := inv * _neck.global_position
	var fwd := Vector3(cos(_yaw), 0.0, sin(_yaw))
	var side := Vector3(-sin(_yaw), 0.0, cos(_yaw))
	if not _initialised or dead:
		var back := -fwd
		_flag.reset(top, (back + Vector3(0, -0.6, 0)).normalized())
		_scarf_a.reset(neck, (back + Vector3(0, -0.8, 0)).normalized())
		_scarf_b.reset(neck, (back + Vector3(0, -1, 0.2)).normalized())
		_initialised = true
	if dt > 0.0:
		# The flag curls like a ponytail: out and back from the stem top, then down.
		var flutter := now * 9.0
		var fr: Array[Vector3] = []
		for i in _flag.n:
			var k := float(i) / (_flag.n - 1)
			var ang2 := 0.45 - k * 1.9
			fr.append((fwd * -cos(ang2) + Vector3(0, sin(ang2), 0)).normalized())
		_flag.step(top, func(i: int) -> Vector3: return fr[i], dt, 18.0, 3.0, func(i: int, f: Vector3) -> Vector3:
			f += side * (sin(flutter + i * 0.9) * 4.0 * (0.3 + run_k))
			f.y += sin(flutter * 0.7 + i) * 3.0 * run_k
			return f)
		var scarf_rest := (fwd * -0.5 + Vector3(0, -0.85, 0)).normalized()
		var scarf_rest_b := (scarf_rest + side * 0.3).normalized()
		_scarf_a.step(neck, func(_i: int) -> Vector3: return scarf_rest, dt, 5.0, 9.0, func(i: int, f: Vector3) -> Vector3:
			return f + side * (sin(now * 7.0 + i * 0.8) * 3.0 * (0.2 + run_k)))
		_scarf_b.step(neck, func(_i: int) -> Vector3: return scarf_rest_b, dt, 5.0, 9.0, func(i: int, f: Vector3) -> Vector3:
			return f + side * (cos(now * 6.0 + i) * 3.0 * (0.2 + run_k)))
	# Keep the flag broad side facing across the body.
	_ribbons[0].update(side, 0.0)
	_ribbons[1].update(side)
	_ribbons[2].update(side)
	for x in _xray:
		x.visible = not dead


## Height of the first solid surface under a point (voxels and solid bodies).
func _ground_below(game: Sim, p: Vector3) -> float:
	var lv := game.level
	var x := floori(p.x)
	var z := floori(p.z)
	var best := -99.0
	if x >= 0 and x < lv.w and z >= 0 and z < lv.d:
		var y := mini(lv.h - 1, floori(p.y + 0.05))
		while y >= 0:
			var m := lv.cells[x + lv.w * (y + lv.h * z)]
			if m != 0 and m != 8:
				best = y + 1
				break
			y -= 1
	for b in game.bodies:
		if not b.solid:
			continue
		if p.x < b.min.x or p.x > b.max.x or p.z < b.min.z or p.z > b.max.z:
			continue
		if b.max.y <= p.y + 0.05 and b.max.y > best:
			best = b.max.y
	return best

class_name PageEntities
extends RefCounted
## Live things in ink and gold (entities.ts). Each one becomes a Drawable with its depth
## and world bounds so the page can draw it in painter's order and redraw whatever stands
## in front of it.


class Drawable:
	## Nearest depth the thing occupies (smaller is nearer).
	var z := 0.0
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0
	var draw: Callable
	## Drawn over scenery when the thing is hidden behind it.
	var ghost: Callable
	## The solid core: scenery only hides the thing when something nearer covers it.
	var has_core := false
	var cx0 := 0.0
	var cy0 := 0.0
	var cx1 := 0.0
	var cy1 := 0.0
	## What it is (for profiling).
	var tag := ""

	func _init(z_: float, x0_: float, y0_: float, x1_: float, y1_: float, draw_: Callable) -> void:
		z = z_
		x0 = x0_
		y0 = y0_
		x1 = x1_
		y1 = y1_
		draw = draw_

	func tagged(t: String) -> Drawable:
		tag = t
		return self

	func core(a: float, b: float, c: float, d: float) -> Drawable:
		has_core = true
		cx0 = a
		cy0 = b
		cx1 = c
		cy1 = d
		return self


static var _sk := PageSketch.new()


static func layer_of(env: PageEnv, z: float) -> int:
	return clampi(floori(z), 0, env.world.d - 1)


static func collect(out: Array, painter: PagePainter, game: Sim, env: PageEnv, frame: Dictionary, vx0: float, vy0: float, vx1: float, vy1: float) -> void:
	var lv := game.level
	var t := game.time
	var in_view := func(a: float, b: float, c: float, d: float) -> bool: return c > vx0 and a < vx1 and d > vy0 and b < vy1

	for i in lv.notes.size():
		var n: V3 = lv.notes[i].pos
		var taken: bool = game.notes_taken[i]
		var since: float = t - game.note_taken_at[i] if taken else 0.0
		if taken and since > 0.7:
			continue
		if not in_view.call(n.x - 0.6, n.y - 0.6, n.x + 0.6, n.y + 1.4):
			continue
		var nz := layer_of(env, n.z)
		var dw := Drawable.new(n.z - 0.3, n.x - 0.5, n.y - 0.5, n.x + 0.5, n.y + 0.6,
			func(p: PageEnv.Proj) -> void: draw_note(painter, p, env, i, n.x, n.y, nz, t, since if taken else -1.0)).tagged("note")
		dw.core(n.x - 0.15, n.y - 0.15, n.x + 0.15, n.y + 0.15)
		if not taken:
			dw.ghost = func(p: PageEnv.Proj) -> void: draw_note_hint(painter, p, env, i, n.x, n.y, t)
		out.append(dw)

	for i in lv.checkpoints.size():
		var c: V3 = lv.checkpoints[i].pos
		if not in_view.call(c.x - 0.6, c.y, c.x + 0.6, c.y + 1.6):
			continue
		out.append(Drawable.new(c.z - 0.35, c.x - 0.5, c.y, c.x + 0.5, c.y + 1.5,
			func(p: PageEnv.Proj) -> void: draw_checkpoint(painter, p, env, game, i, frame)).tagged("checkpoint"))

	var e := lv.exit_pos
	if in_view.call(e.x - 1.8, e.y - 0.2, e.x + 1.8, e.y + 4.6):
		out.append(Drawable.new(e.z - 0.5, e.x - 1.6, e.y, e.x + 1.6, e.y + 4.4,
			func(p: PageEnv.Proj) -> void: draw_exit(painter, p, env, game)).tagged("exit"))

	for i in lv.drums.size():
		var d: V3 = lv.drums[i].pos
		if not in_view.call(d.x - 0.3, d.y, d.x + 1.3, d.y + 1.6):
			continue
		var dz := layer_of(env, d.z)
		out.append(Drawable.new(d.z + 0.06, d.x, d.y, d.x + 1, d.y + 1.4,
			func(p: PageEnv.Proj) -> void: draw_drum(painter, p, env, d.x, d.y, dz, game.drum_hit[i] if i < game.drum_hit.size() else 9.0, i)).tagged("drum"))

	for i in lv.keys.size():
		var k: Dictionary = lv.keys[i]
		var kp: V3 = k.pos
		if not in_view.call(kp.x, kp.y - 0.2, kp.x + k.width, kp.y + 0.5):
			continue
		# The core is the part above the floor, so the floor the key is set into does not
		# paint over it.
		out.append(Drawable.new(kp.z + 0.02, kp.x, kp.y - 0.15, kp.x + k.width, kp.y + 0.45,
			func(p: PageEnv.Proj) -> void: draw_key(painter, p, env, game, i)).tagged("key").core(kp.x + 0.15, kp.y + 0.02, kp.x + k.width - 0.15, kp.y + 0.12))

	for b in game.bodies:
		if b.kind == Sim.KIND_GATE:
			if not in_view.call(b.min.x - 0.2, b.min.y, b.max.x + 0.2, b.max.y + 0.4):
				continue
			out.append(Drawable.new(b.min.z, b.min.x - 0.1, b.min.y - 0.05, b.max.x + 0.1, b.max.y + 0.35,
				func(p: PageEnv.Proj) -> void: draw_gate(painter, p, env, game, b)).tagged("gate"))
		elif b.kind == Sim.KIND_PLATFORM:
			var a: float = 1.0 - frame.alpha
			var x0: float = b.min.x - b.delta.x * a
			var y0: float = b.min.y - b.delta.y * a
			var z0: float = b.min.z - b.delta.z * a
			var w: float = b.max.x - b.min.x
			var h: float = b.max.y - b.min.y
			if not in_view.call(x0 - 0.2, y0 - 1, x0 + w + 0.2, y0 + h + 0.2):
				continue
			out.append(Drawable.new(z0, x0 - 0.1, y0 - 0.9, x0 + w + 0.1, y0 + h + 0.1,
				func(p: PageEnv.Proj) -> void: draw_platform(painter, p, env, game, b, x0, y0, z0, w, h)).tagged("platform"))

	for i in game.discords.size():
		var ds := game.discords[i]
		var al: float = frame.alpha
		var x := ds.prev.x + (ds.pos.x - ds.prev.x) * al
		var y := ds.prev.y + (ds.pos.y - ds.prev.y) * al
		var z := ds.prev.z + (ds.pos.z - ds.prev.z) * al
		if not in_view.call(x - 0.7, y - 0.7, x + 0.7, y + 0.7):
			continue
		var lz := layer_of(env, z)
		var dw := Drawable.new(z - 0.35, x - 0.6, y - 0.6, x + 0.6, y + 0.6,
			func(p: PageEnv.Proj) -> void: draw_discord(painter, p, env, game, i, x, y, lz, frame)).tagged("discord")
		dw.core(x - 0.3, y - 0.3, x + 0.3, y + 0.3)
		out.append(dw)


# ---------------------------------------------------------------- notes

## The note glyph in local units around its centre: head, stem and flag.
static func note_shape(s: PageSketch, fill: Color, edge_lw: float, flag_wave: float = 0.0) -> void:
	s.ellipse(-0.07, -0.17, 0.17, 0.125, 0.38, fill, edge_lw)
	s.pshape([0.065, -0.15, 0.06, 0.34, 0.115, 0.34, 0.11, -0.13], fill, edge_lw * 0.7, 0.3)
	s.pshape([0.08, 0.34, 0.2 + flag_wave * 0.02, 0.22, 0.28, 0.06 + flag_wave * 0.02, 0.23, -0.03, 0.24, 0.1, 0.16, 0.2, 0.09, 0.24], fill, edge_lw * 0.7)


static func draw_note(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, i: int, x: float, y: float, z: int, t: float, since: float) -> void:
	var T := env.tones
	var bob := sin(t * 2.1 + i * 1.7) * 0.07
	var cy := y + bob + (since * 1.6 if since >= 0.0 else 0.0)
	var turn := cos(t * 1.6 + i * 1.3)
	var sx := (0.12 * (signf(turn) if turn != 0.0 else 1.0)) if absf(turn) < 0.12 else turn
	var X := p.ox + x * p.k
	var Y := p.oy - cy * p.k
	var turn_xf := Transform2D(Vector2(sx, 0), Vector2(0, 1), Vector2(X, Y))
	if since < 0.0:
		# Soft radiance as a ring of short gold strokes (never a bloom), then the glyph,
		# recorded once per boil frame and turned with a transform.
		var s := _sk.setup(pt, env, p, x, cy, z, 1.0, 4001 + i * 37, p.boil)
		s.rays(0, -0.02, 0.38, 0.5, 9, PageTones.mix(T.gold, T.paper, 0.15), 0.35 * (0.7 + 0.3 * sin(t * 3 + i)), t * 0.25 + i, 1)
		var flags := (1 if turn >= 0.0 else 0) + (2 if turn > 0.2 else 0)
		var key := "n%d.%d.%d" % [i, p.boil, flags]
		var rec: Variant = env.cache.lookup(key)
		if rec == null:
			pt.begin_record()
			_note_glyph(pt, p.local(x, cy), env, i, z, t, turn, -1.0)
			rec = pt.end_record()
			env.cache.store(key, rec)
		pt.replay(rec, turn_xf)
		var g := sin(t * 0.9 + i * 2.3)
		if g > 0.93:
			var kk := (g - 0.93) / 0.07
			for q in PageInk.glint_quads(X - 0.1 * p.k * sx, Y - 0.04 * p.k, p.k * 0.16 * kk, t):
				pt.fill(q, Color8(255, 252, 236, 242))
	else:
		# Taken: the glyph rises and fades.
		pt.galpha = maxf(0.0, 1.0 - since / 0.7)
		pt.set_xf(Transform2D(Vector2(sx, 0), Vector2(0, 1), Vector2(X - X * sx, 0)))
		_note_glyph(pt, p, env, i, z, t, turn, since, x, cy)
		pt.reset_state()


static func _note_glyph(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, i: int, z: int, t: float, turn: float, since: float, bx: float = 0.0, by: float = 0.0) -> void:
	var T := env.tones
	var s := _sk.setup(pt, env, p, bx, by, z, 1.0, 4001 + i * 37, p.boil)
	s.tint_amt = 0.45
	s.weight = 0.75
	var gold := s.col(T.gold, 0.6) if turn >= 0.0 else s.col(PageTones.mix(T.gold, T.gold_dark, 0.35), 0.6)
	note_shape(s, gold, 0.5 if since >= 0.0 else 0.85, sin(t * 5 + i))
	# Gold leaf: a bright crescent on the head and cracked-leaf flecks.
	if turn > 0.2:
		s.blot(-0.11, -0.14, 0.08, 0.04, T.gold_light, 0.85)
		s.marks([0.08, 0.3, 0.09, -0.05], T.gold_light, 1.2, 0.6)


## A note hidden behind a column still shows a faint glint so the player knows it is there.
static func draw_note_hint(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, i: int, x: float, y: float, t: float) -> void:
	var T := env.tones
	var X := p.ox + x * p.k
	var Y := p.oy - (y + sin(t * 2.1 + i * 1.7) * 0.07) * p.k
	var pulse := 0.5 + 0.5 * sin(t * 2.4 + i)
	env.pat(pt, PageInk.circle_pts(X, Y, p.k * 0.2), PageEnv.CROSS, 0.7 + 0.2 * pulse, p)
	var w := maxf(1.0, 1.3 * p.px)
	var c := PageTones.alpha(T.gold, 0.55 + 0.35 * pulse)
	for kk in 8:
		var a := float(kk) / 8 * TAU + t * 0.3
		var r0 := p.k * 0.22
		var r1 := p.k * (0.3 + 0.06 * pulse)
		pt.seg(X + cos(a) * r0, Y + sin(a) * r0, X + cos(a) * r1, Y + sin(a) * r1, w, c)
	for q in PageInk.glint_quads(X, Y, p.k * (0.13 + 0.06 * pulse), t * 0.4 + i):
		pt.fill(q, Color8(255, 252, 238, int(255 * (0.75 + 0.25 * pulse))))


# ---------------------------------------------------------------- checkpoints

static func draw_checkpoint(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, i: int, frame: Dictionary) -> void:
	var T := env.tones
	var c: V3 = game.level.checkpoints[i].pos
	var active := game.checkpoint_on == i
	var visited := game.checkpoint_at[i] >= 0.0
	var lz := layer_of(env, c.z)
	var s := _sk.setup(pt, env, p, c.x, c.y, lz, 1.0, 5003 + i * 53, p.boil)
	s.tint_amt = 0.7
	var brass := T.mat_color("brass")
	var since := game.time - game.checkpoint_at[i] if visited else 99.0
	# Warm light when lit.
	if visited:
		var pulse := 1.0 - since / 0.8 if since < 0.8 else 0.0
		s.rays(0, 0.95, 0.55 + pulse * 0.2, 0.85 + pulse * 0.6, 14, s.col(T.gold, 0.5), (0.4 if active else 0.22) + pulse * 0.4, game.time * 0.2, 1.1)
	# The case and face plate, recorded per boil frame in world pixels.
	var key := "c%d.%d.%d" % [i, p.boil, 1 if visited else 0]
	var hit: Variant = env.cache.lookup(key)
	if hit == null:
		pt.begin_record()
		var rs := _sk.setup(pt, env, p.local(0, 0), c.x, c.y, lz, 1.0, 5003 + i * 53, p.boil)
		rs.tint_amt = 0.7
		_checkpoint_case(rs, env, visited)
		hit = [pt.end_record(), rs.n]
		env.cache.store(key, hit)
	pt.replay(hit[0], Transform2D(0.0, Vector2(p.ox, p.oy)))
	s.n = hit[1]
	# The pendulum.
	var beat: float = frame.beat if frame.beat >= 0.0 else game.time * (100.0 / 60.0)
	var ang := 0.42 * sin(PI * beat) if active else 0.0
	var px := 0.0
	var py := 0.3
	var length := 0.95
	var tip_x := px + sin(ang) * length
	var tip_y := py + cos(ang) * length
	s.seg(px, py, tip_x, tip_y, 0.75)
	var wx := px + sin(ang) * length * 0.62
	var wy := py + cos(ang) * length * 0.62
	s.ellipse(wx, wy, 0.07, 0.05, ang, s.col(T.gold if visited else brass), 0.55)
	s.dot(px, py, 0.035, s.col(brass))
	if active:
		s.dot(tip_x, tip_y, 0.03, T.gold_light)


static func _checkpoint_case(s: PageSketch, env: PageEnv, visited: bool) -> void:
	var T := env.tones
	var stone := T.mat_color("stone")
	var wood := T.mat_color("wood")
	var brass := T.mat_color("brass")
	s.pshape([-0.36, 0, -0.36, 0.16, 0.36, 0.16, 0.36, 0], s.col(stone), 0.8)
	var body: Array = [-0.27, 0.16, -0.1, 1.12, 0.1, 1.12, 0.27, 0.16]
	s.pshape(body, s.col(PageTones.mix(wood, brass, 0.25) if visited else PageTones.mix(wood, T.ink, 0.15)), 0.9)
	s.clip(body, func() -> void: s.blot(0.25, 0.6, 0.12, 0.6, PageEnv.HATCH, 0.5), true)
	# Face plate with tempo ticks.
	s.pshape([-0.12, 0.32, -0.06, 0.98, 0.06, 0.98, 0.12, 0.32], s.col(PageTones.mix(T.paper, brass, 0.3)), 0.5, 0.3)
	var ticks: Array = []
	for kk in 6:
		var v := 0.42 + kk * 0.1
		ticks.append_array([-0.05, v, 0.05, v])
	s.marks(ticks, s.col(T.ink), 0.8, 0.6)


# ---------------------------------------------------------------- the Fermata arch

static func draw_exit(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim) -> void:
	var T := env.tones
	var e := game.level.exit_pos
	var pl := game.player
	var dist := Vector2(pl.pos.x - e.x, pl.pos.y - e.y).length()
	var near := clampf(1.0 - (dist - 1.0) / 7.0, 0.0, 1.0)
	var done := minf(1.0, (game.time - game.finished_at) / 1.2) if game.finished else 0.0
	var glow := minf(1.0, near * 0.7 + done)
	var t := game.time
	var lz := layer_of(env, e.z)
	var s := _sk.setup(pt, env, p, e.x, e.y, lz, 1.0, 6007, p.boil)
	s.tint_amt = 0.5
	var ri := 0.92
	var ph := 2.25
	# The veil: gold threads hanging in the opening, drifting.
	var strands := 13
	var segs: Array = []
	for st in strands:
		var u0 := -ri + 0.08 + ((2 * ri - 0.16) * st) / (strands - 1)
		var top_v := ph + sqrt(maxf(0.0, ri * ri - u0 * u0)) - 0.08
		for kk in 6:
			var v0 := 0.05 + (top_v * kk) / 6
			var v1 := 0.05 + (top_v * (kk + 1)) / 6
			var sw0 := sin(t * 1.4 + st * 0.9 + v0 * 2.2) * 0.04 * (1 + glow)
			var sw1 := sin(t * 1.4 + st * 0.9 + v1 * 2.2) * 0.04 * (1 + glow)
			segs.append_array([u0 + sw0, v0, u0 + sw1, v1])
	s.marks(segs, PageTones.mix(T.gold, T.gold_light, 0.5), 1.1, 0.18 + 0.5 * glow)
	# Motes of light rising through it.
	for kk in 8:
		var ph2 := fmod(t * (0.25 + PageRand.hash01(kk, 1) * 0.2) + PageRand.hash01(kk, 2), 1.0)
		var u := -ri * 0.8 + PageRand.hash01(kk, 3) * ri * 1.6 + sin(t + kk) * 0.05
		var v := ph2 * (ph + ri * 0.7)
		s.dot(u, v, 0.025 + 0.02 * glow, T.gold_light, (0.3 + 0.6 * glow) * sin(ph2 * PI))
	# Piers, arch ring and keystone, and the golden fermata, recorded per boil frame.
	var key := "x.%d" % p.boil
	var rec: Variant = env.cache.lookup(key)
	if rec == null:
		var rs := _sk.setup(pt, env, p.local(0, 0), e.x, e.y, lz, 1.0, 6007, p.boil)
		rs.tint_amt = 0.5
		pt.begin_record()
		_exit_arch(rs, env)
		var arch := pt.end_record()
		pt.begin_record()
		_exit_fermata(rs, env)
		rec = [arch, pt.end_record()]
		env.cache.store(key, rec)
	var at := Transform2D(0.0, Vector2(p.ox, p.oy))
	pt.replay(rec[0], at)
	var fv := ph + 1.32 + 0.62
	var shimmer := 0.6 + 0.4 * sin(t * 2.2)
	s.rays(0, fv - 0.02, 0.62, 1.0 + 0.3 * glow, 20, T.gold, 0.3 + 0.35 * glow * shimmer, t * 0.15, 1.2)
	pt.replay(rec[1], at)
	if sin(t * 0.8) > 0.9:
		var kk := (sin(t * 0.8) - 0.9) / 0.1
		for q in PageInk.glint_quads(s.X(-0.38), s.Y(fv + 0.16), p.k * 0.26 * kk, t):
			pt.fill(q, Color8(255, 252, 236, 242))


static func _exit_arch(s: PageSketch, env: PageEnv) -> void:
	var T := env.tones
	var marble := T.mat_color("marble")
	var stone := s.col(marble)
	var ri := 0.92
	var ro := 1.32
	var ph := 2.25
	for sd in [-1.0, 1.0]:
		var pier: Array = [sd * ri, 0, sd * ri, ph, sd * ro, ph, sd * ro, 0]
		s.pshape(pier, stone, 1)
		if sd == 1.0:
			s.clip(pier, func() -> void: s.blot(ro, ph / 2, 0.22, ph, PageEnv.HATCH, 0.55), true)
		var joints: Array = []
		var v := 0.45
		while v < ph:
			joints.append_array([sd * ri, v, sd * ro, v])
			v += 0.45
		s.marks(joints, s.darker(marble, 0.35), 0.9, 0.6)
		s.pshape([sd * (ri - 0.08), 0, sd * (ri - 0.08), 0.18, sd * (ro + 0.08), 0.18, sd * (ro + 0.08), 0], stone, 0.8)
	var n := 9
	for i in n:
		var a0 := PI - (float(i) / n) * PI
		var a1 := PI - (float(i + 1) / n) * PI
		var o := ro + 0.14 if i == floori(n / 2.0) else ro
		s.pshape([cos(a0) * ri, ph + sin(a0) * ri, cos(a0) * o, ph + sin(a0) * o, cos(a1) * o, ph + sin(a1) * o, cos(a1) * ri, ph + sin(a1) * ri], stone, 0.8, 0.3)


static func _exit_fermata(s: PageSketch, env: PageEnv) -> void:
	var T := env.tones
	var fv := 2.25 + 1.32 + 0.62
	s.tint_amt = 0.2
	var gold := s.col(T.gold)
	s.shape([-0.62, fv - 0.16, -0.52, fv + 0.2, 0, fv + 0.4, 0.52, fv + 0.2, 0.62, fv - 0.16, 0.52, fv - 0.09, 0.4, fv + 0.1, 0, fv + 0.25, -0.4, fv + 0.1, -0.52, fv - 0.09], gold, 0.9, 0.95, true, 1.0, false)
	s.marks([-0.42, fv + 0.17, 0.06, fv + 0.32], T.gold_light, 1.6, 0.85)
	s.ellipse(0, fv - 0.17, 0.11, 0.1, 0, gold, 0.8)
	s.dot(-0.03, fv - 0.14, 0.03, T.gold_light, 0.9)


# ---------------------------------------------------------------- drums

static func draw_drum(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, x: float, y: float, z: int, hit: float, i: int) -> void:
	if hit >= 0.6:
		# At rest the drum only boils: record it once per boil frame.
		var key := "d%d.%d" % [i, p.boil]
		var rec: Variant = env.cache.lookup(key)
		if rec == null:
			pt.begin_record()
			_drum(pt, p.local(0, 0), env, x, y, z, hit, i)
			rec = pt.end_record()
			env.cache.store(key, rec)
		pt.replay(rec, Transform2D(0.0, Vector2(p.ox, p.oy)))
		return
	_drum(pt, p, env, x, y, z, hit, i)


static func _drum(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, x: float, y: float, z: int, hit: float, i: int) -> void:
	var T := env.tones
	var s := _sk.setup(pt, env, p, x + 0.5, y, z, 1.0, 7001 + i * 17, p.boil)
	s.tint_amt = 0.7
	var brass := T.mat_color("brass")
	var copper := PageTones.mix(PageTones.rgb("#b8683a"), brass, 0.25)
	var cream := PageTones.rgb("#e6e0cc") if T.inv else PageTones.rgb("#f1e6c8")
	var kk := 1.0 - hit / 0.6 if hit < 0.6 else 0.0
	var dip := sin(minf(1.0, hit / 0.18) * PI) * 0.07 * (1.0 if hit < 0.18 else 0.0)
	s.seg(-0.3, 0.02, -0.2, 0.22, 0.7)
	s.seg(0.3, 0.02, 0.2, 0.22, 0.7)
	s.seg(0, 0.02, 0, 0.18, 0.6)
	var bowl: Array = [-0.42, 0.6, -0.4, 0.4, -0.28, 0.22, 0, 0.14, 0.28, 0.22, 0.4, 0.4, 0.42, 0.6]
	s.shape(bowl, s.col(copper), 1)
	s.clip(bowl, func() -> void: s.blot(0.3, 0.25, 0.3, 0.3, PageEnv.CROSS, 0.55))
	s.marks([-0.3, 0.52, -0.26, 0.3], s.lighter(copper, 0.55), 1.8, 0.7)
	s.pshape([-0.45, 0.6, -0.45, 0.68, 0.45, 0.68, 0.45, 0.6], s.col(brass), 0.7)
	var lugs: Array = []
	for l in range(-2, 3):
		lugs.append_array([l * 0.17, 0.62, l * 0.17, 0.5])
	s.marks(lugs, s.darker(brass, 0.4), 1.4, 0.8)
	s.ellipse(0, 0.69 - dip, 0.43, 0.055, 0, s.col(cream), 0.6)
	if kk > 0.0:
		var segs: Array = []
		for r in 3:
			var rr := 0.1 + fmod((1 - kk) * 0.5 + r * 0.12, 0.45)
			segs.append_array([-rr, 0.69 - dip, rr, 0.69 - dip])
		s.marks(segs, s.darker(cream, 0.35), 1, 0.6 * kk)
		var c := PageTones.alpha(s.ink_color(), 0.6 * kk)
		var w := maxf(1.0, 1.3 * p.px)
		for r in 3:
			var rad := (0.35 + (1 - kk) * 0.9 + r * 0.22) * p.k
			pt.stroke(PageInk.arc_pts(s.X(0), s.Y(0.75), rad, rad, 0, -0.85 * PI, -0.15 * PI), w, c)


# ---------------------------------------------------------------- keys

## A piano key set into the floor, seen side on: an ivory cap with a rounded nose and lip,
## on an ebony key body that stands in a slot in the ground. The whole key sinks as it is
## pressed. The group's lozenge (the same mark its gates carry) is inked on the ivory and
## brightens, with a few radiating strokes, when it goes down.
static func draw_key(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, i: int) -> void:
	var k: Dictionary = game.level.keys[i]
	var v: float = game.key_vis[i] if i < game.key_vis.size() else 0.0
	var on: bool = game.groups[k.group]
	if v == 0.0 or v == 1.0:
		# Resting up or held down, a key only boils: record it once per boil frame.
		var key := "k%d.%d.%d.%d" % [i, p.boil, 1 if on else 0, int(v)]
		var rec: Variant = env.cache.lookup(key)
		if rec == null:
			pt.begin_record()
			_key(pt, p.local(0, 0), env, game, i, v, on)
			rec = pt.end_record()
			env.cache.store(key, rec)
		pt.replay(rec, Transform2D(0.0, Vector2(p.ox, p.oy)))
		return
	_key(pt, p, env, game, i, v, on)


static func _key(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, i: int, v: float, on: bool) -> void:
	var T := env.tones
	var k: Dictionary = game.level.keys[i]
	var kp: V3 = k.pos
	var s := _sk.setup(pt, env, p, kp.x, kp.y, layer_of(env, kp.z), 1.0, 8009 + i * 23, p.boil)
	s.tint_amt = 0.4
	var w: float = k.width
	var ivory := PageTones.rgb("#ece6d4") if T.inv else PageTones.rgb("#fbf3de")
	var ebony := PageTones.rgb("#11131f") if T.inv else PageTones.mix(T.ink, Color8(12, 8, 10), 0.5)
	var gc: Color = T.groups[k.group % T.groups.size()]
	var top := 0.24 - v * 0.17
	var cap_h := 0.12
	var x0 := 0.1
	var x1 := w - 0.1
	# The slot, a dark keybed cut into the floor, and the ebony key body standing in it.
	s.pshape([x0 - 0.04, -0.12, x0 - 0.04, 0.015, x1 + 0.04, 0.015, x1 + 0.04, -0.12], PageTones.mix(ebony, T.shade, 0.3), 0.55, 0.2)
	s.pshape([x0 + 0.03, -0.1, x0 + 0.03, top - cap_h + 0.01, x1 - 0.06, top - cap_h + 0.01, x1 - 0.06, -0.1], ebony, 0.5, 0.2)
	# The ivory cap: square at the back (left), a rounded nose and lip at the front (right).
	var c0 := top - cap_h
	s.pshape([x0, c0, x0, top, x1 - 0.06, top, x1 - 0.015, top - 0.02, x1, top - 0.055, x1 - 0.005, c0 + 0.02, x1 - 0.03, c0 - 0.01], s.col(ivory), 0.75, 0.2)
	s.marks([x0 + 0.04, top - 0.03, x1 - 0.08, top - 0.03], Color8(255, 253, 245, 242), 1.3, 0.9)
	s.marks([x0 + 0.02, c0 + 0.025, x1 - 0.05, c0 + 0.025], s.darker(ivory, 0.3), 1.2, 0.55)
	# The group mark: muted at rest, full colour with rays when pressed or its group is on.
	var lit := maxf(v, 0.6 if on else 0.0)
	var mv := top - cap_h / 2
	var mr := 0.055
	var mc := PageTones.mix(PageTones.mix(gc, ivory, 0.25), gc, lit)
	s.pshape([w / 2, mv - mr, w / 2 + mr * 1.5, mv, w / 2, mv + mr, w / 2 - mr * 1.5, mv], mc, 0.45, 0.15)
	if v > 0.05:
		var segs: Array = []
		var n := 5
		for q in n:
			var a := PI * (0.2 + (0.6 * q) / (n - 1))
			var r0 := 0.22
			var r1 := 0.22 + 0.16 * v
			segs.append_array([w / 2 + cos(a) * r0 * 1.6, top + sin(a) * r0, w / 2 + cos(a) * r1 * 1.6, top + sin(a) * r1])
		s.marks(segs, gc, 1.4, 0.75 * v)


# ---------------------------------------------------------------- gates

## Gates come in three shapes, all gold leaf crossed by a five-line staff: upright grilles
## of spear-topped bars (taller than wide), gilded step blocks (wide and tall, the golden
## stairs) and planks (one cell tall, the bridges). A solid gate rises out of the floor (a
## plank inks itself across) as the key raises it; an open one is a faint dotted ghost.
static func draw_gate(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, b: Sim.Body) -> void:
	var def: Dictionary = game.level.gates[b.id]
	var vis: float = game.gate_vis[b.id] if b.id < game.gate_vis.size() else (1.0 if b.solid else 0.0)
	var w := b.max.x - b.min.x
	var h := b.max.y - b.min.y
	var shape := "plank" if h <= 1.05 else ("step" if w >= 1.5 else "bars")
	var t := game.time
	var lz := layer_of(env, b.min.z)
	var s := _sk.setup(pt, env, p, b.min.x, b.min.y, lz, 1.0, 8501 + b.id * 29, p.boil)
	s.tint_amt = 0.3
	if vis < 0.98:
		_gate_ghost(pt, p, env, s, def.group, shape, w, h, 1.0 - vis, t)
	if vis <= 0.02:
		return
	# Ease the reveal so the last stretch settles rather than snaps.
	var e := 1.0 - (1.0 - vis) * (1.0 - vis)
	var clipped := vis < 0.98
	if clipped:
		var r: Rect2
		if shape == "plank":
			r = Rect2(s.X(-0.2), s.Y(h + 0.4), s.D(w * e + 0.2), s.D(h + 0.6))
		else:
			r = Rect2(s.X(-0.3), s.Y(h * e + (0.4 if shape == "bars" else 0.1)), s.D(w + 0.6), s.D(h * e + 0.6))
		pt.use(PagePainter.CLIP, PackedVector4Array([Vector4(r.position.x, r.position.y, r.end.x, r.end.y)]))
	# Solid gates are drawn once per boil drawing (three, as the cached page is) and replayed.
	var v := posmod(p.boil, 3)
	var key := "g%d.%d" % [b.id, v]
	var rec: Variant = env.cache.lookup(key)
	if rec == null:
		pt.begin_record()
		var lp := p.local(0, 0)
		lp.boil = v
		var rs := _sk.setup(pt, env, lp, b.min.x, b.min.y, lz, 1.0, 8501 + b.id * 29, v)
		rs.tint_amt = 0.3
		match shape:
			"bars": _gate_bars(rs, env, def.group, w, h, b.id)
			"step": _gate_step(rs, env, def.group, w, h, b.id)
			_: _gate_plank(rs, env, def.group, w, h, b.id)
		rec = pt.end_record()
		env.cache.store(key, rec)
	pt.replay(rec, Transform2D(0.0, Vector2(p.ox, p.oy)))
	if clipped:
		pt.use(PagePainter.NORMAL)


## A dashed line as point pairs (ctx.setLineDash).
static func dashes(x0: float, y0: float, x1: float, y1: float, on: float, off: float, offset: float) -> Array:
	var out: Array = []
	var d := Vector2(x1 - x0, y1 - y0)
	var l := d.length()
	if l <= 0.0:
		return out
	var u := d / l
	var period := on + off
	var s := -fposmod(offset, period)
	while s < l:
		var a := maxf(0.0, s)
		var b := minf(l, s + on)
		if b > a:
			out.append([Vector2(x0, y0) + u * a, Vector2(x0, y0) + u * b])
		s += period
	return out


## Positions of the five staff lines of a staff centred on `v`.
static func _staff_lines(v: float, gap: float) -> Array:
	return [v - 2 * gap, v - gap, v, v + gap, v + 2 * gap]


## Staff centres on a gate face: one per three cells of height on a grille, one under a
## step's tread.
static func _gate_staffs(shape: String, h: float) -> Array:
	if shape == "plank":
		return [h * 0.52]
	if shape == "step":
		return [h - 0.48]
	var n := maxi(1, PageInk.jround(h / 3.0))
	var out: Array = []
	for i in n:
		out.append((h * (i + 0.5)) / n)
	return out


## A lozenge in the group colour (the mark the gate shares with its key).
static func _group_mark(s: PageSketch, env: PageEnv, group: int, u: float, v: float, r: float) -> void:
	var gc: Color = env.tones.groups[group % env.tones.groups.size()]
	s.pshape([u, v - r, u + r * 0.8, v, u, v + r, u - r * 0.8, v], gc, 0.6, 0.2)
	s.dot(u - r * 0.2, v + r * 0.3, r * 0.22, Color8(255, 250, 236, 217))


## Cracked gold leaf: a scatter of bright flecks inside a rectangle.
static func _gold_flecks(s: PageSketch, env: PageEnv, u0: float, v0: float, u1: float, v1: float, n: int, seed: int) -> void:
	var c := PageTones.alpha(env.tones.gold_light, 0.85)
	for i in n:
		var x := s.X(u0 + PageRand.hash01(seed, i, 1) * (u1 - u0))
		var y := s.Y(v0 + PageRand.hash01(seed, i, 2) * (v1 - v0))
		var r := maxf(0.6, s.D(0.012 + PageRand.hash01(seed, i, 3) * 0.018))
		s.painter.dot(x, y, r, c)


static func _gate_gold(s: PageSketch, env: PageEnv, dark: float = 0.0) -> Color:
	var T := env.tones
	return s.col(PageTones.mix(PageTones.mix(T.gold, T.gold_light, 0.12), T.gold_dark, dark))


## An upright grille: spear-topped gilded bars between gold rails, crossed by staves.
static func _gate_bars(s: PageSketch, env: PageEnv, group: int, w: float, h: float, id: int) -> void:
	var T := env.tones
	var ink := s.ink_color()
	var gold := _gate_gold(s, env)
	var gold_dim := _gate_gold(s, env, 0.3)
	# A dark gilded ground between the bars so the grille reads as a wall, not a frame.
	s.region([0.08, 0.05, 0.08, h - 0.1, w - 0.08, h - 0.1, w - 0.08, 0.05], s.col(PageTones.mix(T.gold_dark, T.gold, 0.35)), 0.5 if T.inv else 0.42, true)
	s.region([0.08, 0.05, 0.08, h - 0.1, w - 0.08, h - 0.1, w - 0.08, 0.05], PageEnv.CROSS, 0.55, true)
	var nb := maxi(3, PageInk.jround(w * 4))
	var bw := 0.075
	var top := h - 0.02
	for i in nb:
		var u := 0.14 + ((w - 0.28) * i) / (nb - 1)
		s.pshape([u - bw / 2, 0, u - bw / 2, top, u + bw / 2, top, u + bw / 2, 0], gold, 0.55, 0.25)
		# Spear point above the top rail.
		s.pshape([u - 0.075, top + 0.02, u, top + 0.3, u + 0.075, top + 0.02], gold_dim, 0.55, 0.2)
	var shade: Array = []
	var lit: Array = []
	for i in nb:
		var u := 0.14 + ((w - 0.28) * i) / (nb - 1)
		shade.append_array([u + bw * 0.3, 0.05, u + bw * 0.3, top - 0.05])
		lit.append_array([u - bw * 0.2, 0.08, u - bw * 0.2, top - 0.08])
	s.marks(shade, s.darker(T.gold, 0.5), 1.1, 0.7)
	s.marks(lit, T.gold_light, 0.9, 0.8)
	# Rails: a heavy foot and a capping rail.
	s.pshape([-0.04, 0, -0.04, 0.16, w + 0.04, 0.16, w + 0.04, 0], gold_dim, 0.8, 0.3)
	s.pshape([-0.04, top - 0.16, -0.04, top, w + 0.04, top, w + 0.04, top - 0.16], gold, 0.8, 0.3)
	s.marks([0, top - 0.04, w, top - 0.04], T.gold_light, 1, 0.8)
	# Staves: five fine lines crossing the bars, with the group's lozenge as their clef.
	var lines: Array = []
	for v in _gate_staffs("bars", h):
		for lv in _staff_lines(v, 0.07):
			lines.append_array([-0.06, lv, w + 0.06, lv])
	s.marks(lines, ink, 1, 0.85)
	for v in _gate_staffs("bars", h):
		_group_mark(s, env, group, w / 2, v, 0.15)
	_gold_flecks(s, env, 0.1, 0.2, w - 0.1, top - 0.2, PageInk.jround(h * 4), 900 + id)


## A gilded step: a solid block of gold leaf with a tread to stand on and a staff under
## the nosing.
static func _gate_step(s: PageSketch, env: PageEnv, group: int, w: float, h: float, id: int) -> void:
	var T := env.tones
	var ink := s.ink_color()
	var body: Array = [0.02, 0, 0.02, h - 0.14, w - 0.02, h - 0.14, w - 0.02, 0]
	s.pshape(body, _gate_gold(s, env, 0.08), 0.9, 0.3)
	s.clip(body, func() -> void:
		# Volume: hatched shade down the right and under the tread, a warm lit band on the left.
		s.blot(w, h * 0.45, w * 0.35, h * 0.7, PageEnv.HATCH, 0.6)
		s.blot(w / 2, h - 0.14, w * 0.8, 0.12, PageEnv.CROSS, 0.55)
		s.blot(0.15, h * 0.5, 0.18, h * 0.6, T.gold_light, 0.35)
		# Faint seams where the sheets of leaf were laid, staggered so they never line up.
		var seams: Array = []
		var v := 0.55
		var r := 0
		while v < h - 0.6:
			var off := 0.5 if r % 2 else 0.0
			var u := 0.5 + off
			while u < w - 0.1:
				seams.append_array([u, v - 0.5, u, v])
				u += 1.0
			v += 0.55
			r += 1
		s.marks(seams, s.darker(T.gold, 0.4), 0.8, 0.35), true)
	# Courses every two cells, level with the neighbouring treads.
	var courses: Array = []
	var lits: Array = []
	var cv := h - 2.0
	while cv > 0.5:
		courses.append_array([0.02, cv, w - 0.02, cv])
		lits.append_array([0.06, cv + 0.05, w - 0.06, cv + 0.05])
		cv -= 2.0
	if not courses.is_empty():
		s.marks(courses, ink, 1.4, 0.75)
		s.marks(lits, T.gold_light, 1, 0.6)
	# The tread: a lighter gold board with a rounded nosing that overhangs the riser.
	s.pshape([-0.05, h - 0.16, -0.08, h - 0.08, -0.05, h, w + 0.05, h, w + 0.08, h - 0.08, w + 0.05, h - 0.16], s.col(PageTones.mix(T.gold, T.gold_light, 0.45)), 0.9, 0.25)
	s.marks([0.05, h - 0.035, w - 0.05, h - 0.035], T.gold_light, 1.3, 0.9)
	# Staff engraved beneath the nosing.
	var lines: Array = []
	var sv: float = _gate_staffs("step", h)[0]
	for lv in _staff_lines(sv, 0.085):
		lines.append_array([0.08, lv, w - 0.08, lv])
	lines.append_array([w - 0.3, sv - 0.17, w - 0.3, sv + 0.17])
	s.marks(lines, ink, 1, 0.85)
	s.marks([w - 0.2, sv - 0.17, w - 0.2, sv + 0.17], ink, 2.2, 0.85)
	_group_mark(s, env, group, 0.3, sv, 0.15)
	# A few engraved notes climbing the staff, as a stair should.
	for q in 3:
		var u := 0.62 + q * ((w - 1.1) / 2)
		var v := sv - 0.085 + q * 0.085
		s.ellipse(u, v, 0.07, 0.05, 0.35, ink, 0, 0.85)
		s.marks([u + 0.06, v, u + 0.06, v + 0.24], ink, 1.1, 0.85)
	_gold_flecks(s, env, 0.1, 0.15, w - 0.1, h - 0.3, mini(16, PageInk.jround(w * h * 1.5)), 1300 + id)


## A gilded plank: one cell deep, a staff running its length, bar lines at each measure.
static func _gate_plank(s: PageSketch, env: PageEnv, group: int, w: float, h: float, id: int) -> void:
	var T := env.tones
	var ink := s.ink_color()
	var v0 := 0.14
	var v1 := h - 0.02
	var board: Array = [-0.02, v0, -0.02, v1, w + 0.02, v1, w + 0.02, v0]
	s.pshape(board, _gate_gold(s, env, 0.05), 0.9, 0.3)
	s.clip(board, func() -> void:
		s.region([-0.1, v0, -0.1, v0 + 0.22, w + 0.1, v0 + 0.22, w + 0.1, v0], PageEnv.HATCH, 0.6, true)
		s.region([-0.1, v1 - 0.12, -0.1, v1, w + 0.1, v1, w + 0.1, v1 - 0.12], T.gold_light, 0.45, true), true)
	# The staff along it, bar lines every two cells and a double bar at each end.
	var sv: float = _gate_staffs("plank", h)[0]
	var lines: Array = []
	for lv in _staff_lines(sv, 0.11):
		lines.append_array([0.06, lv, w - 0.06, lv])
	var u := 2.0
	while u < w - 0.5:
		lines.append_array([u, sv - 0.22, u, sv + 0.22])
		u += 2.0
	s.marks(lines, ink, 1, 0.8)
	s.marks([0.08, sv - 0.22, 0.08, sv + 0.22, w - 0.08, sv - 0.22, w - 0.08, sv + 0.22], ink, 2.2, 0.85)
	s.marks([0.17, sv - 0.22, 0.17, sv + 0.22, w - 0.17, sv - 0.22, w - 0.17, sv + 0.22], ink, 1, 0.85)
	s.marks([0.02, v1 - 0.03, w - 0.02, v1 - 0.03], T.gold_light, 1.3, 0.9)
	_group_mark(s, env, group, 0.42, sv, 0.13)
	if w > 3:
		_group_mark(s, env, group, w - 0.42, sv, 0.13)
	_gold_flecks(s, env, 0.1, v0 + 0.1, w - 0.1, v1 - 0.1, PageInk.jround(w * 4), 1700 + id)


## The open gate: its outline and staves as faint dotted gold, drifting slowly.
static func _gate_ghost(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, s: PageSketch, group: int, shape: String, w: float, h: float, a: float, t: float) -> void:
	var T := env.tones
	var gold := PageTones.mix(T.gold, T.gold_light, 0.15)
	var vb := 0.14 if shape == "plank" else 0.0
	var top := h if shape == "step" else h - 0.02
	var off := -t * 6 * p.px
	var c := PageTones.alpha(gold, 0.6 * a)
	var wl := maxf(1.0, 1.5 * p.px)
	var gap := 0.11 if shape == "plank" else 0.07
	for v in _gate_staffs(shape, h):
		for lv in _staff_lines(v, gap):
			for d in dashes(s.X(0.06), s.Y(lv), s.X(w - 0.06), s.Y(lv), 2.5 * p.px, 5 * p.px, off):
				pt.seg(d[0].x, d[0].y, d[1].x, d[1].y, wl, c)
	# The outline (and the bars of a grille), dotted.
	var c2 := PageTones.alpha(gold, 0.45 * a)
	var w2 := maxf(1.0, 1.2 * p.px)
	var X0 := s.X(0.04)
	var X1 := s.X(w - 0.04)
	var Yt := s.Y(top)
	var Yb := s.Y(vb)
	var outline := PackedVector2Array([Vector2(X0, Yt), Vector2(X1, Yt), Vector2(X1, Yb), Vector2(X0, Yb)])
	for d in PageQuaver.dash_poly(outline, true, 3 * p.px, 4 * p.px, off):
		for q in range(d.size() - 1):
			pt.seg(d[q].x, d[q].y, d[q + 1].x, d[q + 1].y, w2, c2)
	if shape == "bars":
		var nb := maxi(3, PageInk.jround(w * 4))
		for i in range(1, nb - 1):
			var u := 0.14 + ((w - 0.28) * i) / (nb - 1)
			for d in dashes(s.X(u), s.Y(0), s.X(u), s.Y(top), 3 * p.px, 4 * p.px, off):
				pt.seg(d[0].x, d[0].y, d[1].x, d[1].y, w2, c2)
	# The group's lozenge stays faintly visible so the gate can still be matched to its key.
	var gc: Color = T.groups[group % T.groups.size()]
	for v in _gate_staffs(shape, h):
		var u := w / 2 if shape == "bars" else (0.32 if shape == "step" else 0.42)
		var r := 0.12
		pt.fill(PackedVector2Array([Vector2(s.X(u), s.Y(v - r)), Vector2(s.X(u + r * 0.8), s.Y(v)), Vector2(s.X(u), s.Y(v + r)), Vector2(s.X(u - r * 0.8), s.Y(v))]), PageTones.alpha(gc, 0.55 * a))


# ---------------------------------------------------------------- moving platforms

static func draw_platform(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, b: Sim.Body, x0: float, y0: float, z0: float, w: float, h: float) -> void:
	var T := env.tones
	var t := game.time
	var lz := layer_of(env, z0)
	var s := _sk.setup(pt, env, p, x0, y0, lz, 1.0, 9001 + b.id * 31, p.boil)
	s.tint_amt = 0.65
	# Soft light underneath, as fanned strokes.
	var segs: Array = []
	var n := maxi(5, PageInk.jround(w * 5))
	for i in n:
		var u := (w * (i + 0.5)) / n
		var length := 0.35 + 0.2 * sin(t * 2.5 + i * 1.7)
		segs.append_array([u, -0.08, u + (u - w / 2) * 0.15, -0.08 - length])
	s.marks(segs, PageTones.mix(T.gold, T.gold_light, 0.4), 1, 0.35)
	# The stand and desk are recorded per boil frame and move with the platform; the
	# hatching inside the desk stays anchored to the page, as on the web build.
	var key := "p%d.%d" % [b.id, p.boil]
	var hit: Variant = env.cache.lookup(key)
	var desk: Array = [0, 0, 0, h, w, h, w, 0]
	if hit == null:
		var lp := p.local(x0, y0)
		var rs := _sk.setup(pt, env, lp, x0, y0, lz, 1.0, 9001 + b.id * 31, p.boil)
		rs.tint_amt = 0.65
		pt.begin_record()
		_platform_desk(rs, env, game, b, w, h)
		var a := pt.end_record()
		var n1 := rs.n
		rs.clip(desk, func() -> void: pass, true)
		pt.begin_record()
		_platform_trim(rs, env, game, b, w, h)
		hit = [a, pt.end_record(), n1]
		env.cache.store(key, hit)
	var at := Transform2D(0.0, Vector2(p.ox + x0 * p.k, p.oy - y0 * p.k))
	pt.replay(hit[0], at)
	s.n = hit[2]
	s.clip(desk, func() -> void: s.blot(w, h * 0.2, w * 0.4, h * 0.5, PageEnv.HATCH, 0.45), true)
	pt.replay(hit[1], at)


static func _platform_desk(s: PageSketch, env: PageEnv, game: Sim, b: Sim.Body, w: float, h: float) -> void:
	var def: Dictionary = game.level.platforms[b.id]
	var cx := w / 2
	s.seg(cx, 0, cx, -0.55, 0.7, null, 0.8)
	s.seg(cx, -0.55, cx - 0.18, -0.75, 0.55, null, 0.5)
	s.seg(cx, -0.55, cx + 0.18, -0.75, 0.55, null, 0.5)
	s.pshape([0, 0, 0, h, w, h, w, 0], s.col(env.tones.mat_color(def.mat)), 1, 0.5)


static func _platform_trim(s: PageSketch, env: PageEnv, game: Sim, b: Sim.Body, w: float, h: float) -> void:
	var T := env.tones
	var brass := T.mat_color("brass")
	s.pshape([0, h - 0.1, 0, h, w, h, w, h - 0.1], s.col(brass), 0.6, 0.3)
	s.pshape([0, 0, 0, 0.08, w, 0.08, w, 0], s.col(brass), 0.6, 0.3)
	# Sheet music pinned to the desk.
	var sx0 := 0.18
	var sx1 := w - 0.18
	if h >= 0.6 and sx1 - sx0 > 0.4:
		s.pshape([sx0, 0.16, sx0, h - 0.16, sx1, h - 0.16, sx1, 0.16], s.col(PageTones.mix(T.paper, Color8(255, 252, 240), 0.4)), 0.4, 0.3)
		var lines: Array = []
		var notes: Array = []
		for st in 2:
			var base := 0.24 + st * (h - 0.42) * 0.5
			for l in 5:
				lines.append_array([sx0 + 0.05, base + l * 0.035, sx1 - 0.05, base + l * 0.035])
			var m := maxi(2, floori((sx1 - sx0) / 0.35))
			for q in m:
				notes.append_array([sx0 + 0.15 + q * 0.33, base + (PageRand.hash01(b.id, st, q) * 4) * 0.035])
		s.marks(lines, s.ink_color(), 0.6, 0.5)
		for q in range(0, notes.size(), 2):
			s.dot(notes[q], notes[q + 1], 0.03, s.ink_color(), 0.8)


# ---------------------------------------------------------------- discords

static func draw_discord(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, i: int, x: float, y: float, z: int, frame: Dictionary) -> void:
	var T := env.tones
	var restless := floori(frame.now * 12)
	var jx := PageRand.hs(i, restless, 1) * 0.03
	var jy := PageRand.hs(i, restless, 2) * 0.03
	var ink := PageTones.mix(T.paper, Color.BLACK, 0.6) if T.inv else PageTones.mix(T.ink, Color8(10, 6, 14), 0.4)
	# The tangle is re-scrawled a dozen times a second: record each scrawl once.
	var key := "s%d.%d" % [i, restless]
	var hit: Variant = env.cache.lookup(key)
	if hit == null:
		var rs := _sk.setup(pt, env, p.local(x + jx, y + jy), x + jx, y + jy, z, 1.0, 10007 + i * 41, restless)
		rs.tint_amt = 0.35
		pt.begin_record()
		for l in 4:
			var ctrl: Array = []
			var npts := 6 + (l % 2)
			for kk in npts:
				var a := float(kk) / npts * TAU + PageRand.hs(i, l, kk, restless) * 0.5 + l
				var r := 0.22 + PageRand.hash01(i, l * 7 + kk, restless) * 0.2
				ctrl.append_array([cos(a) * r, sin(a) * r * 0.9])
			var P := rs.pts(ctrl, true, 1.4)
			if l == 0:
				pt.fill(P, PageTones.alpha(ink, 0.55))
			pt.stroke(P, maxf(1.0, (1.2 + l * 0.3) * p.px), PageTones.alpha(ink, 0.9), true)
		var spikes: Array = []
		for kk in 9:
			var a := float(kk) / 9 * TAU + PageRand.hs(i, kk, restless) * 0.3
			spikes.append_array([cos(a) * 0.3, sin(a) * 0.28, cos(a) * (0.45 + PageRand.hash01(i, kk, restless + 1) * 0.12), sin(a) * (0.42 + PageRand.hash01(i, kk, restless + 2) * 0.12)])
		rs.marks(spikes, ink, 1.5, 0.85)
		hit = [pt.end_record(), rs.n]
		env.cache.store(key, hit)
	pt.replay(hit[0], Transform2D(0.0, Vector2(p.ox + (x + jx) * p.k, p.oy - (y + jy) * p.k)))
	# One red eye that follows the player.
	var s := _sk.setup(pt, env, p, x + jx, y + jy, z, 1.0, 10007 + i * 41, restless)
	s.tint_amt = 0.35
	s.n = hit[1]
	var pl := game.player
	var dx := pl.pos.x - x
	var dy := pl.pos.y + 0.45 - y
	var dl := Vector2(dx, dy).length()
	if dl == 0.0:
		dl = 1.0
	var ex := (dx / dl) * 0.05
	var ey := (dy / dl) * 0.05
	var blink := 0.3 if PageRand.noise1(game.time * 1.3 + i * 9, 3) > 0.85 else 1.0
	s.ellipse(ex, ey + 0.02, 0.12, 0.12 * blink, 0, T.rubric, 0.6)
	s.dot(ex + (dx / dl) * 0.04, ey + 0.02 + (dy / dl) * 0.04, 0.045 * blink, PageTones.mix(T.ink, Color.BLACK, 0.5))
	s.dot(ex - 0.04, ey + 0.06, 0.02 * blink, Color8(255, 240, 230, 230))

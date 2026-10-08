class_name PageQuaver
extends RefCounted
## Quaver on the page (quaver.ts): an eighth note come to life, in solid ink with a
## highlight crescent, a gold flag and a vermilion scarf. Every pose comes from the same
## simulation state the stage reads; only the flag and scarf keep a little spring state of
## their own so they trail behind with momentum.

const SEG := 0.1
const LINKS := 8


class Tail:
	var x := PackedFloat64Array()
	var y := PackedFloat64Array()
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()

	func _init() -> void:
		for a in [x, y, px, py]:
			a.resize(LINKS)


class Shape:
	var run := 0.0
	var phase := 0.0
	var sx := 1.0
	var sy := 1.0
	var bob := 0.0
	var twirl := 1.0
	var hop := 0.0
	var lean := 0.0
	var blink := 1.0
	var wide := 1.0


var _face := 1.0
var _flag_ang := -0.95
var _flag_vel := 0.0
var _tails: Array[Tail] = [Tail.new(), Tail.new()]
var _last_now := -1.0
var _anchor := Vector2(NAN, NAN)
## Game time of the last respawn (set by the page from events).
var respawn_at := -99.0
## Pose this frame: feet position (interpolated), visibility and fade.
var x := 0.0
var y := 0.0
var z := 0.0
var visible := true
var alpha := 1.0


func reset() -> void:
	_anchor = Vector2(NAN, NAN)
	_last_now = -1.0
	respawn_at = -99.0
	_face = 1.0


## Advances the flag and scarf springs and works out where Quaver is this frame.
func update(game: Sim, frame: Dictionary) -> void:
	var pl := game.player
	var a: float = frame.alpha
	x = pl.prev.x + (pl.pos.x - pl.prev.x) * a
	y = pl.prev.y + (pl.pos.y - pl.prev.y) * a
	z = pl.prev.z + (pl.pos.z - pl.prev.z) * a
	var now: float = frame.now
	var dt := 0.0 if _last_now < 0.0 else now - _last_now
	_last_now = now
	if dt > 0.25:
		# We were hidden; start fresh rather than whip the scarf across the page.
		_anchor = Vector2(NAN, NAN)
		dt = 0.0
	var gdt: float = frame.game_dt
	dt = minf(dt, 1.0 / 30.0) * (0.0 if frame.paused else maxf(0.35, 1.0 if gdt > 0.0 else 0.35))

	# Turn smoothly: the body flattens to nothing and back as it turns round.
	_face += (pl.facing - _face) * (1.0 - exp(-dt * 22.0))
	if absf(_face) < 0.02 and dt == 0.0:
		_face = pl.facing

	# The flag streams away from the motion and droops under its own weight.
	var fwd := pl.vel.x * pl.facing
	var dx := 1.1 - fwd * 0.85
	var dy := -1.5 - pl.vel.y * 0.32
	var target := atan2(dy, dx)
	if target > 1.05:
		target = -PI + 0.08 if target > 2.4 else 1.05
	target = maxf(-PI + 0.08, target)
	var diff := target - _flag_ang
	_flag_vel += (diff * 70.0 - _flag_vel * 10.0) * dt
	_flag_ang = clampf(_flag_ang + _flag_vel * dt, -PI + 0.05, 1.1)

	# Scarf tails: verlet chains hung from the knot, blown back by the motion.
	var knot := Vector2(x + pl.facing * 0.22, y + 0.7)
	if is_nan(_anchor.x) or knot.distance_to(_anchor) > 1.2:
		for ti in 2:
			var t := _tails[ti]
			for i in LINKS:
				t.x[i] = knot.x - pl.facing * i * SEG * 0.85
				t.px[i] = t.x[i]
				t.y[i] = knot.y - i * SEG * 0.5 - ti * 0.02
				t.py[i] = t.y[i]
	_anchor = knot
	if dt > 0.0:
		var wind := -pl.vel.x * 0.9
		var lift := -pl.vel.y * 0.25
		for ti in 2:
			var t := _tails[ti]
			t.x[0] = knot.x
			t.px[0] = knot.x
			t.y[0] = knot.y - ti * 0.03
			t.py[0] = t.y[0]
			var flutter := PageRand.noise1(now * 6.0 + ti * 3, 11 + ti) * (0.6 + absf(pl.vel.x) * 0.25)
			for i in range(1, LINKS):
				var vx := (t.x[i] - t.px[i]) * 0.86
				var vy := (t.y[i] - t.py[i]) * 0.86
				t.px[i] = t.x[i]
				t.py[i] = t.y[i]
				var fx := wind * 4.5 - pl.facing * 20.0 + flutter * 7.0 * (float(i) / LINKS)
				var fy := -8.0 + lift * 6.0 + flutter * 4.0
				t.x[i] += vx + fx * dt * dt
				t.y[i] += vy + fy * dt * dt
			var length := SEG * (1.0 if ti == 0 else 0.8)
			for it in 3:
				for i in range(1, LINKS):
					var ddx := t.x[i] - t.x[i - 1]
					var ddy := t.y[i] - t.y[i - 1]
					var d := sqrt(ddx * ddx + ddy * ddy)
					if d == 0.0:
						d = 1e-6
					var m := (d - length) / d
					t.x[i] -= ddx * m
					t.y[i] -= ddy * m
	var fin := game.time - game.finished_at if game.finished else -1.0
	alpha = maxf(0.0, 1.0 - (fin - 1.3) / 0.9) if fin > 1.3 else 1.0
	visible = pl.dead <= 0.0 and alpha > 0.0


## Squash, stretch, lean and other pose numbers for this frame.
func _shape(game: Sim) -> Shape:
	var pl := game.player
	var t := game.time
	var sh := Shape.new()
	sh.run = minf(1.0, absf(pl.vel.x) / Sim.RUN)
	sh.phase = (pl.walk / (Sim.STEP_EVERY * 2.0)) * TAU
	var sx := 1.0
	var sy := 1.0
	if pl.grounded:
		sh.bob = absf(sin(sh.phase)) * 0.05 * sh.run
		sy *= 1.0 + 0.045 * sin(sh.phase * 2.0) * sh.run
		sx *= 1.0 - 0.03 * sin(sh.phase * 2.0) * sh.run
		if sh.run < 0.1:
			var br := sin(t * 2.6)
			sy *= 1.0 + 0.028 * br
			sx *= 1.0 - 0.018 * br
	else:
		var v := pl.vel.y
		var st := minf(1.0, v / Sim.JUMP_V) * 0.16 if v > 0.0 else minf(1.0, -v / Sim.MAX_FALL) * 0.1
		sy *= 1.0 + st
		sx *= 1.0 - st * 0.7
	if pl.since_jump < 0.22:
		var j := 1.0 - pl.since_jump / 0.22
		sy *= 1.0 + 0.16 * j * j
		sx *= 1.0 - 0.12 * j * j
	if pl.since_land < 0.24 and pl.grounded:
		var imp := minf(1.0, pl.last_impact / 20.0)
		var u := pl.since_land / 0.24
		var sq := imp * sin((1.0 - u) * PI * 0.5) * (1.0 - u * 0.3)
		sy *= 1.0 - 0.34 * sq
		sx *= 1.0 + 0.3 * sq
	# Respawn: the ink gathers back into shape.
	var since_spawn := t - respawn_at
	if since_spawn >= 0.0 and since_spawn < 0.35:
		var u := since_spawn / 0.35
		var c1 := 1.9
		var e := 1.0 + (c1 + 1.0) * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)
		sx *= 0.4 + 0.6 * e
		sy *= 0.2 + 0.8 * e
	# Victory: a twirl and a hop.
	if game.finished:
		var f := game.time - game.finished_at
		if f < 1.0:
			sh.twirl = cos(f * TAU * 1.5)
			sh.hop = sin(minf(1.0, f / 0.7) * PI) * 0.4
	sh.lean = -sh.run * 0.14 * (1.0 if pl.grounded else 0.5) + (0.0 if pl.grounded else clampf(pl.vel.y * 0.006, -0.12, 0.12))
	# Blinks: a deterministic rhythm with the occasional double blink.
	var cyc := 3.6
	var bt := fmod(t + 0.7, cyc)
	var dbl := PageRand.hash01(floori((t + 0.7) / cyc), 3) < 0.3
	var blink := 1.0
	if bt < 0.12:
		blink = absf(bt - 0.06) / 0.06
	elif dbl and bt > 0.22 and bt < 0.34:
		blink = absf(bt - 0.28) / 0.06
	blink = maxf(0.12, blink)
	if pl.since_land < 0.15 and pl.last_impact > 12.0:
		blink = minf(blink, 0.35)
	sh.blink = blink
	sh.wide = 1.18 if not pl.grounded and pl.vel.y < -12.0 else 1.0
	sh.sx = sx
	sh.sy = sy
	return sh


func _local_xf(p: PageEnv.Proj, sh: Shape, face: float) -> Transform2D:
	var X := p.ox + x * p.k
	var Y := p.oy - (y + sh.hop) * p.k
	var base := Transform2D(Vector2(p.k * sh.sx * face, 0), Vector2(0, -p.k * sh.sy), Vector2(X, Y))
	return base * Transform2D(sh.lean, Vector2.ZERO)


func draw(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, frame: Dictionary) -> void:
	if not visible:
		return
	var T := env.tones
	var pl := game.player
	var sh := _shape(game)
	var k := p.k
	var face := (0.15 * (signf(_face) if _face != 0.0 else 1.0) if absf(_face) < 0.15 else _face) * sh.twirl
	var u := 1.0 / k
	var boil := p.boil
	var ink := T.ink
	var body := T.body
	var lw := 2.3 * p.px * u
	var amp := 0.5 * p.px * u

	_contact_shadow(pt, p, env, game)

	pt.galpha = alpha
	_draw_tails(pt, p, env, sh)
	var lxf := _local_xf(p, sh, face)
	# Parts that only boil are recorded in a pixel-scaled local space (y down) and replayed
	# through the live squash, lean and facing; `rq` is that replay transform, `bq` adds the
	# bob of the body.
	var rq := Transform2D(Vector2(sh.sx * face, 0), Vector2(0, sh.sy), Vector2(p.ox + x * k, p.oy - (y + sh.hop) * k)) * Transform2D(-sh.lean, Vector2.ZERO)
	var bq := rq * Transform2D(0.0, Vector2(0, -sh.bob * k))
	var qk := Transform2D(Vector2(k, 0), Vector2(0, -k), Vector2.ZERO)
	pt.set_xf(lxf)

	# Legs.
	var hip_y := 0.22
	var legs: Array[Vector2] = []
	for l in 2:
		var off := 0.0 if l == 0 else PI
		var fx: float
		var fy: float
		if pl.grounded:
			fx = sin(sh.phase + off) * 0.17 * sh.run
			fy = maxf(0.0, cos(sh.phase + off)) * 0.11 * sh.run
		elif pl.vel.y > 0.0:
			fx = 0.08 if l == 0 else -0.06
			fy = 0.09 + l * 0.03
		else:
			fx = 0.1 if l == 0 else -0.1
			fy = -0.02
		legs.append(Vector2((0.08 if l == 0 else -0.08) + fx, fy))
	for l in 2:
		var hx0 := 0.08 if l == 0 else -0.08
		var f := legs[l]
		var P := PageInk.curve_pts(PackedVector2Array([Vector2(hx0, hip_y + sh.bob), Vector2((hx0 + f.x) / 2.0 + 0.02, (hip_y + f.y) / 2.0 + sh.bob * 0.5), Vector2(f.x, f.y + 0.03)]), amp * 0.5, 300 + l, boil, 0.03)
		pt.ribbon(P, 0.075, 310 + l, body, 0.2)
	for l in 2:
		var f := legs[l]
		pt.fill(PageInk.ellipse_pts(f.x + 0.035, f.y + 0.03, 0.075, 0.042, 0.05, amp * 0.3, 320 + l, boil, 14), body)

	# Head: a tilted, glossy note head, with its highlight crescent.
	var hy0 := 0.47
	var hy := hy0 + sh.bob
	var key := "qh.%d" % boil
	var rec: Variant = env.cache.lookup(key)
	if rec == null:
		pt.begin_record()
		pt.set_xf(qk)
		var head := PageInk.ellipse_pts(0.0, hy0, 0.315, 0.25, 0.36, amp * 0.6, 330, boil, 40)
		pt.fill(head, body)
		pt.ring(head, lw, 331, ink)
		var cres := PagePath.new()
		cres.seg_px = 0.02
		cres.ellipse(-0.1, hy0 + 0.08, 0.15, 0.075, 0.55, PI * 0.95, PI * 1.9, true)
		cres.ellipse(-0.085, hy0 + 0.055, 0.12, 0.05, 0.55, PI * 1.85, PI * 1.0, false)
		pt.fill(cres.subpath(0), Color(220 / 255.0, 226 / 255.0, 1.0, 0.85) if T.inv else Color(1.0, 250 / 255.0, 236 / 255.0, 0.8))
		rec = pt.end_record()
		env.cache.store(key, rec)
		pt.galpha = alpha
	pt.replay(rec, bq)
	pt.set_xf(lxf)

	# Stem with the gold flag.
	var stem_x := 0.27
	var stem_y0 := hy + 0.02
	var stem_top_x := stem_x - sh.run * 0.05
	var stem_top_y := hy + 0.78
	var stem := PageInk.curve_pts(PackedVector2Array([Vector2(stem_x, stem_y0), Vector2(stem_x - sh.run * 0.02, (stem_y0 + stem_top_y) / 2.0), Vector2(stem_top_x, stem_top_y)]), amp * 0.5, 340, boil, 0.04)
	pt.ribbon(stem, 0.065, 341, body, 0.15)
	_draw_flag(pt, env, stem_top_x, stem_top_y, sh, frame)

	# Eyes: the whites are kept per blink height; the pupils look where Quaver goes.
	var ry := 0.088 * sh.blink * sh.wide
	var ekey := "qe.%d.%d" % [roundi(ry * 2000.0), roundi(sh.wide * 100.0)]
	var erec: Variant = env.cache.lookup(ekey)
	if erec == null:
		pt.begin_record()
		pt.set_xf(qk)
		for e in 2:
			var ex := -0.03 if e == 0 else 0.13
			var ey := hy0 + 0.05 + (0.0 if e == 0 else 0.03)
			var eye := PageInk.arc_pts(ex, ey, 0.066 * sh.wide, ry, 0.1, 0.0, TAU, false, 0.012)
			eye.resize(eye.size() - 1)
			pt.fill(eye, T.eye)
			pt.stroke(eye, 0.012, ink, true)
		erec = pt.end_record()
		env.cache.store(ekey, erec)
		pt.galpha = alpha
	pt.replay(erec, bq)
	pt.set_xf(lxf)
	if sh.blink > 0.4:
		var look_x := clampf(pl.vel.x * signf(face) * 0.25 + 0.4, -1.0, 1.0)
		var look_y := clampf(pl.vel.y * 0.06, -1.0, 1.0)
		var pupil := PageTones.rgb("#0b0d1c") if T.inv else PageTones.mix(T.ink, Color.BLACK, 0.4)
		for e in 2:
			var ex := -0.03 if e == 0 else 0.13
			var ey := hy + 0.05 + (0.0 if e == 0 else 0.03)
			var pcx := ex + look_x * 0.025
			var pcy := ey + look_y * 0.03 - 0.005
			pt.dot(pcx, pcy, 0.028, pupil)
			pt.dot(pcx - 0.01, pcy + 0.008, 0.009, PageTones.rgb("#fffaf0"))

	# The scarf wrapped round the stem just above the head, with a little knot.
	var skey := "qs.%d" % boil
	var srec: Variant = env.cache.lookup(skey)
	if srec == null:
		pt.begin_record()
		pt.set_xf(qk)
		var ky := hy0 + 0.22
		var sc := PagePath.new()
		sc.seg_px = 0.01
		sc.move_to(stem_x - 0.075, ky - 0.045)
		sc.quad_to(stem_x, ky - 0.065, stem_x + 0.075, ky - 0.04)
		sc.line_to(stem_x + 0.07, ky + 0.045)
		sc.quad_to(stem_x, ky + 0.03, stem_x - 0.07, ky + 0.05)
		sc.close()
		var scarf := sc.subpath(0)
		pt.fill(scarf, T.rubric)
		pt.stroke(scarf, 0.016, ink, true)
		var knot := PageInk.ellipse_pts(stem_x - 0.075, ky - 0.005, 0.045, 0.04, 0.3, amp * 0.2, 350, boil, 12)
		pt.fill(knot, PageTones.mix(T.rubric, T.ink, 0.15))
		pt.stroke(knot, 0.016, ink, true)
		srec = pt.end_record()
		env.cache.store(skey, srec)
		pt.galpha = alpha
	pt.replay(srec, bq)
	pt.reset_state()


func _draw_flag(pt: PagePainter, env: PageEnv, sx: float, sy: float, sh: Shape, frame: Dictionary) -> void:
	var T := env.tones
	var now: float = frame.now
	# An eighth-note flag: it leaves the stem top, swells, and sweeps back towards the stem
	# lower down. Its direction comes from the flag spring (facing frame, y up).
	var flutter := sin(now * 11.0) * (0.05 + sh.run * 0.1) + sin(now * 17.3) * 0.035 * sh.run
	var ang := _flag_ang + flutter
	var length := 0.46
	var ca := cos(ang)
	var sa := sin(ang)
	var nx := -sa
	var ny := ca
	var side := -1.0 if ca >= 0.0 else 1.0
	var wave := sin(now * 9.0) * 0.03 * (0.4 + sh.run)
	var tip_x := sx + ca * length + nx * wave
	var tip_y := sy + sa * length + ny * wave
	var bulge := 0.16
	var o1x := sx + ca * length * 0.45 - nx * bulge * side
	var o1y := sy + sa * length * 0.45 - ny * bulge * side
	var i1x := sx + ca * length * 0.55 - nx * bulge * 0.2 * side + nx * wave * 0.6
	var i1y := sy - 0.1 + sa * length * 0.55 - ny * bulge * 0.2 * side
	var f := PagePath.new()
	f.seg_px = 0.02
	f.move_to(sx, sy + 0.01)
	f.quad_to(o1x, o1y, tip_x, tip_y)
	f.quad_to(i1x, i1y, sx, sy - 0.2)
	f.close()
	var flag := f.subpath(0)
	pt.fill(flag, T.gold)
	pt.stroke(flag, 0.02, T.gold_dark, true)
	var hl := PagePath.new()
	hl.seg_px = 0.02
	hl.move_to(sx + ca * 0.04, sy + sa * 0.04)
	hl.quad_to(o1x * 0.92 + sx * 0.08, o1y * 0.92 + sy * 0.08, sx + (tip_x - sx) * 0.8, sy + (tip_y - sy) * 0.8)
	pt.stroke(hl.subpath(0), 0.022, PageTones.alpha(T.gold_light, 0.85))


func _draw_tails(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, sh: Shape) -> void:
	var T := env.tones
	var k := p.k
	for ti in [1, 0]:
		var t := _tails[ti]
		var ctrl := PackedVector2Array()
		for i in LINKS:
			ctrl.append(Vector2(p.ox + t.x[i] * k, p.oy - (t.y[i] + sh.hop) * k))
		var P := PageInk.curve_pts(ctrl, 0.4 * p.px, 370 + ti, p.boil, 3.0 * p.px)
		var n := P.size()
		if n < 2:
			continue
		# A tapering ribbon, wide at the knot, narrow at the tip, with a forked end.
		var L := PackedVector2Array()
		var R := PackedVector2Array()
		for i in n:
			var tv := P[mini(n - 1, i + 1)] - P[maxi(0, i - 1)]
			var l := tv.length()
			if l == 0.0:
				l = 1.0
			tv /= l
			var w := k * (0.06 - 0.035 * (float(i) / (n - 1))) * (1.0 + 0.25 * sin(i * 0.9 + ti))
			L.append(Vector2(P[i].x - tv.y * w, P[i].y + tv.x * w))
			R.append(Vector2(P[i].x + tv.y * w, P[i].y - tv.x * w))
		var e := P[n - 1]
		var outline := PackedVector2Array(L)
		outline.append(e - (L[n - 1] - e) * 0.2)
		for i in range(n - 1, -1, -1):
			outline.append(R[i])
		pt.fill(outline, T.rubric if ti == 0 else PageTones.mix(T.rubric, T.ink, 0.25))
		pt.stroke(outline, maxf(0.8, 1.1 * p.px), PageTones.alpha(T.ink, 0.8), true)


## A small hatched shadow on whatever Quaver stands over.
func _contact_shadow(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim) -> void:
	var lv := game.level
	var cx := floori(x)
	var gy := -1
	var yy := floori(y + 0.01)
	while yy >= maxi(0, floori(y) - 5):
		if cx >= 0 and cx < lv.w and yy - 1 >= 0 and yy - 1 < lv.h and lv.front[cx + lv.w * (yy - 1)] != Level.NO_DEPTH:
			gy = yy
			break
		yy -= 1
	if gy < 0:
		return
	var hgt := y - gy
	if hgt > 4.0:
		return
	var s := 1.0 - hgt / 4.0
	var e := PageInk.arc_pts(p.ox + x * p.k, p.oy - gy * p.k + 0.02 * p.k, p.k * 0.34 * (0.5 + 0.5 * s), p.k * 0.06 * (0.5 + 0.5 * s), 0, 0, TAU, false, 3.0)
	env.pat(pt, e, PageEnv.CROSS, 0.8 * s, p)


## Splits a polyline into dashes (ctx.setLineDash), the pattern restarting per polyline.
static func dash_poly(P: PackedVector2Array, closed: bool, on: float, off: float, offset: float) -> Array:
	var out: Array = []
	var pts := PackedVector2Array(P)
	if closed and pts.size() > 1:
		pts.append(pts[0])
	var period := on + off
	var phase := fposmod(offset, period)
	var cur := PackedVector2Array()
	var drawing := phase < on
	var left := (on - phase) if drawing else (period - phase)
	if drawing:
		cur.append(pts[0])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg_l := a.distance_to(b)
		var pos := 0.0
		while seg_l - pos > left:
			pos += left
			var q := a.lerp(b, pos / seg_l)
			if drawing:
				cur.append(q)
				out.append(cur)
				cur = PackedVector2Array()
				drawing = false
				left = off
			else:
				cur = PackedVector2Array([q])
				drawing = true
				left = on
		left -= seg_l - pos
		if drawing:
			cur.append(b)
	if drawing and cur.size() > 1:
		out.append(cur)
	return out


## Dotted outline and light accents over scenery when Quaver is behind it.
func ghost(pt: PagePainter, p: PageEnv.Proj, env: PageEnv, game: Sim, frame: Dictionary) -> void:
	if not visible:
		return
	var T := env.tones
	var sh := _shape(game)
	var face := 0.15 * (signf(_face) if _face != 0.0 else 1.0) if absf(_face) < 0.15 else _face
	var xf := _local_xf(p, sh, face)
	var hy := 0.47 + sh.bob
	var head := PageInk.arc_pts(0, hy, 0.315, 0.25, 0.36, 0, TAU, false, 0.02)
	head.resize(head.size() - 1)
	var polys: Array = [[xf * head, true],
		[xf * PackedVector2Array([Vector2(0.27, hy + 0.02), Vector2(0.27 - sh.run * 0.05, hy + 0.78)]), false],
		[xf * PackedVector2Array([Vector2(0.08, 0.22), Vector2(0.08, 0.02)]), false],
		[xf * PackedVector2Array([Vector2(-0.08, 0.22), Vector2(-0.08, 0.02)]), false]]
	var light := Color(240 / 255.0, 236 / 255.0, 220 / 255.0, 0.95) if T.inv else PageTones.alpha(PageTones.mix(T.paper, Color.WHITE, 0.5), 0.95)
	var now: float = frame.now
	var dash_list: Array = []
	for pc in polys:
		dash_list.append_array(dash_poly(pc[0], pc[1], 2.2 * p.px, 3.2 * p.px, -now * 12.0 * p.px))
	for d in dash_list:
		pt.stroke(d, maxf(2.0, 3.4 * p.px), PageTones.alpha(T.ink, 0.65))
	for d in dash_list:
		pt.stroke(d, maxf(1.2, 2.0 * p.px), light)
	pt.set_xf(xf)
	var kn := PageInk.arc_pts(0.24, hy + 0.15, 0.08, 0.045, -0.2, 0, TAU, false, 0.01)
	kn.resize(kn.size() - 1)
	pt.fill(kn, PageTones.alpha(T.rubric, 0.85))
	for e in 2:
		var el := PageInk.arc_pts(-0.03 if e == 0 else 0.13, hy + 0.05 + e * 0.03, 0.05, 0.065 * sh.blink, 0.1, 0, TAU, false, 0.01)
		el.resize(el.size() - 1)
		pt.fill(el, light)
	pt.reset_state()

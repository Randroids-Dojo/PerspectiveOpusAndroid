class_name PageFx
extends RefCounted
## One-off ink effects from game events, and ambient particles per palette (fx.ts).
## Event effects live in world units; ambient ones live in screen space with their own
## parallax so they drift at different depths.

enum { DROP, SPLAT, PUFF, MARK, FLECK, RING, RAYS, GATHER, SPARK, ARC, ACCENT, DASH }

const MAX_FX := 420


class Fx:
	var kind := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	## Age and lifetime in game seconds. Negative age is a delay.
	var age := 0.0
	var life := 1.0
	var size := 0.1
	var seed := 0
	var rot := 0.0
	var spin := 0.0
	var color := Color.BLACK
	var tx := 0.0
	var ty := 0.0
	var grav := 0.0
	var drag := 0.0


class Amb:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var age := 0.0
	var life := 1.0
	var size := 1.0
	var depth := 1.0
	var seed := 0
	var rot := 0.0
	var spin := 0.0
	var color := Color.BLACK


var _list: Array[Fx] = []
var _amb: Array[Amb] = []
var _amb_kind := "motes"
var T: PageTones
var _r := PageRand.Gen.new(99)
var _last_cam := Vector2(NAN, NAN)


func set_tones(t: PageTones) -> void:
	T = t
	_amb_kind = String(t.pal.ambient)
	_list.clear()
	_amb.clear()
	_last_cam = Vector2(NAN, NAN)


func clear() -> void:
	_list.clear()
	_amb.clear()
	_last_cam = Vector2(NAN, NAN)


## Adds an effect. Properties come in the web build's key order, so the shared generator
## is drawn from in the same sequence.
func _add(props: Dictionary) -> void:
	if _list.size() >= MAX_FX:
		_list.pop_front()
	var f := Fx.new()
	f.seed = floori(_r.next() * 1e6)
	f.rot = _r.next() * TAU
	f.color = T.ink
	for key in props:
		f.set(key, props[key])
	_list.append(f)


func handle(events: Array, game: Sim, reduce: bool) -> void:
	var pl := game.player
	var lv := game.level
	var r := _r
	var ink := T.ink
	var gold := T.gold
	var gold_l := T.gold_light
	var m := 0.5 if reduce else 1.0
	for e in events:
		match String(e.t):
			"jump":
				var i := 0
				while i < 6 * m:
					var a := PI + 0.25 + (i / 5.0) * (PI - 0.5)
					_add({"kind": PUFF, "x": pl.pos.x + cos(a) * 0.12, "y": pl.pos.y + 0.02, "vx": cos(a) * 2.2, "vy": -sin(a) * 0.9 + 0.3, "life": 0.32, "size": 0.12 + r.next() * 0.08, "drag": 6.0, "rot": a})
					i += 1
				for j in 3:
					_add({"kind": DROP, "x": pl.pos.x + PageRand.hs(j, 7) * 0.2, "y": pl.pos.y + 0.03, "vx": PageRand.hs(j, 8) * 1.5, "vy": 1.5 + r.next() * 1.5, "grav": 22.0, "life": 0.35, "size": 0.03 + r.next() * 0.02})
			"land":
				var imp := minf(1.0, float(e.impact) / 20.0)
				if imp < 0.15:
					continue
				var n := PageInk.jround((2.0 + 9.0 * imp) * m)
				for i in n:
					var sd := 1.0 if i % 2 else -1.0
					_add({"kind": DROP, "x": pl.pos.x + sd * (0.1 + r.next() * 0.2), "y": pl.pos.y + 0.03, "vx": sd * (1.0 + r.next() * 3.0 * imp), "vy": 1.0 + r.next() * 4.0 * imp, "grav": 26.0, "life": 0.45 + r.next() * 0.2, "size": 0.03 + r.next() * 0.035 * (0.5 + imp)})
				for sd in [-1.0, 1.0]:
					_add({"kind": DASH, "x": pl.pos.x + sd * 0.32, "y": pl.pos.y + 0.02, "vx": sd * 1.4 * imp, "life": 0.4, "size": 0.18 + 0.35 * imp, "rot": sd, "drag": 5.0})
			"step":
				if not pl.grounded:
					continue
				_add({"kind": MARK, "x": pl.pos.x - pl.facing * 0.12, "y": pl.pos.y + 0.015, "life": 0.4, "size": 0.1 + r.next() * 0.05, "rot": -pl.facing})
			"note":
				var id := int(e.id)
				if id >= lv.notes.size():
					continue
				var n: V3 = lv.notes[id].pos
				var i := 0
				while i < 18 * m:
					var a := r.next() * TAU
					var s := 1.5 + r.next() * 3.5
					_add({"kind": FLECK, "x": n.x, "y": n.y, "vx": cos(a) * s, "vy": sin(a) * s + 1.5, "grav": 6.0, "drag": 2.2, "life": 0.8 + r.next() * 0.6, "size": 0.05 + r.next() * 0.05, "spin": PageRand.hs(i, 3) * 12.0, "color": gold_l if r.next() < 0.3 else gold})
					i += 1
				_add({"kind": RAYS, "x": n.x, "y": n.y, "life": 0.5, "size": 0.9, "color": gold})
				_add({"kind": RING, "x": n.x, "y": n.y, "life": 0.55, "size": 0.9, "color": gold})
			"checkpoint":
				var id := int(e.id)
				if id >= lv.checkpoints.size():
					continue
				var c: V3 = lv.checkpoints[id].pos
				_add({"kind": RING, "x": c.x, "y": c.y + 0.9, "life": 0.8, "size": 1.6, "color": ink})
				_add({"kind": RING, "x": c.x, "y": c.y + 0.9, "life": 0.6, "size": 1.1, "color": gold, "age": -0.08})
				_add({"kind": RAYS, "x": c.x, "y": c.y + 1.05, "life": 0.6, "size": 1.1, "color": gold})
			"death":
				var pos: V3 = e.pos
				var x := pos.x
				var y := pos.y + 0.45
				_add({"kind": SPLAT, "x": x, "y": y, "life": 1.5, "size": 0.62, "color": ink})
				for i in 4:
					var a := r.next() * TAU
					var d := 0.6 + r.next() * 0.6
					_add({"kind": SPLAT, "x": x + cos(a) * d, "y": y + sin(a) * d, "life": 1.4, "size": 0.08 + r.next() * 0.1, "color": ink, "age": -0.05 - r.next() * 0.1})
				var i := 0
				while i < 26 * m:
					var a := r.next() * TAU
					var s := 2.0 + r.next() * 6.0
					_add({"kind": DROP, "x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s + 2.5, "grav": 18.0, "drag": 0.8, "life": 0.7 + r.next() * 0.4, "size": 0.04 + r.next() * 0.06})
					i += 1
				# The ink gathers again at the respawn point just before Quaver returns.
				var rp := game.respawn_pos
				i = 0
				while i < 16 * m:
					var a := r.next() * TAU
					var d := 1.0 + r.next() * 1.4
					_add({"kind": GATHER, "x": rp.x + cos(a) * d, "y": rp.y + 0.4 + sin(a) * d * 0.8, "tx": rp.x, "ty": rp.y + 0.4, "age": -(0.5 + r.next() * 0.12), "life": 0.38 + r.next() * 0.06, "size": 0.04 + r.next() * 0.05})
					i += 1
			"respawn":
				_add({"kind": RING, "x": pl.pos.x, "y": pl.pos.y + 0.4, "life": 0.45, "size": 0.9, "color": ink})
				for i in 6:
					var a := float(i) / 6 * TAU
					_add({"kind": DROP, "x": pl.pos.x + cos(a) * 0.3, "y": pl.pos.y + 0.4 + sin(a) * 0.3, "vx": cos(a) * 1.5, "vy": sin(a) * 1.5, "grav": 4.0, "drag": 4.0, "life": 0.3, "size": 0.03})
			"bounce":
				var id := int(e.id)
				if id >= lv.drums.size():
					continue
				var d: V3 = lv.drums[id].pos
				for i in 3:
					_add({"kind": ARC, "x": d.x + 0.5, "y": d.y + 0.8, "life": 0.5, "size": 0.5 + i * 0.25, "age": -i * 0.06})
				var i := 0
				while i < 6 * m:
					_add({"kind": DROP, "x": d.x + 0.5 + PageRand.hs(i, 4) * 0.35, "y": d.y + 0.75, "vx": PageRand.hs(i, 5) * 2.0, "vy": 2.0 + r.next() * 3.0, "grav": 20.0, "life": 0.45, "size": 0.03 + r.next() * 0.03})
					i += 1
			"key":
				var id := int(e.id)
				if id >= lv.keys.size():
					continue
				var k: Dictionary = lv.keys[id]
				var kp: V3 = k.pos
				var col: Color = T.groups[k.group % T.groups.size()]
				for i in 3:
					_add({"kind": ACCENT, "x": kp.x + (k.width * (i + 0.5)) / 3.0, "y": kp.y + 0.35, "vy": 0.9, "life": 0.7, "size": 0.16, "color": col, "age": -i * 0.05})
			"gate":
				for g in lv.gates:
					if g.group != int(e.group):
						continue
					var i := 0
					while i < 10 * m:
						_add({"kind": SPARK, "x": g.min.x + r.next() * (g.max.x - g.min.x), "y": g.min.y + r.next() * (g.max.y - g.min.y), "vy": 0.4 + r.next() * 0.6, "life": 0.6 + r.next() * 0.4, "size": 0.08 + r.next() * 0.06, "color": gold_l, "age": -r.next() * 0.2})
						i += 1
			"exit":
				var x := lv.exit_pos
				_add({"kind": RAYS, "x": x.x, "y": x.y + 1.6, "life": 1.2, "size": 2.6, "color": gold})
				_add({"kind": RING, "x": x.x, "y": x.y + 1.6, "life": 1.0, "size": 2.4, "color": gold})
				var i := 0
				while i < 30 * m:
					var a := r.next() * TAU
					var s := 1.0 + r.next() * 4.0
					_add({"kind": FLECK, "x": x.x + PageRand.hs(i, 9) * 0.6, "y": x.y + 1.0 + r.next() * 2.0, "vx": cos(a) * s, "vy": sin(a) * s + 1.0, "grav": 2.0, "drag": 1.5, "life": 1.2 + r.next() * 0.8, "size": 0.05 + r.next() * 0.06, "spin": PageRand.hs(i, 3) * 10.0, "color": gold_l if r.next() < 0.4 else gold})
					i += 1
			"bonk":
				_add({"kind": RAYS, "x": pl.pos.x, "y": pl.pos.y + 1.0, "life": 0.28, "size": 0.45, "color": ink})


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var keep: Array[Fx] = []
	for f in _list:
		f.age += dt
		if f.age > f.life:
			continue
		if f.age > 0.0:
			f.vy -= f.grav * dt
			if f.drag != 0.0:
				var d := exp(-f.drag * dt)
				f.vx *= d
				f.vy *= d
			f.x += f.vx * dt
			f.y += f.vy * dt
			f.rot += f.spin * dt
		keep.append(f)
	_list = keep


## Draws the event effects in world space.
func draw(pt: PagePainter, p: PageEnv.Proj) -> void:
	var k := p.k
	for f in _list:
		if f.age < 0.0 and f.kind != GATHER:
			continue
		var u := maxf(0.0, f.age / f.life)
		var X := p.ox + f.x * k
		var Y := p.oy - f.y * k
		match f.kind:
			DROP:
				var sp := Vector2(f.vx, f.vy).length()
				var r := f.size * k * (1.0 - u * 0.5)
				var stretch := minf(2.5, 1.0 + sp * 0.08)
				var xf := Transform2D(atan2(-f.vy, f.vx), Vector2(X, Y)) * Transform2D(Vector2(stretch, 0), Vector2(0, 1.0 / sqrt(stretch)), Vector2.ZERO)
				pt.fill(xf * PageInk.circle_pts(0, 0, maxf(0.6, r), 2.0), PageTones.alpha(f.color, 1.0 - u * u))
			SPLAT:
				var grow := minf(1.0, f.age / 0.12)
				var r := f.size * k * (0.4 + 0.6 * grow)
				var c := PageTones.alpha(f.color, 0.92 if u < 0.6 else 0.92 * (1.0 - (u - 0.6) / 0.4))
				pt.fill(PageInk.blob_pts(X, Y, r, 0.35, f.seed, 0, 28), c)
				if f.size > 0.3:
					for i in 9:
						var a := PageRand.hash01(f.seed, i) * TAU
						var length := r * (1.3 + PageRand.hash01(f.seed, i, 2) * 0.8)
						var w := r * 0.12
						pt.fill(PackedVector2Array([Vector2(X + cos(a + 0.15) * r * 0.8, Y + sin(a + 0.15) * r * 0.8), Vector2(X + cos(a) * length, Y + sin(a) * length), Vector2(X + cos(a - 0.15) * r * 0.8, Y + sin(a - 0.15) * r * 0.8)]), c)
						pt.dot(X + cos(a) * (length + w * 1.5), Y + sin(a) * (length + w * 1.5), w, c)
			PUFF:
				var length := f.size * k * (0.5 + u)
				var a := f.rot
				var pa := PagePath.new()
				pa.move_to(X, Y)
				pa.quad_to(X + cos(a) * length * 0.6, Y + length * 0.1, X + cos(a) * length, Y - sin(a) * length * 0.3)
				pt.stroke(pa.subpath(0), maxf(0.8, 1.4 * p.px * (1.0 - u)), PageTones.alpha(T.ink, 0.7 * (1.0 - u)))
			MARK, DASH:
				var length := f.size * k
				var pa := PagePath.new()
				pa.move_to(X - length * 0.5, Y)
				pa.quad_to(X, Y - length * 0.08 * f.rot, X + length * 0.5, Y)
				pt.stroke(pa.subpath(0), maxf(0.8, (1.8 if f.kind == DASH else 1.2) * p.px), PageTones.alpha(T.ink, (0.75 if f.kind == DASH else 0.45) * (1.0 - u)))
			FLECK:
				var s := f.size * k
				var sx := cos(f.rot)
				var xf := Transform2D(Vector2(maxf(0.15, absf(sx)), 0), Vector2(0, 1), Vector2(X, Y)) * Transform2D(f.rot * 0.3, Vector2.ZERO)
				pt.fill(xf * PackedVector2Array([Vector2(0, -s), Vector2(s * 0.6, 0), Vector2(0, s), Vector2(-s * 0.6, 0)]), PageTones.alpha(T.gold_light if absf(sx) > 0.85 else f.color, 1.0 - u * u))
			RING:
				var r := f.size * k * (0.25 + 0.75 * sqrt(u))
				var P := PackedVector2Array()
				for i in 40:
					var a := float(i) / 40 * TAU
					var rr := r * (1.0 + 0.05 * sin(a * 5.0 + f.seed) + 0.03 * sin(a * 9.0 + f.seed * 2))
					P.append(Vector2(X + cos(a) * rr, Y + sin(a) * rr))
				pt.stroke(P, maxf(1.0, 2.6 * p.px * (1.0 - u)), PageTones.alpha(f.color, 0.85 * (1.0 - u)), true)
			RAYS:
				var r0 := f.size * k * (0.2 + 0.5 * u)
				var r1 := f.size * k * (0.45 + 0.75 * sqrt(u))
				var c := PageTones.alpha(f.color, 0.85 * (1.0 - u))
				var w := maxf(1.0, 1.8 * p.px)
				for i in 14:
					var a := float(i) / 14 * TAU + f.seed
					var j := 0.7 + 0.5 * PageRand.hash01(f.seed, i)
					pt.seg(X + cos(a) * r0, Y + sin(a) * r0, X + cos(a) * r1 * j, Y + sin(a) * r1 * j, w, c)
			GATHER:
				if f.age < 0.0:
					if f.age > -0.25:
						pt.dot(X, Y, maxf(0.6, f.size * k * 0.6), PageTones.alpha(T.ink, (0.25 + f.age) * 2.0))
					continue
				var e := u * u * (3.0 - 2.0 * u)
				var bend := sin(u * PI) * 0.5
				var gx := f.x + (f.tx - f.x) * e + (f.ty - f.y) * bend * 0.3
				var gy := f.y + (f.ty - f.y) * e - (f.tx - f.x) * bend * 0.3
				pt.dot(p.ox + gx * k, p.oy - gy * k, maxf(0.6, f.size * k * (1.0 - e * 0.4)), PageTones.alpha(T.ink, 0.9))
			SPARK:
				for q in PageInk.glint_quads(X, Y, f.size * k * sin(u * PI), f.rot):
					pt.fill(q, PageTones.alpha(f.color, 0.9))
			ARC:
				var r := f.size * k * (0.6 + 0.8 * u)
				pt.stroke(PageInk.arc_pts(X, Y, r, r, 0, -0.82 * PI, -0.18 * PI), maxf(1.0, 2.0 * p.px * (1.0 - u)), PageTones.alpha(T.ink, 0.75 * (1.0 - u)))
			ACCENT:
				var s := f.size * k
				pt.stroke(PackedVector2Array([Vector2(X - s * 0.6, Y - s * 0.4), Vector2(X + s * 0.6, Y), Vector2(X - s * 0.6, Y + s * 0.4)]), maxf(1.0, 2.0 * p.px), PageTones.alpha(f.color, 0.9 * (1.0 - u)))


# ---------------------------------------------------------------- ambient

## Updates and draws ambient particles in screen space (target pixels).
func ambient(pt: PagePainter, dt: float, cam_x: float, cam_y: float, ppu: float, W: float, H: float, dpr: float, quality: String, now: float) -> void:
	var want := 10 if quality == "low" else (20 if quality == "medium" else 30)
	var kind := _amb_kind
	var count := PageInk.jround(want * 0.3) if kind == "mist" else want
	var ppd := ppu * dpr
	if not is_nan(_last_cam.x):
		var dx := (cam_x - _last_cam.x) * ppd
		var dy := (cam_y - _last_cam.y) * ppd
		if absf(dx) + absf(dy) < W:
			for a in _amb:
				a.x -= dx * a.depth
				a.y += dy * a.depth
	_last_cam = Vector2(cam_x, cam_y)
	while _amb.size() < count:
		_amb.append(_spawn(kind, W, H, dpr, _amb.size() < count * 0.5 or _amb.is_empty()))
	var margin := 60.0 * dpr
	for i in _amb.size():
		var a := _amb[i]
		a.age += dt
		var sway := PageRand.noise1(now * 0.6 + a.seed * 0.01, a.seed & 1023)
		a.x += (a.vx + sway * 18.0 * dpr) * dt
		a.y += a.vy * dt
		a.rot += a.spin * dt
		if a.age > a.life or a.x < -margin or a.x > W + margin or a.y < -margin or a.y > H + margin:
			_amb[i] = _spawn(kind, W, H, dpr, false)
	for a in _amb:
		var u := a.age / a.life
		var fade := minf(1.0, minf(u * 5.0, (1.0 - u) * 4.0))
		if fade <= 0.0:
			continue
		match kind:
			"motes":
				pt.dot(a.x, a.y, a.size, PageTones.alpha(a.color, fade * 0.65))
			"petals", "leaves":
				var s := a.size
				var sx := cos(a.rot)
				var xf := Transform2D(a.rot * 0.4, Vector2(a.x, a.y)) * Transform2D(Vector2(maxf(0.2, absf(sx)), 0), Vector2(0, 1), Vector2.ZERO)
				pt.fill(xf * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2.ZERO) * _leaf_shape(), PageTones.alpha(a.color, fade * 0.9))
				pt.stroke(xf * PackedVector2Array([Vector2(-s * 0.8, 0), Vector2(s * 0.8, 0)]), maxf(0.5, 0.6 * dpr), PageTones.alpha(T.ink, fade * 0.5))
			"fireflies":
				var blink := 0.5 + 0.5 * sin(now * (1.5 + (a.seed % 7) * 0.2) + a.seed)
				var b := blink * blink
				pt.dot(a.x, a.y, a.size * (0.6 + 0.4 * b), PageTones.alpha(a.color, fade * (0.35 + 0.65 * b)))
				if b > 0.5:
					var c := PageTones.alpha(a.color, fade * (b - 0.5) * 1.2)
					for kk in 6:
						var ang := float(kk) / 6 * TAU + a.rot
						pt.seg(a.x + cos(ang) * a.size * 1.8, a.y + sin(ang) * a.size * 1.8, a.x + cos(ang) * a.size * 3.2, a.y + sin(ang) * a.size * 3.2, maxf(0.6, 0.7 * dpr), c)
			"sparks":
				pt.seg(a.x, a.y, a.x - a.vx * 0.04, a.y - a.vy * 0.04, maxf(0.8, a.size), PageTones.alpha(a.color, fade * 0.9))
			"embers":
				var fl := 0.6 + 0.4 * sin(now * 9.0 + a.seed)
				pt.dot(a.x, a.y, a.size * fl, PageTones.alpha(a.color, fade * 0.85))
			"mist":
				for l in 4:
					var ox := sin(a.seed + l * 2.1) * a.size * 4.0
					var oy := cos(a.seed * 0.7 + l) * a.size * 0.5
					pt.ellipse_dot(a.x + ox, a.y + oy, a.size * (7.0 - l * 1.2), a.size * (1.1 - l * 0.15), PageTones.alpha(a.color, fade * 0.07))


## A unit almond (two quadratic arcs from (-1, 0) to (1, 0) through (0, -0.55) and
## (0, 0.55)), made once.
static var _leaf: PackedVector2Array


static func _leaf_shape() -> PackedVector2Array:
	if _leaf.is_empty():
		var pa := PagePath.new()
		pa.seg_px = 0.25
		pa.move_to(-1, 0)
		pa.quad_to(0, -0.55, 1, 0)
		pa.quad_to(0, 0.55, -1, 0)
		_leaf = pa.subpath(0)
		_leaf.resize(_leaf.size() - 1)
	return _leaf


func _spawn(kind: String, W: float, H: float, dpr: float, anywhere: bool) -> Amb:
	var r := _r
	var a := Amb.new()
	a.depth = 0.5 + r.next() * 0.7
	a.x = r.next() * W
	a.y = r.next() * H
	a.age = r.next() * 3.0 if anywhere else 0.0
	a.life = 4.0 + r.next() * 5.0
	a.seed = floori(r.next() * 1e6)
	a.rot = r.next() * TAU
	a.color = T.ink
	match kind:
		"motes":
			a.vx = (r.next() - 0.5) * 10.0 * dpr
			a.vy = -(3.0 + r.next() * 8.0) * dpr
			a.size = (0.7 + r.next() * 1.3) * dpr * a.depth
			a.color = T.gold if r.next() < 0.4 else PageTones.mix(T.ink, T.paper, 0.35)
		"petals":
			a.vx = (20.0 + r.next() * 25.0) * dpr
			a.vy = (14.0 + r.next() * 20.0) * dpr
			a.size = (3.0 + r.next() * 3.0) * dpr * a.depth
			a.spin = (r.next() - 0.5) * 6.0
			a.color = PageTones.mix(PageTones.rgb("#e8a6b0"), T.paper, 0.2)
			if not anywhere:
				a.x = -20.0 * dpr
				a.y = r.next() * H * 0.8
		"leaves":
			var cols := [PageTones.rgb("#c4602a"), PageTones.rgb("#d8902e"), T.rubric, PageTones.rgb("#a8462a")]
			a.vx = (10.0 + r.next() * 30.0) * dpr
			a.vy = (22.0 + r.next() * 28.0) * dpr
			a.size = (4.0 + r.next() * 4.0) * dpr * a.depth
			a.spin = (r.next() - 0.5) * 7.0
			a.color = PageTones.mix(cols[floori(r.next() * cols.size())], T.paper, 0.1 + (1.0 - a.depth) * 0.3)
			if not anywhere:
				a.x = r.next() * W * 1.2 - W * 0.2
				a.y = -20.0 * dpr
			a.life = 6.0 + r.next() * 6.0
		"fireflies":
			a.vx = (r.next() - 0.5) * 16.0 * dpr
			a.vy = (r.next() - 0.5) * 10.0 * dpr
			a.size = (1.4 + r.next() * 1.4) * dpr * a.depth
			a.color = PageTones.mix(T.ink, Color.WHITE, 0.4) if r.next() < 0.5 else PageTones.mix(T.gold, PageTones.rgb("#fff4c0"), 0.4)
			a.y = H * (0.25 + r.next() * 0.7)
			a.life = 5.0 + r.next() * 6.0
		"sparks":
			a.vx = (r.next() - 0.5) * 60.0 * dpr
			a.vy = (40.0 + r.next() * 80.0) * dpr
			a.size = (0.9 + r.next() * 1.2) * dpr
			a.color = T.gold_light if r.next() < 0.5 else PageTones.mix(T.gold, PageTones.rgb("#ff8a3a"), 0.4)
			a.life = 0.8 + r.next() * 1.4
			if not anywhere:
				a.y = -10.0 * dpr + r.next() * H * 0.3
		"embers":
			a.vx = (r.next() - 0.5) * 14.0 * dpr
			a.vy = -(10.0 + r.next() * 22.0) * dpr
			a.size = (1.0 + r.next() * 1.6) * dpr * a.depth
			a.color = PageTones.mix(PageTones.rgb("#ff9a4a"), T.gold, r.next() * 0.6)
			if not anywhere:
				a.y = H + 10.0 * dpr
			a.life = 5.0 + r.next() * 4.0
		"mist":
			a.vx = (6.0 + r.next() * 10.0) * dpr * (-1.0 if r.next() < 0.5 else 1.0)
			a.vy = 0.0
			a.size = (10.0 + r.next() * 14.0) * dpr
			a.y = H * (0.45 + r.next() * 0.5)
			a.color = PageTones.mix(T.paper, PageTones.rgb("#8090c0"), 0.5) if T.inv else PageTones.mix(T.paper, Color.WHITE, 0.5)
			a.life = 9.0 + r.next() * 8.0
	return a

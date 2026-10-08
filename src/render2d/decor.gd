class_name PageDecor
extends RefCounted
## The 19 kinds of decor as ink illustrations (decor.ts), each varied by its seed. Static
## parts are baked into the cached page; moving parts (a turning gear, a waving banner,
## flames, glows, a swaying bell) are drawn live every frame.

enum { STATIC, LIVE, ALL }

const FLOWER_COLS := ["#b2362b", "#d6a33a", "#4f6fbf", "#f4eee2", "#c0609a", "#e07a3a"]

static var _sk := PageSketch.new()


## Drops the shared sketch, which holds on to the last page's environment.
static func release_shared() -> void:
	_sk = PageSketch.new()
## Gears are recorded without their sheen at rotation zero and turned when replayed:
## 0 draws the whole gear, 1 only the turning parts at rotation zero, 2 only the sheen.
static var gear_part := 0


static func draw(painter: PagePainter, env: PageEnv, p: PageEnv.Proj, di: PageWorld.DecorInfo, boil: int, mode: int) -> void:
	if mode == LIVE and not di.live:
		return
	var s := _sk.setup(painter, env, p, di.px, di.py, di.z, di.scale, di.seed, boil)
	var r := PageRand.Gen.new(di.seed, true)
	match di.kind:
		"tree": _tree(s, r)
		"pine": _pine(s, r)
		"lamp": _lamp(s, r, mode)
		"pillar": _pillar(s, r)
		"banner": _banner(s, r, mode)
		"flowers": _flowers(s, r)
		"grass": _grass(s, r)
		"rock": _rock(s, r)
		"reeds": _reeds(s, r)
		"lantern": _lantern(s, r, mode)
		"pipes": _pipes(s, r)
		"gear": _gear(s, r, mode)
		"crystals": _crystals(s, r)
		"statue": _statue(s, r)
		"curtain": _curtain(s, r)
		"arch": _arch(s, r)
		"mushroom": _mushroom(s, r)
		"bell": _bell(s, r, mode)
		"candles": _candles(s, r, mode)


static func _static(m: int) -> bool:
	return m != LIVE


static func _live(m: int) -> bool:
	return m != STATIC


static func _rgb(h: String) -> Color:
	return PageTones.rgb(h)


static func _mix(a: Color, b: Color, t: float) -> Color:
	return PageTones.mix(a, b, t)


## Scalloped foliage outline around a centre, as local control points.
static func scallop(cx: float, cy: float, rx: float, ry: float, lobes: int, seed: int, depth: float = 0.16) -> Array:
	var out: Array = []
	var n := lobes * 4
	var ph := PageRand.hash01(seed, 3) * PI
	for i in n:
		var a := float(i) / n * TAU
		var lobe := sqrt(absf(sin((a * lobes) / 2.0 + ph)))
		var kk := 1.0 - depth + depth * lobe + PageRand.hs(seed, i, 4) * 0.04
		out.append(cx + cos(a) * rx * kk)
		out.append(cy + sin(a) * ry * kk)
	return out


## A gear's hub height (local units) and its rotation at a game time.
static func gear_turn(di: PageWorld.DecorInfo, time: float) -> Vector2:
	var r := PageRand.Gen.new(di.seed, true)
	var R := 1.15 + r.next() * 0.25
	r.next()
	var dir := -1.0 if r.next() < 0.5 else 1.0
	return Vector2(R * 0.92, time * 0.35 * dir + r.next() * 6)


# ---------------------------------------------------------------- kinds

static func _tree(s: PageSketch, r: PageRand.Gen) -> void:
	var leaf := s.T.mat_color("leaf")
	var wood := s.T.mat_color("wood")
	var R := 0.95 + r.next() * 0.35
	var th := 1.35 + r.next() * 0.45
	var lean := (r.next() - 0.5) * 0.25
	var cx := lean
	var cy := th + R * 0.72
	s.shape([-0.17, 0, -0.1, 0.25, -0.08, th * 0.7, -0.07 + lean * 0.6, th + 0.2, 0.07 + lean * 0.6, th + 0.2, 0.09, th * 0.7, 0.11, 0.25, 0.2, 0], s.col(wood), 1)
	s.line([0, th * 0.75, -0.35 + lean, th + 0.45, -0.55 + lean, th + 0.7], 0.8)
	s.line([0.03, th * 0.85, 0.35 + lean, th + 0.55], 0.7)
	s.marks([-0.03, 0.15, -0.02, th * 0.6, 0.04, 0.3, 0.03, th * 0.5], s.darker(wood), 0.9, 0.6)
	var crown := scallop(cx, cy, R, R * 0.86, 7 + floori(r.next() * 3), s.seed)
	s.shape(crown, s.col(leaf), 1.05)
	s.clip(crown, func() -> void:
		s.blot(cx + R * 0.4, cy - R * 0.55, R * 0.9, R * 0.6, PageEnv.HATCH, 0.32)
		s.blot(cx + R * 0.55, cy - R * 0.75, R * 0.55, R * 0.35, PageEnv.CROSS, 0.25))
	var segs: Array = []
	for i in 6:
		var a := r.next() * TAU
		var d := r.next() * 0.6 * R
		var ux := cx + cos(a) * d
		var uy := cy + sin(a) * d * 0.8
		s.line([ux - 0.18, uy + 0.02, ux, uy - 0.07, ux + 0.18, uy + 0.03], 0.55, null, 0.6)
	for i in 4:
		var ux := cx - R * 0.45 + r.next() * R * 0.4
		var uy := cy + R * 0.3 + r.next() * R * 0.3
		segs.append_array([ux, uy, ux + 0.14, uy + 0.05])
	s.marks(segs, s.lighter(leaf, 0.55), 1.4, 0.7)


static func _pine(s: PageSketch, r: PageRand.Gen) -> void:
	var leaf := _mix(s.T.mat_color("leaf", true), s.T.mat_color("leaf"), 0.3)
	s.shape([-0.1, 0, -0.08, 0.7, 0.08, 0.7, 0.11, 0], s.col(s.T.mat_color("wood")), 0.9)
	for i in 4:
		var v0 := 0.45 + i * 0.78
		var w := 1.05 - i * 0.2 + r.next() * 0.06
		var top := v0 + 1.45 - i * 0.1
		var teeth := 4 - floori(i / 2.0)
		var ctrl: Array = [0 + PageRand.hs(s.seed, i) * 0.03, top]
		ctrl.append_array([w * 0.45, v0 + 0.55, w, v0])
		for t in range(teeth - 1, 0, -1):
			var u := -w + (2 * w * t) / teeth
			ctrl.append_array([u + w / teeth / 2.0, v0 + 0.06, u, v0 - 0.04])
		ctrl.append_array([-w, v0, -w * 0.45, v0 + 0.55])
		s.shape(ctrl, s.col(leaf), 1, 0.95, true, 1.0, true, true)
		s.clip(ctrl, func() -> void: s.blot(w * 0.6, v0 + 0.3, w * 0.75, 0.9, PageEnv.HATCH, 0.4), true)


static func _lamp(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	var T := s.T
	var iron := _mix(T.ink, T.paper, 0.2) if T.inv else _mix(T.ink, _rgb("#3a3430"), 0.3)
	var glass := _mix(T.gold_light, _rgb("#fff6d8"), 0.5)
	var hgt := 2.05 + r.next() * 0.2
	if _static(mode):
		s.shape([-0.2, 0, -0.14, 0.22, -0.05, 0.32, -0.04, hgt, 0.04, hgt, 0.05, 0.32, 0.14, 0.22, 0.2, 0], s.col(iron), 0.9)
		s.seg(-0.09, 0.62, 0.09, 0.62, 0.7)
		s.seg(-0.08, hgt - 0.35, 0.08, hgt - 0.35, 0.7)
		s.shape([-0.17, hgt, -0.22, hgt + 0.38, 0.22, hgt + 0.38, 0.17, hgt], s.col(glass), 0.8)
		s.seg(0, hgt, 0, hgt + 0.38, 0.5)
		s.shape([-0.3, hgt + 0.38, 0, hgt + 0.58, 0.3, hgt + 0.38], s.col(iron), 0.8)
		s.dot(0, hgt + 0.64, 0.04, s.ink_color())
	if _live(mode):
		var t := s.env.time
		var f := 0.75 + 0.25 * PageRand.noise1(t * 3 + s.seed, 5)
		s.dot(0, hgt + 0.19, 0.09 * f, _mix(T.gold, _rgb("#fff1c0"), 0.6), 0.95)
		s.rays(0, hgt + 0.19, 0.3, 0.55 + 0.12 * f, 12, T.gold, 0.45 * f, t * 0.2, 1.1)


static func _pillar(s: PageSketch, r: PageRand.Gen) -> void:
	var marble := s.T.mat_color("marble")
	var fill := s.col(marble)
	var broken := r.next() < 0.3
	s.pshape([-0.55, 0, -0.55, 0.13, 0.55, 0.13, 0.55, 0], fill, 0.9)
	s.pshape([-0.45, 0.13, -0.45, 0.26, 0.45, 0.26, 0.45, 0.13], fill, 0.8)
	var top := 1.5 + r.next() * 0.7 if broken else 2.8
	var shaft: Array = [-0.31, 0.26, -0.29, top - 0.1, -0.15, top + 0.08, -0.02, top - 0.06, 0.12, top + 0.12, 0.28, top - 0.05, 0.31, 0.26] if broken else [-0.32, 0.26, -0.28, top, 0.28, top, 0.32, 0.26]
	s.shape(shaft, fill, 1, 0.95, true, 1.0, true, true)
	s.clip(shaft, func() -> void: s.blot(0.38, top / 2, 0.22, top, PageEnv.HATCH, 0.55), true)
	var fl: Array = []
	for i in range(-1, 2):
		fl.append_array([i * 0.13, 0.32, i * 0.12, top - 0.12])
	s.marks(fl, s.darker(marble, 0.35), 0.9, 0.65)
	if not broken:
		s.shape([-0.42, top, -0.46, top + 0.16, 0.46, top + 0.16, 0.42, top], fill, 0.8)
		for sd in [-1.0, 1.0]:
			var cx: float = sd * 0.42
			s.line([cx, top + 0.08, cx + sd * 0.1, top + 0.16, cx + sd * 0.13, top + 0.06, cx + sd * 0.05, top + 0.02, cx + sd * 0.03, top + 0.08], 0.6)
		s.pshape([-0.52, top + 0.16, -0.52, top + 0.28, 0.52, top + 0.28, 0.52, top + 0.16], fill, 0.8)
	else:
		s.shape([0.45, 0, 0.42, 0.22, 0.95, 0.24, 0.98, 0.02], fill, 0.8)


static func _banner(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	var T := s.T
	var top := 1.5
	if _static(mode):
		s.seg(-0.62, top, 0.62, top, 1)
		s.dot(-0.66, top, 0.05, s.col(T.gold))
		s.dot(0.66, top, 0.05, s.col(T.gold))
	if _live(mode):
		var t := s.env.time
		var ph := r.next() * 6
		var wave := func(v: float) -> float: return sin(t * 1.9 + ph - v * 2.4) * 0.07 * (top - v) * 0.7
		var bottom := -0.6
		var ctrl: Array = []
		var steps := 6
		for i in steps + 1:
			var v := top - ((top - bottom) * i) / steps
			ctrl.append_array([-0.5 + wave.call(v), v])
		ctrl.append_array([0 + wave.call(bottom + 0.3), bottom + 0.3])
		for i in range(steps, -1, -1):
			var v := top - ((top - bottom) * i) / steps
			ctrl.append_array([0.5 + wave.call(v), v])
		var cloth := _mix(T.rubric, T.mat_color("dark"), 0.15)
		s.shape(ctrl, s.col(cloth), 0.9, 0.95, true, 1.0, false)
		var bctrl: Array = []
		for i in steps + 1:
			var v := top - 0.08 - ((top - 0.08 - bottom - 0.12) * i) / steps
			bctrl.append_array([-0.4 + wave.call(v), v])
		s.line(bctrl, 0.55, s.col(T.gold), 0.9)
		var bc2: Array = []
		for i in steps + 1:
			var v := top - 0.08 - ((top - 0.08 - bottom - 0.12) * i) / steps
			bc2.append_array([0.4 + wave.call(v), v])
		s.line(bc2, 0.55, s.col(T.gold), 0.9)
		var ev := 0.6
		var ew: float = wave.call(ev)
		s.line([-0.22 + ew, ev, -0.15 + ew, ev + 0.2, 0.15 + ew, ev + 0.2, 0.22 + ew, ev], 0.9, s.col(T.gold), 0.95)
		s.dot(ew, ev + 0.04, 0.05, s.col(T.gold))
		s.line([-0.2 + wave.call(0.9), 0.95, -0.15 + wave.call(0.2), 0.2], 0.4, s.darker(cloth), 0.5)
		s.line([0.18 + wave.call(1.0), 1.1, 0.12 + wave.call(0.0), 0.0], 0.4, s.darker(cloth), 0.5)


static func _flowers(s: PageSketch, r: PageRand.Gen) -> void:
	var T := s.T
	var leaf := T.mat_color("leaf")
	var n := 4 + floori(r.next() * 3)
	var heads: Array = []
	for i in n:
		var u := -0.4 + (0.8 * (i + r.next() * 0.6)) / n
		var hgt := 0.3 + r.next() * 0.38
		var tip := u + (r.next() - 0.5) * 0.18
		s.line([u, 0, (u + tip) / 2 + 0.03, hgt * 0.5, tip, hgt], 0.45, s.darker(leaf, 0.3))
		if r.next() < 0.6:
			var lv := hgt * (0.25 + r.next() * 0.3)
			var sd := -1.0 if r.next() < 0.5 else 1.0
			s.shape([u + sd * 0.01, lv, u + sd * 0.09, lv + 0.06, u + sd * 0.16, lv + 0.02, u + sd * 0.08, lv - 0.02], s.col(leaf), 0.35, 0.95, true, 1.0, false)
		heads.append([tip, hgt, FLOWER_COLS[floori(r.next() * FLOWER_COLS.size())]])
	for hd in heads:
		var u: float = hd[0]
		var v: float = hd[1]
		var colr := s.col(_rgb(hd[2]))
		for kk in 5:
			var a := float(kk) / 5 * TAU + u * 3
			s.dot(u + cos(a) * 0.05, v + sin(a) * 0.05, 0.042, colr, 0.95)
		s.dot(u, v, 0.03, s.col(T.gold if T.inv else _mix(T.gold, T.ink, 0.3)))


static func _grass(s: PageSketch, r: PageRand.Gen) -> void:
	var leaf := _mix(_rgb(s.T.pal.topColor), s.T.mat_color("leaf"), 0.4)
	var n := 9 + floori(r.next() * 5)
	for i in n:
		var u := -0.35 + (0.7 * i) / n + (r.next() - 0.5) * 0.06
		var hgt := 0.35 + r.next() * 0.42
		var bend := (r.next() - 0.5) * 0.5 + u * 0.4
		s.line([u, 0, u + bend * 0.3, hgt * 0.55, u + bend, hgt], 0.6, s.lighter(leaf, 0.2) if i % 3 == 0 else s.darker(leaf, 0.35), 0.9)
		if r.next() < 0.25:
			s.dot(u + bend, hgt + 0.03, 0.03, s.darker(_rgb("#a08040"), 0.2))


static func _rock(s: PageSketch, r: PageRand.Gen) -> void:
	var stone := s.T.mat_color("stone")
	var w := 0.6 + r.next() * 0.2
	var hgt := 0.45 + r.next() * 0.2
	var ctrl: Array = [-w, 0, -w * 0.95, hgt * 0.45, -w * 0.55, hgt * 0.9, -w * 0.05, hgt, w * 0.5, hgt * 0.85, w * 0.92, hgt * 0.45, w, 0]
	s.shape(ctrl, s.col(stone), 1)
	s.clip(ctrl, func() -> void: s.blot(w * 0.55, hgt * 0.1, w * 0.8, hgt * 0.7, PageEnv.CROSS, 0.6))
	s.line([-w * 0.2, hgt * 0.95, -w * 0.05, hgt * 0.6, -w * 0.25, hgt * 0.3], 0.5, null, 0.7)
	s.marks([-w * 0.6, hgt * 0.6, -w * 0.35, hgt * 0.78], s.lighter(stone, 0.5), 1.5, 0.7)
	s.shape([-w * 0.45, hgt * 0.86, -w * 0.15, hgt * 1.03, w * 0.25, hgt * 0.98, w * 0.05, hgt * 0.85], s.col(_rgb(s.T.pal.topColor)), 0.3, 0.85)


static func _reeds(s: PageSketch, r: PageRand.Gen) -> void:
	var leaf := _mix(s.T.mat_color("leaf"), _rgb(s.T.pal.topColor), 0.4)
	var head := _rgb("#5a3a22")
	var n := 4 + floori(r.next() * 3)
	for i in 3:
		var sd := i - 1
		s.line([sd * 0.05, 0, sd * 0.2, 0.5, sd * 0.45, 0.75 + r.next() * 0.2], 0.55, s.darker(leaf, 0.2))
	for i in n:
		var u := -0.3 + (0.6 * i) / maxi(1, n - 1)
		var hgt := 1.15 + r.next() * 0.55
		var tip := u + (r.next() - 0.5) * 0.25
		s.line([u, 0, (u + tip) / 2, hgt * 0.5, tip, hgt], 0.45, s.darker(leaf, 0.35))
		if r.next() < 0.75:
			var hv := hgt - 0.28
			var hu := u + (tip - u) * (hv / hgt)
			s.ellipse(hu, hv, 0.05, 0.16, 0, s.col(head), 0.5)


static func _lantern(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	var T := s.T
	var wood := T.mat_color("wood")
	var hgt := 1.85 + r.next() * 0.2
	var arm := 0.5
	if _static(mode):
		s.shape([-0.06, 0, -0.05, hgt, 0.05, hgt, 0.06, 0], s.col(wood), 0.8)
		s.line([0, hgt - 0.05, arm * 0.5, hgt + 0.05, arm, hgt - 0.02], 0.7)
		s.seg(-0.18, 0, 0.18, 0, 0.8)
	if _live(mode):
		var t := s.env.time
		var sway := sin(t * 1.3 + s.seed) * 0.08
		var hx := arm
		var hy := hgt - 0.02
		var cx := hx + sin(sway) * 0.45
		var cy := hy - cos(sway) * 0.45
		s.seg(hx, hy, hx + sin(sway) * 0.2, hy - cos(sway) * 0.2, 0.4)
		var f := 0.8 + 0.2 * PageRand.noise1(t * 2.5 + s.seed, 9)
		var paper := _mix(T.rubric, T.gold, 0.55)
		s.rays(cx, cy, 0.32, 0.55 + 0.1 * f, 10, T.gold, 0.4 * f, t * 0.15, 1)
		s.ellipse(cx, cy, 0.2, 0.25, -sway, _mix(paper, _rgb("#fff0c0"), 0.35 * f), 0.8)
		s.marks([cx - 0.1, cy + 0.2, cx - 0.12, cy - 0.2, cx + 0.1, cy + 0.2, cx + 0.12, cy - 0.2, cx, cy + 0.24, cx, cy - 0.24], s.darker(paper, 0.4), 0.8, 0.6)
		s.pshape([cx - 0.1, cy + 0.22, cx - 0.09, cy + 0.3, cx + 0.09, cy + 0.3, cx + 0.1, cy + 0.22], s.col(T.ink), 0.5)
		s.pshape([cx - 0.1, cy - 0.22, cx - 0.08, cy - 0.3, cx + 0.08, cy - 0.3, cx + 0.1, cy - 0.22], s.col(T.ink), 0.5)


static func _pipes(s: PageSketch, r: PageRand.Gen) -> void:
	var brass := s.T.mat_color("brass")
	var n := 5 + floori(r.next() * 3)
	var span := 2.1
	var pw := (span / n) * 0.78
	s.pshape([-span / 2 - 0.1, 0, -span / 2 - 0.1, 0.42, span / 2 + 0.1, 0.42, span / 2 + 0.1, 0], s.col(s.T.mat_color("wood")), 0.9)
	for i in n:
		var u := -span / 2 + (span * (i + 0.5)) / n
		var mid := absf(i - (n - 1) / 2.0) / ((n - 1) / 2.0 if n > 1 else 1.0)
		var hgt := 3.35 - mid * 1.5 + r.next() * 0.1
		var hw := pw / 2
		s.pshape([u - hw * 0.35, 0.42, u - hw, 0.75, u - hw, hgt, u + hw, hgt, u + hw, 0.75, u + hw * 0.35, 0.42], s.col(brass), 0.85)
		s.ellipse(u, hgt, hw, hw * 0.3, 0, s.darker(brass, 0.55), 0.6)
		s.pshape([u - hw * 0.6, 0.95, u, 1.15, u + hw * 0.6, 0.95, u, 0.85], s.darker(brass, 0.6), 0.5)
		s.marks([u - hw * 0.45, 1.25, u - hw * 0.45, hgt - 0.1], s.lighter(brass, 0.6), 1.6, 0.75)
		s.marks([u + hw * 0.6, 0.85, u + hw * 0.6, hgt - 0.05], s.darker(brass, 0.4), 1, 0.5)


static func _gear(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	if not _live(mode):
		return
	var T := s.T
	var brass := T.mat_color("brass")
	var R := 1.15 + r.next() * 0.25
	var cy := R * 0.92
	var teeth := 12 + floori(r.next() * 5)
	var dir := -1.0 if r.next() < 0.5 else 1.0
	var rot := s.env.time * 0.35 * dir + r.next() * 6
	if gear_part == 2:
		s.marks([-R * 0.6, cy + R * 0.55, -R * 0.35, cy + R * 0.72], s.lighter(brass, 0.6), 1.6, 0.7)
		return
	if gear_part == 1:
		rot = 0.0
	# Toothed rim with a hollow centre (even-odd): a band between the teeth and the hole.
	var count := teeth * 4
	var outer := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	var inner := R - 0.36
	for i in count:
		var a := rot + float(i) / count * TAU
		var ph := i % 4
		var rr := R if ph == 1 or ph == 2 else R - 0.17
		outer.append(Vector2(s.X(cos(a) * rr), s.Y(cy + sin(a) * rr)))
		inner_pts.append(Vector2(s.X(cos(a) * inner), s.Y(cy + sin(a) * inner)))
	s.painter.strip(outer, inner_pts, PageTones.alpha(s.col(brass), 0.95), true)
	var ink := PageTones.alpha(s.ink_color(), 0.9)
	var w := s.lw(0.75)
	s.painter.stroke(outer, w, ink, true)
	var hole := PackedVector2Array()
	for i in 48:
		var a := float(i) / 48 * TAU
		hole.append(Vector2(s.X(cos(a) * inner), s.Y(cy + sin(a) * inner)))
	s.painter.stroke(hole, w, ink, true)
	for i in 5:
		var a := rot + float(i) / 5 * TAU
		var ca := cos(a)
		var sa := sin(a)
		var sw := 0.07
		s.pshape([ca * 0.15 - sa * sw, cy + sa * 0.15 + ca * sw, ca * (inner + 0.02) - sa * sw, cy + sa * (inner + 0.02) + ca * sw, ca * (inner + 0.02) + sa * sw, cy + sa * (inner + 0.02) - ca * sw, ca * 0.15 + sa * sw, cy + sa * 0.15 - ca * sw], s.col(brass), 0.6, 0.3)
	s.ellipse(0, cy, 0.22, 0.22, 0, s.col(_mix(brass, T.gold, 0.3)), 0.8)
	s.dot(0, cy, 0.07, s.darker(brass, 0.6))
	if gear_part == 0:
		s.marks([-R * 0.6, cy + R * 0.55, -R * 0.35, cy + R * 0.72], s.lighter(brass, 0.6), 1.6, 0.7)


static func _crystals(s: PageSketch, r: PageRand.Gen) -> void:
	var c1 := s.T.mat_color("crystal")
	var c2 := s.T.mat_color("crystal", true)
	var n := 4 + floori(r.next() * 3)
	var order: Array = []
	for i in n:
		order.append(i)
	var mid := (n - 1) / 2.0
	# Outermost first (a stable sort, like the web build's).
	var keyed: Array = []
	for i in order:
		keyed.append([-absf(i - mid), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for e in keyed:
		var i: int = e[1]
		var u := -0.45 + (0.9 * i) / maxi(1, n - 1)
		var ang := (u * 0.9 + (r.next() - 0.5) * 0.3) * 0.9
		var length := 0.55 + (1 - absf(u) * 1.4) * 0.6 + r.next() * 0.15
		var w := 0.1 + r.next() * 0.06
		var ca := sin(ang)
		var sa := cos(ang)
		var tip_u := u + ca * length
		var tip_v := sa * length
		var mid_u := u + ca * length * 0.78
		var mid_v := sa * length * 0.78
		var nx := sa * w
		var ny := -ca * w
		var ctrl: Array = [u - nx, 0 - ny, mid_u - nx, mid_v - ny, tip_u, tip_v, mid_u + nx, mid_v + ny, u + nx, 0 + ny]
		s.pshape(ctrl, s.col(_mix(c1, c2, r.next() * 0.5)), 0.7, 0.2)
		s.region([u - nx, -ny, mid_u - nx, mid_v - ny, tip_u, tip_v, u, 0], s.lighter(c1, 0.6), 0.55, true)
		s.marks([u, 0, tip_u, tip_v], s.darker(c2, 0.3), 0.8, 0.7)
	s.rays(0, 0.7, 0.75, 0.95, 8, s.lighter(c1, 0.7), 0.35, s.seed, 1)


static func _statue(s: PageSketch, r: PageRand.Gen) -> void:
	var marble := s.T.mat_color("marble")
	var fill := s.col(marble)
	var face := -1.0 if r.next() < 0.5 else 1.0
	s.pshape([-0.5, 0, -0.5, 0.15, 0.5, 0.15, 0.5, 0], fill, 0.9)
	s.pshape([-0.38, 0.15, -0.36, 1.15, 0.36, 1.15, 0.38, 0.15], fill, 0.9)
	s.clip([-0.38, 0.15, -0.36, 1.15, 0.36, 1.15, 0.38, 0.15], func() -> void: s.blot(0.4, 0.6, 0.2, 0.6, PageEnv.HATCH, 0.6), true)
	s.pshape([-0.46, 1.15, -0.46, 1.28, 0.46, 1.28, 0.46, 1.15], fill, 0.8)
	s.marks([-0.25, 0.35, 0.25, 0.35, -0.25, 0.95, 0.25, 0.95], s.darker(marble, 0.3), 0.8, 0.5)
	s.flip = face
	var bust: Array = [-0.42, 1.28, -0.38, 1.62, -0.2, 1.82, -0.08, 1.88, 0.1, 1.88, 0.22, 1.82, 0.38, 1.62, 0.42, 1.28]
	s.shape(bust, fill, 0.9)
	s.pshape([-0.08, 1.8, -0.08, 2.0, 0.08, 2.0, 0.08, 1.8], fill, 0.6)
	var head: Array = [0.0, 1.98, -0.17, 2.08, -0.19, 2.3, -0.08, 2.47, 0.1, 2.46, 0.2, 2.32, 0.23, 2.22, 0.27, 2.18, 0.21, 2.12, 0.18, 2.02]
	s.shape(head, fill, 0.9)
	var hair := scallop(-0.06, 2.33, 0.21, 0.19, 9, s.seed + 5, 0.3)
	s.shape(hair, s.darker(marble, 0.18), 0.7, 0.95, true, 1.0, false)
	s.dot(0.12, 2.27, 0.018, s.ink_color())
	s.clip(bust, func() -> void: s.blot(0.35, 1.45, 0.25, 0.4, PageEnv.CROSS, 0.55))
	s.line([-0.25, 1.7, -0.05, 1.45, 0.15, 1.7], 0.45, null, 0.6)
	s.flip = 1


static func _curtain(s: PageSketch, r: PageRand.Gen) -> void:
	var T := s.T
	var velvet := _mix(T.rubric, _rgb("#401020"), 0.5) if T.inv else _mix(T.rubric, _rgb("#5a0c1c"), 0.45)
	var gold := T.gold
	var tie := 1.5 + r.next() * 0.3
	for sd in [-1.0, 1.0]:
		s.flip = sd
		var panel: Array = [-1.25, 4.0, -0.15, 4.0, -0.25, 3.0, -0.75, tie + 0.15, -0.6, tie - 0.1, -0.35, 0.6, -0.4, 0, -1.3, 0, -1.2, tie, -1.18, 3.0]
		s.shape(panel, s.col(velvet), 1)
		s.clip(panel, func() -> void:
			s.blot(-0.3, 2.5, 0.35, 2.4, PageEnv.CROSS, 0.55)
			s.blot(-1.25, 1.0, 0.2, 1.5, PageEnv.HATCH, 0.45))
		for f in 3:
			var u0 := -1.1 + f * 0.3
			s.line([u0, 3.95, u0 + 0.05, 3.0, -0.95 + f * 0.1, tie + 0.05], 0.45, s.darker(velvet, 0.5), 0.75)
			s.line([-0.95 + f * 0.1, tie - 0.05, -1.05 + f * 0.25, 0.8, -1.15 + f * 0.3, 0.03], 0.45, s.darker(velvet, 0.5), 0.75)
		s.line([-1.15, 3.6, -1.1, 2.5], 0.6, s.lighter(velvet, 0.35), 0.6)
		s.line([-1.25, tie, -0.95, tie - 0.06, -0.62, tie + 0.02], 0.9, s.col(gold), 0.95)
		s.pshape([-0.66, tie - 0.02, -0.72, tie - 0.35, -0.55, tie - 0.35, -0.6, tie - 0.02], s.col(gold), 0.5)
	s.flip = 1
	s.pshape([-1.35, 4.2, 1.35, 4.2, 1.35, 3.95, -1.35, 3.95], s.col(_mix(velvet, Color.BLACK, 0.1)), 0.8)
	for i in 3:
		var u0 := -1.35 + i * 0.9
		s.shape([u0, 3.95, u0 + 0.45, 3.62, u0 + 0.9, 3.95], s.col(velvet), 0.7)
		s.line([u0 + 0.05, 3.9, u0 + 0.45, 3.67, u0 + 0.85, 3.9], 0.5, s.col(gold), 0.9)
	s.line([-1.35, 4.12, 1.35, 4.12], 0.6, s.col(gold), 0.9)


static func _arch(s: PageSketch, r: PageRand.Gen) -> void:
	var stone := s.T.mat_color("stone")
	var fill := s.col(stone)
	var pier := 2.0
	var ri := 0.85
	var ro := 1.3
	var broken := 0
	if r.next() < 0.5:
		broken = -1 if r.next() < 0.5 else 1
	for sd in [-1.0, 1.0]:
		var ctrl: Array = [sd * ri, 0, sd * ri, pier, sd * ro, pier, sd * ro, 0]
		s.pshape(ctrl, fill, 0.9)
		var segs: Array = []
		var v := 0.4
		while v < pier:
			segs.append_array([sd * ri, v, sd * ro, v])
			v += 0.4
		s.marks(segs, s.darker(stone, 0.4), 0.9, 0.6)
		if sd == 1.0:
			s.clip(ctrl, func() -> void: s.blot(ro, pier / 2, 0.25, pier, PageEnv.HATCH, 0.5), true)
	var n := 9
	for i in n:
		var a0 := PI - (float(i) / n) * PI
		var a1 := PI - (float(i + 1) / n) * PI
		if broken == -1 and i < 3:
			continue
		if broken == 1 and i > n - 4:
			continue
		var key := i == floori(n / 2.0)
		var o := ro + 0.1 if key else ro
		s.pshape([cos(a0) * ri, pier + sin(a0) * ri, cos(a0) * o, pier + sin(a0) * o, cos(a1) * o, pier + sin(a1) * o, cos(a1) * ri, pier + sin(a1) * ri], fill, 0.7, 0.3)
	var ivy := _rgb(s.T.pal.topColor)
	for i in 3:
		var u := -0.6 + i * 0.55 + r.next() * 0.2
		var vv := pier + sqrt(maxf(0, ri * ri - u * u)) + 0.1
		var length := 0.5 + r.next() * 0.8
		s.line([u, vv + 0.2, u + 0.06, vv - length * 0.5, u - 0.03, vv - length], 0.4, s.darker(ivy, 0.3), 0.8)
		for j in 4:
			var lv := vv - (length * j) / 4
			s.dot(u + (0.06 if j % 2 else -0.05), lv, 0.06, s.col(ivy), 0.9)


static func _mushroom(s: PageSketch, r: PageRand.Gen) -> void:
	var cap := s.T.rubric if r.next() < 0.7 else _rgb("#9a6a3a")
	var stem := _rgb("#efe4cc")
	var n := 2 + floori(r.next() * 2)
	for i in n:
		var u := -0.25 + (0.5 * i) / maxi(1, n - 1) + (r.next() - 0.5) * 0.08
		var hgt := 0.22 + r.next() * 0.3
		var cw := 0.13 + hgt * 0.35
		var lean := (r.next() - 0.5) * 0.12
		s.pshape([u - 0.05, 0, u - 0.04 + lean, hgt, u + 0.04 + lean, hgt, u + 0.05, 0], s.col(stem), 0.6)
		var cu := u + lean
		var cap_c: Array = [cu - cw, hgt - 0.02, cu - cw * 0.8, hgt + cw * 0.45, cu, hgt + cw * 0.62, cu + cw * 0.8, hgt + cw * 0.45, cu + cw, hgt - 0.02]
		s.shape(cap_c, s.col(cap), 0.7)
		for d in 3:
			s.dot(cu + (d - 1) * cw * 0.5, hgt + cw * (0.28 + (0.15 if d == 1 else 0.0)), 0.022, s.col(_rgb("#fffaf0")), 0.9)


static func _bell(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	var wood := s.T.mat_color("wood")
	var brass := s.T.mat_color("brass")
	var beam := 2.15
	if _static(mode):
		s.pshape([-0.66, 0, -0.62, beam, -0.52, beam, -0.5, 0], s.col(wood), 0.8)
		s.pshape([0.5, 0, 0.52, beam, 0.62, beam, 0.66, 0], s.col(wood), 0.8)
		s.pshape([-0.78, beam, -0.78, beam + 0.14, 0.78, beam + 0.14, 0.78, beam], s.col(wood), 0.8)
		s.shape([-0.88, beam + 0.14, 0, beam + 0.48, 0.88, beam + 0.14], s.col(_mix(wood, s.T.rubric, 0.25)), 0.8)
		s.seg(-0.6, 0.5, 0.6, 0.5, 0.5)
	if _live(mode):
		var t := s.env.time
		var sway := sin(t * 1.25 + r.next() * 6) * 0.1
		var py := beam - 0.02
		var cs := cos(sway)
		var sn := sin(sway)
		var rot := func(u: float, v: float) -> Vector2:
			var dy := v - py
			return Vector2(u * cs - dy * sn, py + u * sn + dy * cs)
		var pts: Array = []
		for uv in [Vector2(-0.12, 0), Vector2(-0.16, -0.12), Vector2(-0.2, -0.45), Vector2(-0.32, -0.68), Vector2(-0.36, -0.75), Vector2(0.36, -0.75), Vector2(0.32, -0.68), Vector2(0.2, -0.45), Vector2(0.16, -0.12), Vector2(0.12, 0)]:
			var q: Vector2 = rot.call(uv.x, py + uv.y)
			pts.append_array([q.x, q.y])
		s.shape(pts, s.col(brass), 0.85)
		var h1: Vector2 = rot.call(-0.1, py - 0.2)
		var h2: Vector2 = rot.call(-0.18, py - 0.62)
		s.marks([h1.x, h1.y, h2.x, h2.y], s.lighter(brass, 0.65), 1.8, 0.8)
		var l1: Vector2 = rot.call(-0.33, py - 0.7)
		var l2: Vector2 = rot.call(0.33, py - 0.7)
		s.marks([l1.x, l1.y, l2.x, l2.y], s.darker(brass, 0.5), 1, 0.7)
		var cc: Vector2 = rot.call(sin(sway * 1.6) * 0.1, py - 0.84)
		s.dot(cc.x, cc.y, 0.06, s.ink_color())


static func _candles(s: PageSketch, r: PageRand.Gen, mode: int) -> void:
	var T := s.T
	var wax := _rgb("#e8e2d0") if T.inv else _rgb("#f3ead2")
	var brass := T.mat_color("brass")
	var n := 2 + floori(r.next() * 3)
	var list: Array = []
	for i in n:
		var u := -0.32 + (0.64 * i) / maxi(1, n - 1) + (r.next() - 0.5) * 0.06
		list.append([u, 0.3 + r.next() * 0.55, 0.05 + r.next() * 0.025])
	if _static(mode):
		s.ellipse(0, 0.05, 0.48, 0.07, 0, s.col(brass), 0.7)
		for c in list:
			var u: float = c[0]
			var h: float = c[1]
			var w: float = c[2]
			s.pshape([u - w, 0.06, u - w, h, u - w * 0.3, h + 0.02, u + w * 0.4, h - 0.01, u + w, h, u + w, 0.06], s.col(wax), 0.6)
			s.shape([u + w * 0.2, h, u + w * 0.35, h - 0.12, u + w * 0.5, h - 0.15, u + w * 0.62, h - 0.02], s.col(wax), 0.4, 0.95, true, 1.0, false)
			s.seg(u, h, u + 0.01, h + 0.05, 0.5)
	if _live(mode):
		var t := s.env.now
		for i in list.size():
			var u: float = list[i][0]
			var h: float = list[i][1]
			var f := PageRand.noise1(t * 7 + i * 13 + s.seed, 3)
			var fh := 0.13 + 0.03 * f
			var lean := 0.02 * PageRand.noise1(t * 4 + i * 5, 4)
			s.rays(u, h + 0.12, 0.13, 0.24 + 0.03 * f, 8, T.gold, 0.35, t * 0.3 + i, 0.9)
			s.pshape([u - 0.035, h + 0.06, u + lean, h + 0.06 + fh, u + 0.035, h + 0.06, u, h + 0.04], _mix(T.gold, _rgb("#ffcf6a"), 0.4), 0.35, 0.2)
			s.dot(u + lean * 0.3, h + 0.09, 0.016, Color8(255, 250, 230), 0.95)

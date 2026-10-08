class_name PageTerrain
extends RefCounted
## Paints everything static in a world rectangle, back layer to front layer, the way an
## illustrator builds up a page (terrain.ts): wash, marks, shade, top edging, the ink
## outline along each layer's silhouette, then thorns and decor at that depth. Used for
## the cached chunks and for live occlusion fix-ups.

## Materials that take the palette's top edging (grass, moss, leaves, snow, carpet).
const CAPPED := [Level.MAT_STONE, Level.MAT_BRICK, Level.MAT_WOOD, Level.MAT_MARBLE, Level.MAT_LEAF, Level.MAT_DARK]


class Pen:
	var painter: PagePainter
	var env: PageEnv
	var p: PageEnv.Proj
	var variant := 0
	var L: PageTones.Layer
	var z := 0


class MarkSet:
	var light := PagePath.new()
	var dark := PagePath.new()
	var fine := PagePath.new()
	var gold := PagePath.new()
	var hatch := PagePath.new()
	var dense := PagePath.new()
	var white := PagePath.new()
	var tint_d := PagePath.new()
	var tint_l := PagePath.new()


static func _capped(m: int) -> bool:
	return CAPPED.has(m)


## `use_mul` lets the cast shadows multiply what is already painted (the chunk painter
## passes true; occlusion fix-ups never draw shadows).
static func paint_static(painter: PagePainter, env: PageEnv, p: PageEnv.Proj, wx0: float, wy0: float, wx1: float, wy1: float, variant: int) -> void:
	var W := env.world
	var cx0 := maxi(0, floori(wx0) - 1)
	var cx1 := mini(W.w - 1, ceili(wx1))
	var cy0 := maxi(0, floori(wy0) - 1)
	var cy1 := mini(W.h - 1, ceili(wy1))
	var buckets: Array = []
	for z in W.d:
		buckets.append(PackedInt32Array())
	for y in range(cy0, cy1 + 1):
		for x in range(cx0, cx1 + 1):
			var f := W.front[x + W.w * y]
			if f != Level.NO_DEPTH:
				var b: PackedInt32Array = buckets[f]
				b.append(x)
				b.append(y)
				buckets[f] = b
	var m := 0.6
	var rx0 := wx0 - m
	var rx1 := wx1 + m
	var ry0 := wy0 - m
	var ry1 := wy1 + m
	var pen := Pen.new()
	pen.painter = painter
	pen.env = env
	pen.p = p
	pen.variant = variant
	painter.use(PagePainter.NORMAL)
	for z in range(W.d - 1, -1, -1):
		pen.L = env.tones.layers[z]
		pen.z = z
		var cells: PackedInt32Array = buckets[z]
		var runs: Array = []
		for r in W.edges[z]:
			if r.x1 >= rx0 and r.x0 <= rx1 and r.y1 >= ry0 and r.y0 <= ry1:
				runs.append(r)
		if not cells.is_empty():
			if z < W.d - 1:
				_cast_shadow(pen, cells)
			_fill_cells(pen, cells)
			_marks(pen, cells)
			_volume(pen, runs)
		_seams(pen, rx0, ry0, rx1, ry1)
		_top_caps(pen, runs)
		_outlines(pen, runs)
		var th: PackedInt32Array = W.thorns[z]
		for i in range(0, th.size(), 2):
			var tx := th[i]
			var ty := th[i + 1]
			if tx + 1 < rx0 or tx > rx1 or ty + 1 < ry0 or ty > ry1:
				continue
			draw_thorn(pen, tx, ty)
		for di in W.decor_by_layer[z]:
			if di.x1 < wx0 or di.x0 > wx1 or di.y1 < wy0 or di.y0 > wy1:
				continue
			PageDecor.draw(painter, env, p, di, variant, PageDecor.STATIC)


## Granulation over the whole chunk so the ink sits in the paper (source-atop the wash).
static func granulate(painter: PagePainter, env: PageEnv, p: PageEnv.Proj, w: float, h: float) -> void:
	painter.use(PagePainter.MUL)
	env.pat_rect(painter, 0, 0, w, h, PageEnv.WASH, 1.0, p)
	painter.use(PagePainter.NORMAL)


# ---------------------------------------------------------------- shadow and fill

## The nearer layer throws a hatched shadow down and to the right onto whatever is behind.
static func _cast_shadow(pen: Pen, cells: PackedInt32Array) -> void:
	var p := pen.p
	var painter := pen.painter
	var env := pen.env
	var k := p.k
	var o1 := k * 0.07
	var o2 := k * 0.17
	painter.use(PagePainter.MUL)
	for pass_i in 2:
		var off := Vector2(o1, o1 * 0.9) if pass_i == 0 else Vector2(o2, o2 * 0.85)
		var kind := PageEnv.CROSS if pass_i == 0 else PageEnv.HATCH
		var a := 0.55 if pass_i == 0 else 0.5
		for i in range(0, cells.size(), 2):
			var x := p.ox + cells[i] * k + off.x
			var y := p.oy - (cells[i + 1] + 1) * k + off.y
			env.pat_rect(painter, x, y, k, k, kind, a, p, off)
	painter.use(PagePainter.NORMAL)


static func _fill_cells(pen: Pen, cells: PackedInt32Array) -> void:
	var p := pen.p
	var L := pen.L
	var W := pen.env.world
	var painter := pen.painter
	var k := p.k
	var inset := k * 0.08
	var tint_d: Array[Rect2] = []
	var tint_l: Array[Rect2] = []
	for i in range(0, cells.size(), 2):
		var x := cells[i]
		var y := cells[i + 1]
		var mt := W.mat(x, y, pen.z)
		var X := p.ox + x * k
		var Y := p.oy - (y + 1) * k
		var c: Color = L.fill[mt if mt > 0 and mt != Level.MAT_THORN else Level.MAT_STONE]
		painter.fill_rect(X, Y, k, k, Color(c.r, c.g, c.b, 0.97))
		var hh := PageRand.hash01(x, y, pen.z, 77)
		if hh < 0.14:
			tint_d.append(Rect2(X + inset, Y + inset, k - inset * 2, k - inset * 2))
		elif hh > 0.9:
			tint_l.append(Rect2(X + inset, Y + inset, k - inset * 2, k - inset * 2))
	var cd := PageTones.alpha(L.dark, 0.04 * (0.5 + L.density))
	for r in tint_d:
		painter.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, cd)
	var cl := PageTones.alpha(L.light, 0.05 * (0.5 + L.density))
	for r in tint_l:
		painter.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, cl)


# ---------------------------------------------------------------- material marks

static func _marks(pen: Pen, cells: PackedInt32Array) -> void:
	var p := pen.p
	var L := pen.L
	var env := pen.env
	var W := env.world
	var painter := pen.painter
	var q := p.k / p.dpr
	var lod := 2 if q >= 46.0 else (1 if q >= 28.0 else 0)
	var ms := MarkSet.new()
	var z := pen.z
	for i in range(0, cells.size(), 2):
		var x := cells[i]
		var y := cells[i + 1]
		var mt := W.mat(x, y, z)
		var below := W.front_at(x, y - 1) == z and W.mat(x, y - 1, z) == mt
		var left := W.front_at(x - 1, y) == z and W.mat(x - 1, y, z) == mt
		match mt:
			Level.MAT_STONE:
				_stone(ms, p, x, y, z, below, lod, pen.variant)
			Level.MAT_BRICK:
				_brick(ms, p, x, y, z, below, lod, pen.variant)
			Level.MAT_WOOD:
				_wood(ms, p, x, y, z, below, lod, pen.variant)
			Level.MAT_BRASS:
				_brass(ms, p, x, y, z, below, left, lod, pen.variant)
			Level.MAT_DARK:
				_dark(ms, p, x, y, z, lod, pen.variant)
			Level.MAT_CRYSTAL:
				_crystal(ms, p, x, y, z, lod)
			Level.MAT_LEAF:
				_leaf(ms, p, x, y, z, lod)
			Level.MAT_MARBLE:
				_marble(ms, p, x, y, z, below, left, lod, pen.variant)
	var d := L.density
	var T := env.tones
	painter.fill_path(ms.tint_d, PageTones.alpha(L.dark, 0.07 * d + 0.03), false)
	painter.fill_path(ms.tint_l, PageTones.alpha(L.light, 0.08 * d + 0.03), false)
	env.pat_path(painter, ms.dense, PageEnv.DENSE, 0.8, p)
	env.pat_path(painter, ms.hatch, PageEnv.HATCH, 0.45 * d + 0.1, p)
	painter.stroke_path(ms.light, maxf(0.8, 1.15 * p.px), PageTones.alpha(L.light, 0.55 * d + 0.25))
	painter.stroke_path(ms.dark, maxf(0.8, 1.15 * p.px), PageTones.alpha(L.dark, 0.5 * d + 0.2))
	painter.stroke_path(ms.fine, maxf(0.6, 0.8 * p.px), PageTones.alpha(L.dark, 0.35 * d + 0.15))
	painter.fill_path(ms.gold, PageTones.alpha(PageTones.mix(T.gold_light, L.tone, 0.3 * L.k), 0.85))
	var white := Color.WHITE if T.inv else PageTones.mix(T.paper, Color.WHITE, 0.5)
	painter.fill_path(ms.white, PageTones.alpha(white, 0.5 * d + 0.2))


## A horizontal mark across a cell whose ends meet the neighbour's marks exactly.
static func _hmark(path: PagePath, p: PageEnv.Proj, x0: float, x1: float, y: float, amp: float, salt: int, v: int) -> void:
	var Y := p.oy - y * p.k
	var yk := PageInk.jround(y * 64.0)
	var xk := PageInk.jround(x0 * 64.0)
	var j0 := PageRand.hs(xk, yk, salt) * amp
	var j1 := PageRand.hs(PageInk.jround(x1 * 64.0), yk, salt) * amp
	var X0 := p.ox + x0 * p.k
	var X1 := p.ox + x1 * p.k
	path.move_to(X0, Y + j0)
	path.line_to(X0 + (X1 - X0) * 0.5, Y + (j0 + j1) * 0.5 + PageRand.hs(xk, yk, salt + 1 + v * 7) * amp * 1.2)
	path.line_to(X1, Y + j1)


static func _vmark(path: PagePath, p: PageEnv.Proj, x: float, y0: float, y1: float, amp: float, seed: int, v: int) -> void:
	var X := p.ox + x * p.k
	path.move_to(X + PageRand.hs(seed, 1, v) * amp, p.oy - y0 * p.k)
	path.line_to(X + PageRand.hs(seed, 2, v) * amp, p.oy - y1 * p.k)


static func _rect_w(path: PagePath, p: PageEnv.Proj, x0: float, y0: float, x1: float, y1: float) -> void:
	path.rect(p.ox + x0 * p.k, p.oy - y1 * p.k, (x1 - x0) * p.k, (y1 - y0) * p.k)


## markLine: a thin wobbly polyline.
static func mark_line(path: PagePath, x0: float, y0: float, x1: float, y1: float, amp: float, seed: int, boil: int) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var l := sqrt(dx * dx + dy * dy)
	if l < 0.5:
		return
	var nx := -dy / l
	var ny := dx / l
	var segs := 4 if l > 40.0 else (2 if l > 14.0 else 1)
	var h1 := PageRand.hs(seed, boil, 1) * amp * 0.5
	path.move_to(x0 + nx * h1, y0 + ny * h1)
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var o := PageRand.hs(seed, boil, 2) * amp * 0.5 if i == segs else PageRand.hs(seed, i, 3 + boil) * amp
		path.line_to(x0 + dx * t + nx * o, y0 + dy * t + ny * o)


static func _stone(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, below: bool, lod: int, v: int) -> void:
	var a := 0.7 * p.px
	var k := p.k
	if below:
		_hmark(ms.light, p, x, x + 1, y, a, 3, v)
	var has_joint := PageRand.hash01(x, y, z, 6) > 0.28
	var jx := x + 0.3 + PageRand.hash01(x, y, z, 5) * 0.4
	if has_joint:
		_vmark(ms.light, p, jx, y, y + 1, a * 0.6, x * 31 + y, v)
	if lod == 0:
		return
	_hmark(ms.white, p, x, x + 1, y + 0.93, a * 0.4, 21, v)
	_hmark(ms.dark, p, x, x + 1, y + 0.07, a * 0.4, 22, v)
	_rect_w(ms.hatch, p, x, y, x + 1, y + 0.16)
	var split := PageRand.hash01(x, y, z, 9)
	if split < 0.22:
		var lft := PageRand.hash01(x, y, z, 10) < 0.5
		var sx0: float = x if lft else (jx if has_joint else float(x))
		var sx1: float = (jx if has_joint else x + 1.0) if lft else x + 1.0
		_hmark(ms.light, p, sx0, sx1, y + 0.5, a * 0.6, 23, v)
		_hmark(ms.dark, p, sx0 + 0.02, sx1 - 0.02, y + 0.56, a * 0.3, 24, v)
	if has_joint:
		mark_line(ms.dark, p.ox + (jx - 0.03) * k, p.oy - (y + 0.1) * k, p.ox + (jx - 0.03) * k, p.oy - (y + 0.88) * k, a * 0.3, x * 3 + y * 7, v)
	if lod >= 1 and PageRand.hash01(x, y, z, 7) < 0.3:
		var bx := (jx if has_joint else x + 1.0) - 0.1
		var by := y + 0.12
		for i in 3:
			var o := i * 0.07
			mark_line(ms.fine, p.ox + (bx - 0.22 + o) * k, p.oy - by * k, p.ox + (bx - 0.1 + o) * k, p.oy - (by + 0.15) * k, a * 0.4, x * 7 + y * 3 + i, v)
	var h := PageRand.hash01(x, y, z, 8)
	if h < 0.08:
		var cx := x + 0.2 + PageRand.hash01(x, y, 9) * 0.6
		var cy := y + 0.95
		ms.dark.move_to(p.ox + cx * k, p.oy - cy * k)
		for i in 4:
			cx += PageRand.hs(x, y, i, 10) * 0.12
			cy -= 0.12 + PageRand.hash01(x, y, i, 11) * 0.08
			ms.dark.line_to(p.ox + cx * k, p.oy - cy * k)
	elif h > 0.85:
		ms.tint_d.rect(p.ox + (x + 0.06) * k, p.oy - (y + 0.9) * k, k * 0.88, k * 0.8)
	elif h > 0.76:
		ms.tint_l.rect(p.ox + (x + 0.06) * k, p.oy - (y + 0.9) * k, k * 0.88, k * 0.8)
	if lod == 2:
		for i in 4:
			var sx := p.ox + (x + PageRand.hash01(x, y, i, 12)) * k
			var sy := p.oy - (y + 0.15 + PageRand.hash01(x, y, i, 13) * 0.75) * k
			ms.fine.move_to(sx, sy)
			ms.fine.line_to(sx + 0.7 * p.px, sy + 0.5 * p.px)


static func _brick(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, below: bool, lod: int, v: int) -> void:
	var a := 0.5 * p.px
	var courses := 2 if lod == 0 else 4
	var bw := 1.0 if lod == 0 else 0.5
	for c in courses:
		var v0 := float(c) / courses
		var v1 := float(c + 1) / courses
		if c > 0 or below:
			_hmark(ms.light, p, x, x + 1, y + v0, a, 4, v)
		var row := y * courses + c
		var off := (row & 1) * bw * 0.5
		var u := off
		while u < 1.0 - 1e-6:
			if u > 1e-6:
				_vmark(ms.light, p, x + u, y + v0, y + v1, a * 0.5, x * 97 + row * 13 + PageInk.jround(u * 8.0), v)
			var hh := PageRand.hash01(PageInk.jround((x + u) * 4.0), row, z, 15)
			var u1 := minf(1.0, u + bw)
			if hh < 0.22:
				_rect_w(ms.tint_d, p, x + u + 0.02, y + v0 + 0.02, x + u1 - 0.02, y + v1 - 0.02)
			elif hh > 0.85:
				_rect_w(ms.tint_l, p, x + u + 0.02, y + v0 + 0.02, x + u1 - 0.02, y + v1 - 0.02)
			u += bw
		if off > 0.0:
			var h2 := PageRand.hash01(PageInk.jround(x * 4.0), row, z, 15)
			if h2 < 0.22:
				_rect_w(ms.tint_d, p, x + 0.02, y + v0 + 0.02, x + off - 0.02, y + v1 - 0.02)
	if lod >= 1 and PageRand.hash01(x, y, z, 16) < 0.35:
		var cc := floori(PageRand.hash01(x, y, 17) * courses)
		_hmark(ms.dark, p, x + 0.05, x + 0.45, y + float(cc) / courses + 0.03, a * 0.4, 18, v)


static func _wood(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, below: bool, lod: int, v: int) -> void:
	var a := 0.5 * p.px
	var k := p.k
	var planks := 2 if lod == 0 else 3
	for c in planks:
		var v0 := float(c) / planks
		if c > 0 or below:
			_hmark(ms.dark, p, x, x + 1, y + v0, a, 5, v)
			_hmark(ms.light, p, x, x + 1, y + v0 - 0.035, a * 0.6, 6, v)
		if lod >= 1:
			var row := y * planks + c
			for g in (2 if lod == 2 else 1):
				var base := y + v0 + (0.3 + 0.4 * g) / planks
				var amp := 0.05 / planks
				var f := 2.1 + PageRand.hash01(row, g, 19)
				var ph := PageRand.hash01(row, g, 20) * 6.28
				ms.fine.move_to(p.ox + x * k, p.oy - (base + sin(x * f + ph) * amp) * k)
				for s in range(1, 5):
					var wx := x + s / 4.0
					ms.fine.line_to(p.ox + wx * k, p.oy - (base + sin(wx * f + ph) * amp) * k)
		if PageRand.hash01(x, y * planks + c, z, 21) < 0.5:
			var nx := p.ox + (x + 0.06) * k
			var ny := p.oy - (y + v0 + 0.5 / planks) * k
			ms.dark.move_to(nx + 1.1 * p.px, ny)
			ms.dark.arc(nx, ny, 1.1 * p.px, 0, TAU)
	if lod >= 1 and PageRand.hash01(x, y, z, 22) < 0.12:
		var kx := p.ox + (x + 0.3 + PageRand.hash01(x, y, 23) * 0.4) * k
		var ky := p.oy - (y + 0.2 + PageRand.hash01(x, y, 24) * 0.6) * k
		ms.dark.move_to(kx + k * 0.08, ky)
		ms.dark.ellipse(kx, ky, k * 0.08, k * 0.035, 0, 0, TAU)
		ms.fine.move_to(kx + k * 0.14, ky)
		ms.fine.ellipse(kx, ky, k * 0.14, k * 0.06, 0, 0, TAU)


static func _brass(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, below: bool, left: bool, lod: int, v: int) -> void:
	var a := 0.35 * p.px
	var k := p.k
	if below:
		_hmark(ms.dark, p, x, x + 1, y, a, 7, v)
	if left:
		_vmark(ms.dark, p, x, y, y + 1, a, x * 13 + y, v)
	_hmark(ms.light, p, x + 0.02, x + 0.98, y + 0.78, a, 8, v)
	if lod >= 1:
		_hmark(ms.light, p, x + 0.1, x + 0.9, y + 0.7, a, 9, v)
	_hmark(ms.dark, p, x + 0.04, x + 0.96, y + 0.22, a, 10, v)
	if lod >= 1:
		var r := maxf(1.0, k * 0.035)
		for uw in [Vector2(0.12, 0.12), Vector2(0.88, 0.12), Vector2(0.12, 0.88), Vector2(0.88, 0.88)]:
			var cx: float = p.ox + (x + uw.x) * k
			var cy: float = p.oy - (y + uw.y) * k
			ms.dark.move_to(cx + r, cy)
			ms.dark.arc(cx, cy, r, 0, TAU)
			ms.white.move_to(cx - r * 0.2 + r * 0.45, cy - r * 0.3)
			ms.white.arc(cx - r * 0.2, cy - r * 0.3, r * 0.45, 0, TAU)
	var n := 3 if lod == 2 else 1
	for i in n:
		if PageRand.hash01(x, y, z, 30 + i) > 0.6:
			continue
		var fx := p.ox + (x + 0.15 + PageRand.hash01(x, y, 31 + i) * 0.7) * k
		var fy := p.oy - (y + 0.3 + PageRand.hash01(x, y, 32 + i) * 0.4) * k
		ms.gold.add(PageInk.blob_pts(fx, fy, maxf(1.2, k * (0.03 + PageRand.hash01(x, y, 33 + i) * 0.04)), 0.5, x * 5 + y * 3 + i, 0, 7), true)


static func _dark(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, lod: int, v: int) -> void:
	_rect_w(ms.dense, p, x, y, x + 1, y + 1)
	if lod >= 1 and PageRand.hash01(x, y, z, 40) < 0.4:
		var sx := x + 0.2 + PageRand.hash01(x, y, 41) * 0.5
		var sy := y + 0.2 + PageRand.hash01(x, y, 42) * 0.6
		mark_line(ms.light, p.ox + sx * p.k, p.oy - sy * p.k, p.ox + (sx + 0.25) * p.k, p.oy - (sy - 0.05) * p.k, 0.4 * p.px, x * 3 + y, v)


static func _crystal(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, lod: int) -> void:
	var k := p.k
	var ax := 0.3 + PageRand.hash01(x, y, z, 50) * 0.4
	var ay := 0.35 + PageRand.hash01(x, y, z, 51) * 0.3
	var bx := ax + PageRand.hs(x, y, 52) * 0.2
	var by := minf(0.95, ay + 0.25)
	var X := func(u: float) -> float: return p.ox + (x + u) * k
	var Y := func(w: float) -> float: return p.oy - (y + w) * k
	ms.dark.move_to(X.call(0.0), Y.call(0.0))
	ms.dark.line_to(X.call(ax), Y.call(ay))
	ms.dark.line_to(X.call(1.0), Y.call(0.0))
	ms.dark.move_to(X.call(ax), Y.call(ay))
	ms.dark.line_to(X.call(bx), Y.call(by))
	ms.dark.move_to(X.call(0.0), Y.call(1.0))
	ms.dark.line_to(X.call(bx), Y.call(by))
	ms.dark.line_to(X.call(1.0), Y.call(1.0))
	ms.tint_l.move_to(X.call(0.0), Y.call(1.0))
	ms.tint_l.line_to(X.call(bx), Y.call(by))
	ms.tint_l.line_to(X.call(ax), Y.call(ay))
	ms.tint_l.line_to(X.call(0.0), Y.call(0.1))
	ms.tint_l.close()
	ms.light.move_to(X.call(0.08), Y.call(0.82))
	ms.light.line_to(X.call(0.3), Y.call(0.92))
	if lod >= 1 and PageRand.hash01(x, y, z, 53) < 0.5:
		var gx: float = X.call(0.2 + PageRand.hash01(x, y, 54) * 0.6)
		var gy: float = Y.call(0.2 + PageRand.hash01(x, y, 55) * 0.6)
		var r := k * 0.09
		ms.white.add(PackedVector2Array([
			Vector2(gx + r, gy), Vector2(gx + r * 0.15, gy + r * 0.15), Vector2(gx, gy + r), Vector2(gx - r * 0.15, gy + r * 0.15),
			Vector2(gx - r, gy), Vector2(gx - r * 0.15, gy - r * 0.15), Vector2(gx, gy - r), Vector2(gx + r * 0.15, gy - r * 0.15)]), true)


static func _leaf(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, lod: int) -> void:
	var k := p.k
	var rows := 2 if lod == 0 else 3
	var per := 2 if lod == 0 else 3
	var r := 0.5 / per + 0.03
	for ri in rows:
		var w := (ri + 0.75) / rows
		var off := ((y * rows + ri) & 1) * (0.5 / per)
		for i in range(-1, per):
			var u := (i + 0.5) / per + off
			if u < -0.1 or u > 1.1:
				continue
			var cx := p.ox + (x + u) * k
			var cy := p.oy - (y + w) * k
			var rr := r * k * (0.9 + 0.2 * PageRand.hash01(x, y, ri * 7 + i, 60))
			var a0 := 0.15 + PageRand.hs(x, y, ri, i) * 0.1
			ms.dark.move_to(cx + cos(a0) * rr, cy + sin(a0) * rr)
			ms.dark.arc(cx, cy, rr, a0, PI - a0)
			if lod >= 1:
				ms.light.move_to(cx - rr * 0.5, cy - rr * 0.35)
				ms.light.quad_to(cx, cy - rr * 0.75, cx + rr * 0.45, cy - rr * 0.4)
			if PageRand.hash01(x, y, ri * 5 + i, z) < 0.2:
				ms.tint_d.circle(cx, cy, rr * 0.8)


static func _marble(ms: MarkSet, p: PageEnv.Proj, x: int, y: int, z: int, below: bool, left: bool, lod: int, v: int) -> void:
	var a := 0.35 * p.px
	var k := p.k
	if below and PageRand.hash01(x, y, z, 69) < 0.6:
		_hmark(ms.light, p, x, x + 1, y, a, 11, v)
	if left and PageRand.hash01(x, y, z, 70) < 0.35:
		_vmark(ms.light, p, x, y, y + 1, a, x * 3 + y * 7, v)
	if lod == 0:
		return
	# Veins run on long diagonals anchored in the world, wandering as they go, so they
	# continue from cell to cell and chunk to chunk.
	var fams := [[0.62, 2.7, 0.4, ms.dark], [-1.35, 3.9, 1.7, ms.fine]]
	for f in fams.size():
		var F: Array = fams[f]
		var fs: float = F[0]
		var fd: float = F[1]
		var fph: float = F[2]
		var path: PagePath = F[3]
		var seed := 900 + f * 31
		var lo := floori((x - 1 - fs * (y + 1) - fph) / fd) - 1
		var hi := ceili((x + 2 - fs * y - fph) / fd) + 1
		for n in range(mini(lo, hi), maxi(lo, hi) + 1):
			if PageRand.hash01(n, f, 71) > 0.7:
				continue
			var started := false
			for st in 7:
				var wy := y + st / 6.0
				var wx := n * fd + fph + fs * wy + 0.32 * PageRand.noise1(wy * 1.6 + n * 3.3, seed) + 0.1 * PageRand.noise1(wy * 5.1 + n, seed + 1)
				if wx < x - 0.02 or wx > x + 1.02:
					started = false
					continue
				var X := p.ox + wx * k
				var Y := p.oy - wy * k
				if not started:
					path.move_to(X, Y)
				else:
					path.line_to(X, Y)
				started = true
	if lod == 2 and PageRand.hash01(x, y, z, 72) < 0.25:
		var bx := x + 0.2 + PageRand.hash01(x, y, 73) * 0.5
		var by := y + 0.2 + PageRand.hash01(x, y, 74) * 0.5
		ms.fine.move_to(p.ox + bx * k, p.oy - by * k)
		ms.fine.line_to(p.ox + (bx + 0.25) * k, p.oy - (by + PageRand.hs(x, y, 75) * 0.2) * k)


# ---------------------------------------------------------------- volume, seams, outlines

## Inner shade along the underside and right of each silhouette, a lit edge along the top.
static func _volume(pen: Pen, runs: Array) -> void:
	var p := pen.p
	var L := pen.L
	var env := pen.env
	var painter := pen.painter
	var shade := PagePath.new()
	var side := PagePath.new()
	var hi := PagePath.new()
	var capped := String(env.tones.pal.top) != "none"
	for r in runs:
		if r.side == PageWorld.BOTTOM:
			_rect_w(shade, p, r.x0, r.y0, r.x1, r.y0 + 0.24)
		elif r.side == PageWorld.RIGHT:
			_rect_w(side, p, r.x0 - 0.13, r.y0, r.x0, r.y1)
		elif r.side == PageWorld.TOP and not capped:
			_hmark(hi, p, r.x0 + 0.04, r.x1 - 0.04, r.y0 - 0.07, 0.4 * p.px, 12, pen.variant)
		elif r.side == PageWorld.TOP:
			_hmark(hi, p, r.x0 + 0.04, r.x1 - 0.04, r.y0 - 0.16, 0.4 * p.px, 13, pen.variant)
	env.pat_path(painter, shade, PageEnv.CROSS, 0.45 * L.density + 0.1, p)
	env.pat_path(painter, side, PageEnv.HATCH, 0.4 * L.density + 0.1, p)
	painter.stroke_path(hi, maxf(1.0, 1.6 * p.px), PageTones.alpha(L.light, 0.45 * L.density + 0.1))


static func _seams(pen: Pen, rx0: float, ry0: float, rx1: float, ry1: float) -> void:
	var p := pen.p
	var L := pen.L
	var list: PackedInt32Array = pen.env.world.seams[pen.z]
	if list.is_empty():
		return
	var c := PageTones.alpha(L.ink, 0.7)
	for i in range(0, list.size(), 4):
		var x0 := list[i]
		var y0 := list[i + 1]
		var x1 := list[i + 2]
		var y1 := list[i + 3]
		if x1 < rx0 or x0 > rx1 or y1 < ry0 or y0 > ry1:
			continue
		var pts := PageInk.line_pts(p.ox + x0 * p.k, p.oy - y0 * p.k, p.ox + x1 * p.k, p.oy - y1 * p.k, 0.6 * p.px, x0 * 131 + y0 * 71 + pen.z, pen.variant, 6.0 * p.px, 0.0, 0.6, p.px)
		pen.painter.ribbon(pts, L.outline_w * 0.55 * p.px, x0 * 17 + y0, c)


static func _outlines(pen: Pen, runs: Array) -> void:
	var p := pen.p
	var L := pen.L
	if runs.is_empty():
		return
	var w := L.outline_w * p.px
	var amp := (0.75 + 0.5 * (1.0 - L.k)) * p.px
	var c := PageTones.alpha(L.ink, 0.93)
	for r in runs:
		var length := maxi(r.x1 - r.x0, r.y1 - r.y0) * p.k
		var pts := PageInk.line_pts(p.ox + r.x0 * p.k, p.oy - r.y0 * p.k, p.ox + r.x1 * p.k, p.oy - r.y1 * p.k, amp * (1.25 if length > 300.0 else 1.0), r.seed, pen.variant, 6.0 * p.px, 2.4 * p.px, 0.6, p.px)
		pen.painter.ribbon(pts, w, r.seed, c)


# ---------------------------------------------------------------- top edging

static func _top_caps(pen: Pen, runs: Array) -> void:
	var p := pen.p
	var L := pen.L
	var env := pen.env
	var painter := pen.painter
	var top := String(env.tones.pal.top)
	var W := env.world
	var band := PagePath.new()
	var blades := PagePath.new()
	var blades_light := PagePath.new()
	var accent := PagePath.new()
	var accent2 := PagePath.new()
	var trim := PagePath.new()
	var q := p.k / p.dpr
	var z := pen.z
	var any := false
	for r in runs:
		if r.side != PageWorld.TOP:
			continue
		var y: int = r.y0
		for x in range(r.x0, r.x1):
			var mt := W.mat(x, y - 1, z)
			if not _capped(mt):
				if top != "none" and mt == Level.MAT_BRASS:
					_hmark(trim, p, x, x + 1, y - 0.04, 0.3 * p.px, 14, pen.variant)
				continue
			any = true
			var start_cap: bool = x == r.x0 or not _capped(W.mat(x - 1, y - 1, z))
			var end_cap: bool = x == r.x1 - 1 or not _capped(W.mat(x + 1, y - 1, z))
			match top:
				"grass":
					_grass_cap(band, blades, blades_light, accent, p, x, y, z, q, L.density, pen.variant)
				"moss":
					_moss_cap(band, blades, accent, p, x, y, z, q, start_cap)
				"leaves":
					_leaves_cap(band, blades, accent, accent2, p, x, y, q)
				"snow":
					_snow_cap(band, blades, p, x, y, z, end_cap)
				"carpet":
					_carpet_cap(band, trim, accent, p, x, y, start_cap, end_cap, q, pen.variant)
				"none":
					_hmark(trim, p, x, x + 1, y - 0.05, 0.3 * p.px, 15, pen.variant)
	var T := env.tones
	var trim_c := PageTones.alpha(PageTones.mix(T.gold_light, L.tone, 0.4), 0.6 * L.density + 0.2)
	var trim_w := maxf(1.0, 1.4 * p.px)
	if not any and top != "none":
		if top != "carpet":
			painter.stroke_path(trim, trim_w, trim_c)
		return
	var top_c := L.top
	var ink := L.ink
	match top:
		"grass":
			painter.fill_path(band, PageTones.alpha(top_c, 0.9))
			painter.stroke_path(blades, maxf(0.8, 1.15 * p.px), PageTones.alpha(PageTones.mix(top_c, ink, 0.45), 0.85))
			painter.stroke_path(blades_light, maxf(0.8, 1.15 * p.px), PageTones.alpha(PageTones.mix(top_c, T.paper, 0.35), 0.7))
			painter.fill_path(accent, PageTones.alpha(PageTones.mix(T.rubric, L.tone, 0.25 * L.k), 0.9))
		"moss":
			painter.fill_path(band, PageTones.alpha(top_c, 0.88))
			painter.stroke_path(blades, maxf(0.8, 1.1 * p.px), PageTones.alpha(PageTones.mix(top_c, ink, 0.5), 0.8))
			painter.fill_path(accent, PageTones.alpha(PageTones.mix(top_c, ink, 0.4), 0.7))
		"leaves":
			painter.fill_path(band, PageTones.alpha(top_c, 0.9))
			painter.fill_path(accent, PageTones.alpha(PageTones.mix(PageTones.mix(T.rubric, top_c, 0.3), L.tone, 0.3 * L.k), 0.9))
			painter.fill_path(accent2, PageTones.alpha(PageTones.mix(PageTones.mix(T.gold, top_c, 0.3), L.tone, 0.3 * L.k), 0.9))
			painter.stroke_path(blades, maxf(0.7, 0.9 * p.px), PageTones.alpha(PageTones.mix(top_c, ink, 0.6), 0.75))
		"snow":
			painter.fill_path(band, Color8(235, 238, 250, 242) if T.inv else Color8(252, 250, 246, 242))
			painter.stroke_path(blades, maxf(0.8, p.px), PageTones.alpha(PageTones.mix(ink, Color8(120, 140, 170), 0.5), 0.7))
		"carpet":
			painter.fill_path(band, PageTones.alpha(PageTones.mix(top_c, L.tone, 0.15 + 0.2 * L.k), 0.95))
			painter.stroke_path(trim, maxf(1.0, 1.3 * p.px), PageTones.alpha(PageTones.mix(T.gold, L.tone, 0.3 * L.k), 0.9))
			painter.stroke_path(accent, maxf(0.6, 0.8 * p.px), PageTones.alpha(PageTones.mix(top_c, ink, 0.55), 0.6))
		"none":
			painter.stroke_path(trim, trim_w, trim_c)
	if top != "none" and top != "carpet":
		painter.stroke_path(trim, trim_w, trim_c)


static func _grass_cap(band: PagePath, blades: PagePath, light: PagePath, flowers: PagePath, p: PageEnv.Proj, x: int, y: int, z: int, q: float, density: float, v: int) -> void:
	var k := p.k
	var X := func(u: float) -> float: return p.ox + (x + u) * k
	var Y := func(w: float) -> float: return p.oy - w * k
	band.move_to(X.call(0.0), Y.call(y - 0.12 - PageRand.hash01(x, y, 1) * 0.04))
	for i in 7:
		var u := i / 6.0
		band.line_to(X.call(u), Y.call(y + 0.035 + PageRand.hash01(PageInk.jround((x + u) * 6.0), y, 2) * 0.05))
	band.line_to(X.call(1.0), Y.call(y - 0.12 - PageRand.hash01(x + 1, y, 1) * 0.04))
	for i in range(5, 0, -1):
		var u := i / 6.0
		band.line_to(X.call(u), Y.call(y - 0.1 - PageRand.hash01(PageInk.jround((x + u) * 6.0), y, 3) * 0.1))
	band.close()
	var n := maxi(4, PageInk.jround((q / 4.2) * (0.45 + 0.55 * density)))
	for i in n:
		var u := (i + PageRand.hash01(x, y, i, 4)) / n
		var hgt := (0.07 + PageRand.hash01(x, y, i, 5) * 0.16) * (1.7 if PageRand.hash01(x, y, i, 6) < 0.12 else 1.0)
		var lean := PageRand.hs(x, y, i, 7) * 0.08 + PageRand.hs(x, y, i, v + 30) * 0.012
		var bx: float = X.call(u)
		var by: float = Y.call(y + 0.01)
		var tx: float = X.call(u + lean)
		var ty: float = Y.call(y + hgt)
		var path := light if PageRand.hash01(x, y, i, 8) < 0.25 else blades
		path.move_to(bx, by)
		path.quad_to(bx + (tx - bx) * 0.2, by + (ty - by) * 0.6, tx, ty)
	if z <= 2 and PageRand.hash01(x, y, z, 9) < 0.12 and q > 26.0:
		var fx: float = X.call(0.2 + PageRand.hash01(x, y, 10) * 0.6)
		var fy: float = Y.call(y + 0.13 + PageRand.hash01(x, y, 11) * 0.08)
		var r := maxf(1.2, k * 0.035)
		blades.move_to(fx, Y.call(y))
		blades.line_to(fx, fy)
		flowers.circle(fx, fy, r)


static func _moss_cap(band: PagePath, lines: PagePath, drips: PagePath, p: PageEnv.Proj, x: int, y: int, z: int, q: float, start_cap: bool) -> void:
	var k := p.k
	var X := func(u: float) -> float: return p.ox + (x + u) * k
	var Y := func(w: float) -> float: return p.oy - w * k
	var bumps := maxi(2, PageInk.jround(q / 18.0))
	var base := y - 0.1
	band.move_to(X.call(0.0), Y.call(base - (0.0 if start_cap else 0.02)))
	for i in bumps:
		var u0 := float(i) / bumps
		var u1 := float(i + 1) / bumps
		var hgt := 0.08 + PageRand.hash01(x * 8 + i, y, z, 20) * 0.07
		band.quad_to(X.call((u0 + u1) / 2.0), Y.call(y + hgt * 1.6), X.call(u1), Y.call(y + 0.01))
	band.line_to(X.call(1.0), Y.call(base))
	band.line_to(X.call(0.0), Y.call(base))
	band.close()
	for i in bumps:
		var u := (i + 0.5) / bumps
		lines.move_to(X.call(u - 0.12 / bumps), Y.call(y + 0.03))
		lines.quad_to(X.call(u), Y.call(y + 0.09), X.call(u + 0.12 / bumps), Y.call(y + 0.04))
	var nd := 1 if PageRand.hash01(x, y, z, 21) < 0.5 else 2
	for i in nd:
		var u := 0.15 + PageRand.hash01(x, y, i, 22) * 0.7
		var length := 0.1 + PageRand.hash01(x, y, i, 23) * 0.22
		var w := 0.035
		drips.move_to(X.call(u - w), Y.call(base + 0.02))
		drips.quad_to(X.call(u - w * 0.6), Y.call(base - length), X.call(u), Y.call(base - length - 0.03))
		drips.quad_to(X.call(u + w * 0.6), Y.call(base - length), X.call(u + w), Y.call(base + 0.02))
		drips.close()


static func _leaves_cap(band: PagePath, veins: PagePath, red: PagePath, yellow: PagePath, p: PageEnv.Proj, x: int, y: int, q: float) -> void:
	var k := p.k
	var X := func(u: float) -> float: return p.ox + (x + u) * k
	var Y := func(w: float) -> float: return p.oy - w * k
	band.move_to(X.call(0.0), Y.call(y - 0.07))
	for i in 6:
		band.line_to(X.call(i / 5.0), Y.call(y + 0.02 + PageRand.hash01(x * 5 + i, y, 30) * 0.035))
	band.line_to(X.call(1.0), Y.call(y - 0.07))
	band.close()
	var n := maxi(2, PageInk.jround(q / 14.0))
	for i in n:
		var u := (i + PageRand.hash01(x, y, i, 31)) / n
		var cx: float = X.call(u)
		var cy: float = Y.call(y + 0.04 + PageRand.hash01(x, y, i, 32) * 0.05)
		var length := k * (0.09 + PageRand.hash01(x, y, i, 33) * 0.06)
		var ang := PageRand.hs(x, y, i, 34) * 0.9
		var ca := cos(ang)
		var sa := sin(ang)
		var target := red if PageRand.hash01(x, y, i, 35) < 0.45 else yellow
		target.move_to(cx - ca * length, cy - sa * length)
		target.quad_to(cx - sa * length * 0.45, cy + ca * length * 0.45, cx + ca * length, cy + sa * length)
		target.quad_to(cx + sa * length * 0.45, cy - ca * length * 0.45, cx - ca * length, cy - sa * length)
		target.close()
		veins.move_to(cx - ca * length * 0.8, cy - sa * length * 0.8)
		veins.line_to(cx + ca * length * 0.8, cy + sa * length * 0.8)


static func _snow_cap(band: PagePath, lines: PagePath, p: PageEnv.Proj, x: int, y: int, z: int, end_cap: bool) -> void:
	var k := p.k
	var X := func(u: float) -> float: return p.ox + (x + u) * k
	var Y := func(w: float) -> float: return p.oy - w * k
	band.move_to(X.call(0.0), Y.call(y - 0.12))
	band.quad_to(X.call(0.25), Y.call(y + 0.1 + PageRand.hash01(x, y, z, 40) * 0.05), X.call(0.5), Y.call(y + 0.09))
	band.quad_to(X.call(0.75), Y.call(y + 0.1 + PageRand.hash01(x + 1, y, z, 40) * 0.05), X.call(1.0), Y.call(y + (0.0 if end_cap else 0.08)))
	band.line_to(X.call(1.0), Y.call(y - 0.1))
	band.line_to(X.call(0.5), Y.call(y - 0.16 - PageRand.hash01(x, y, 41) * 0.08))
	band.close()
	lines.move_to(X.call(0.05), Y.call(y + 0.08))
	lines.quad_to(X.call(0.5), Y.call(y + 0.13), X.call(0.95), Y.call(y + 0.08))


static func _carpet_cap(band: PagePath, trim: PagePath, pile: PagePath, p: PageEnv.Proj, x: int, y: int, start_cap: bool, end_cap: bool, q: float, v: int) -> void:
	var x0 := x + 0.06 if start_cap else float(x)
	var x1 := x + 0.94 if end_cap else x + 1.0
	_rect_w(band, p, x0, y - 0.13, x1, y + 0.03)
	_hmark(trim, p, x0, x1, y + 0.02, 0.2 * p.px, 16, v)
	_hmark(trim, p, x0, x1, y - 0.11, 0.2 * p.px, 17, v)
	var n := maxi(3, PageInk.jround(q / 9.0))
	for i in n:
		var u := x0 + ((i + 0.5) / n) * (x1 - x0)
		pile.move_to(p.ox + u * p.k, p.oy - (y - 0.09) * p.k)
		pile.line_to(p.ox + (u + 0.02) * p.k, p.oy - (y - 0.02) * p.k)
	for e in [[start_cap, x0], [end_cap, x1]]:
		if not e[0]:
			continue
		var ex: float = e[1]
		for i in 4:
			var fy := y - 0.11 + i * 0.035
			trim.move_to(p.ox + ex * p.k, p.oy - fy * p.k)
			trim.line_to(p.ox + (ex + (-0.05 if ex == x0 else 0.05)) * p.k, p.oy - (fy - 0.02) * p.k)


# ---------------------------------------------------------------- thorns

## A bramble of thorny stems with vermilion tips, filling one cell (a spiked cog in the
## clocktower).
static func draw_thorn(pen: Pen, x: int, y: int) -> void:
	if pen.env.tones.id == "clock":
		_cog_thorn(pen, x, y)
		return
	var p := pen.p
	var L := pen.L
	var T := pen.env.tones
	var painter := pen.painter
	var k := p.k
	var seed := x * 7919 + y * 104729 + pen.z * 31
	var count := 3 + floori(PageRand.hash01(seed, 1) * 2.0)
	var stems: Array = []
	var spikes := PagePath.new()
	var tips := PagePath.new()
	for s in count:
		var u0 := 0.1 + PageRand.hash01(seed, s, 2) * 0.8
		var u1 := u0 + PageRand.hs(seed, s, 3) * 0.45
		var top := 0.55 + PageRand.hash01(seed, s, 4) * 0.4
		var ctrl := PackedVector2Array([
			Vector2(p.ox + (x + u0) * k, p.oy - y * k),
			Vector2(p.ox + (x + u0 + PageRand.hs(seed, s, 5) * 0.3) * k, p.oy - (y + top * 0.45) * k),
			Vector2(p.ox + (x + (u0 + u1) / 2.0 + PageRand.hs(seed, s, 6) * 0.2) * k, p.oy - (y + top * 0.8) * k),
			Vector2(p.ox + (x + u1) * k, p.oy - (y + top) * k)])
		var pts := PageInk.curve_pts(ctrl, 0.5 * p.px, seed + s, pen.variant, 5.0 * p.px)
		stems.append(PageInk.ribbon(pts, maxf(1.2, k * 0.05 * (0.8 + 0.4 * (1.0 - L.k))), seed + s, 0.9))
		var n := pts.size()
		var every := maxi(2, PageInk.jround(n / 5.0))
		var i := every
		while i < n - 1:
			var a := pts[i]
			var tv := pts[i + 1] - pts[i - 1]
			var l := tv.length()
			if l == 0.0:
				l = 1.0
			tv /= l
			var sd := 1.0 if (i / every) % 2 == 0 else -1.0
			var length := k * (0.12 + PageRand.hash01(seed, s, i) * 0.07)
			var nv := Vector2(-tv.y * sd, tv.x * sd)
			var bw := k * 0.035
			var tip := a + nv * length + tv * length * 0.5
			spikes.add(PackedVector2Array([a - tv * bw, tip, a + tv * bw]), true)
			if PageRand.hash01(seed, s, i, 9) < 0.85:
				tips.circle(tip.x, tip.y, maxf(1.0, k * 0.026))
			i += every
		if PageRand.hash01(seed, s, 10) < 0.7:
			var e := pts[n - 1]
			tips.add(PageInk.blob_pts(e.x, e.y, maxf(1.6, k * 0.055), 0.25, seed + s * 3, pen.variant, 8), true)
	var ink := PageTones.mix(T.ink, L.ink, 0.6)
	var stem_c := PageTones.mix(ink, T.paper, 0.15) if T.inv else PageTones.mix(ink, Color8(20, 8, 12), 0.3)
	stem_c.a = 0.95
	for st in stems:
		painter.strip(st[0], st[1], stem_c)
	painter.fill_path(spikes, stem_c)
	painter.fill_path(tips, PageTones.alpha(PageTones.mix(T.rubric, L.tone, 0.35 * L.k), 0.95))


## The clocktower's hazard: a brass wheel whose teeth are filed into vermilion spikes, with
## a dark hub and spoke windows. Each cell turns its cog to its own angle.
static func _cog_thorn(pen: Pen, x: int, y: int) -> void:
	var p := pen.p
	var L := pen.L
	var T := pen.env.tones
	var painter := pen.painter
	var lv := pen.env.world.lv
	# Only the front-most cog of a cell is drawn; the ones behind would only blur its spikes.
	if pen.z > 0 and lv.cells[x + lv.w * (y + lv.h * (pen.z - 1))] == Level.MAT_THORN:
		return
	var k := p.k
	var seed := x * 7919 + y * 104729 + pen.z * 31
	var cx := p.ox + (x + 0.5) * k
	var cy := p.oy - (y + 0.47) * k
	var n := 8
	var r_tip := k * (0.49 - 0.03 * PageRand.hash01(seed, 1))
	var r_body := k * 0.29
	var r_root := r_body * 0.97
	var rot := PageRand.hash01(seed, 2) * TAU
	var half := (PI / n) * 0.56
	var body := PackedVector2Array()
	var q := 0
	for i in n:
		var a := rot + float(i) / n * TAU
		var a0 := a - half
		var a1 := a + half
		var am := a + PI / n
		q += 1
		var rt := r_tip * (1.0 + PageRand.hs(seed, q, pen.variant) * 0.025)
		body.append(Vector2(cx + cos(a0) * r_body, cy + sin(a0) * r_body))
		body.append(Vector2(cx + cos(a) * rt, cy + sin(a) * rt))
		body.append(Vector2(cx + cos(a1) * r_body, cy + sin(a1) * r_body))
		body.append(Vector2(cx + cos(am) * r_root, cy + sin(am) * r_root))
	var brass_base := PageTones.mix(T.mat_color("brass"), Color8(255, 236, 170), 0.0 if T.inv else 0.08)
	var brass := PageTones.mix(PageTones.mix(brass_base, L.tone, 0.15 + 0.45 * L.k), T.paper, 0.3 * L.k)
	# A brass wheel whose teeth are filed into vermilion spikes.
	painter.fill(body, PageTones.alpha(PageTones.mix(PageTones.mix(T.rubric, Color8(236, 96, 60), 0.2), L.tone, 0.4 * L.k), 0.97))
	var wheel := PageInk.circle_pts(cx, cy, r_root, 2.0)
	painter.fill(wheel, PageTones.alpha(brass, 0.97))
	# Shade the lower right of the wheel with hatching.
	var shade := PageInk.circle_pts(cx + k * 0.14, cy + k * 0.14, k * 0.26, 2.0)
	for part in Geometry2D.intersect_polygons(wheel, shade):
		pen.env.pat(painter, part, PageEnv.HATCH, 0.55 + 0.3 * (1.0 - L.k), p)
	var ink := PageTones.mix(T.ink, L.ink, 0.6)
	painter.stroke(body, maxf(1.0, L.outline_w * p.px * 0.6), PageTones.alpha(ink, 0.92), true)
	# Hub ring, spoke windows and the axle.
	painter.stroke(PageInk.circle_pts(cx, cy, k * 0.17, 2.0), maxf(0.8, L.outline_w * p.px * 0.45), PageTones.alpha(ink, 0.92), true)
	var hc := PageTones.alpha(ink, 0.85)
	for i in 5:
		var a := rot * 1.7 + float(i) / 5 * TAU
		painter.fill(PageInk.circle_pts(cx + cos(a) * k * 0.17, cy + sin(a) * k * 0.17, k * 0.035, 2.0), hc)
	painter.fill(PageInk.circle_pts(cx, cy, k * 0.06, 2.0), hc)
	# A brass glint on the axle.
	painter.fill(PageInk.circle_pts(cx - k * 0.02, cy - k * 0.02, maxf(0.8, k * 0.022), 2.0), PageTones.alpha(PageTones.mix(brass_base, Color8(255, 250, 230), 0.6), 0.85))

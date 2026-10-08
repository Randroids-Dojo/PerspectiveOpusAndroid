class_name PageSketch
extends RefCounted
## A small drawing helper for illustrations placed in the world (sketch.ts): local units
## are world units relative to a base point (y up), scaled by `s`. Every call takes the
## next seed so a drawing is the same stroke for stroke each time it is made, and the
## boil index nudges the wobble.
##
## Fills are a Color or a pattern (an int, PageEnv.HATCH and friends).

var painter: PagePainter
var env: PageEnv
var p: PageEnv.Proj
var T: PageTones
var L: PageTones.Layer
var z := 0
var s := 1.0
var bx := 0.0
var by := 0.0
var k := 1.0
var px := 1.0
var boil := 0
var seed := 0
var n := 0
## Mirror horizontally (local u flips).
var flip := 1.0
## Outline weight multiplier.
var weight := 0.85
## Depth tint amount for colours (0 keeps colours pure).
var tint_amt := 1.0
## While set, blots are clipped to this polygon (device pixels).
var _clip := PackedVector2Array()
var _clipping := false


func setup(painter_: PagePainter, env_: PageEnv, p_: PageEnv.Proj, bx_: float, by_: float, z_: int, s_: float, seed_: int, boil_: int) -> PageSketch:
	painter = painter_
	env = env_
	p = p_
	T = env_.tones
	z = z_
	L = env_.tones.tone_at(z_)
	s = s_
	bx = bx_
	by = by_
	k = p_.k
	px = p_.px
	boil = boil_
	seed = PageRand.i32(seed_)
	if seed >= 0x80000000:
		seed -= 0x100000000
	n = 0
	flip = 1.0
	weight = 0.85
	tint_amt = 1.0
	_clipping = false
	return self


func X(u: float) -> float:
	return p.ox + (bx + u * s * flip) * k


func Y(v: float) -> float:
	return p.oy - (by + v * s) * k


func D(u: float) -> float:
	return u * s * k


func next() -> int:
	n += 1
	var v := (seed * 31 + n * 977) & 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


func col(c: Color, amount: float = 1.0) -> Color:
	return T.depth_tint(c, z + 0.5, amount * tint_amt)


func ink_color() -> Color:
	return L.ink


func lw(m: float = 1.0) -> float:
	return maxf(0.7, L.outline_w * weight * px * m * minf(1.3, maxf(0.65, s)))


func amp(m: float = 1.0) -> float:
	return 0.55 * px * m


func darker(c: Color, t: float = 0.45) -> Color:
	return T.depth_tint(PageTones.mix(c, T.paper_shade if T.inv else T.ink, t), z + 0.5, tint_amt)


func lighter(c: Color, t: float = 0.45) -> Color:
	return T.depth_tint(PageTones.mix(c, Color8(255, 250, 236), t), z + 0.5, tint_amt)


func _dev(ctrl: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(ctrl.size() / 2)
	for i in out.size():
		out[i] = Vector2(X(ctrl[i * 2]), Y(ctrl[i * 2 + 1]))
	return out


## A smooth closed (or open) path through local control points, in device pixels.
func pts(ctrl: Array, closed: bool, amp_m: float = 1.0) -> PackedVector2Array:
	return PageInk.curve_pts(_dev(ctrl), amp(amp_m), next(), boil, maxf(3.0, 5.0 * px), closed)


## A polygon with wobbly straight edges through local corner points, in device pixels.
func poly(ctrl: Array, closed: bool, amp_m: float = 1.0) -> PackedVector2Array:
	var dev := _dev(ctrl)
	var m := dev.size()
	var out := PackedVector2Array()
	var segs := m if closed else m - 1
	for i in segs:
		var j := (i + 1) % m
		var tmp := PageInk.line_pts(dev[i].x, dev[i].y, dev[j].x, dev[j].y, amp(amp_m) * 0.7, next(), boil, 6.0 * px, 0.0, 0.4, px)
		tmp[0] = dev[i]
		for q in tmp.size() - 1:
			out.append(tmp[q])
	if not closed:
		out.append(dev[m - 1])
	return out


func _fill(P: PackedVector2Array, fill: Variant, a: float, aa: bool = true) -> void:
	if fill is Color:
		var c: Color = fill
		painter.fill(P, Color(c.r, c.g, c.b, c.a * a), aa)
	elif fill is int:
		env.pat(painter, P, fill, a, p)


## Fills a smooth closed shape (or a polygon with `poly`), then inks its outline.
func shape(ctrl: Array, fill: Variant, lw_m: float = 1.0, alpha_: float = 0.95, outline: bool = true, amp_m: float = 1.0, misreg: bool = true, is_poly: bool = false) -> void:
	var P := poly(ctrl, true, amp_m) if is_poly else pts(ctrl, true, amp_m)
	if fill != null:
		if misreg:
			# The wash is laid a hair off the line, as a painter's brush would be.
			_fill(PageInk.shifted(P, 0.8 * px, 0.5 * px), fill, alpha_)
		else:
			_fill(P, fill, alpha_)
	if outline and lw_m > 0.0:
		painter.ring(P, lw(lw_m), next(), PageTones.alpha(L.ink, 0.92))


## Shorthand for polygon shapes without misregistration (the most common call).
func pshape(ctrl: Array, fill: Variant, lw_m: float = 1.0, amp_m: float = 1.0) -> void:
	shape(ctrl, fill, lw_m, 0.95, true, amp_m, false, true)


## Fills a closed region with a pattern or colour without an outline.
func region(ctrl: Array, fill: Variant, a: float, is_poly: bool = false) -> void:
	var P := poly(ctrl, true, 0.4) if is_poly else pts(ctrl, true, 0.6)
	_fill(P, fill, a, false)


## Runs `fn` with blots clipped to a closed shape (shading inside a form).
func clip(ctrl: Array, fn: Callable, is_poly: bool = false) -> void:
	_clip = poly(ctrl, true, 0.4) if is_poly else pts(ctrl, true, 0.5)
	_clipping = true
	fn.call()
	_clipping = false


## Fills a local-space ellipse (shading inside a clip).
func blot(cu: float, cv: float, ru: float, rv: float, fill: Variant, a: float) -> void:
	var e := PageInk.arc_pts(X(cu), Y(cv), maxf(0.5, D(ru)), maxf(0.5, D(rv)), 0.0, 0.0, TAU, false, 4.0)
	e.resize(e.size() - 1)
	if _clipping:
		for part in Geometry2D.intersect_polygons(_clip, e):
			_fill(part, fill, a, false)
	else:
		_fill(e, fill, a, false)


## A nib stroke along a smooth open curve.
func line(ctrl: Array, lw_m: float = 1.0, color: Variant = null, a: float = 0.92, amp_m: float = 1.0) -> void:
	var P := pts(ctrl, false, amp_m)
	var c: Color = color if color != null else L.ink
	painter.ribbon(P, lw(lw_m), next(), Color(c.r, c.g, c.b, a))


## A straight nib stroke.
func seg(u0: float, v0: float, u1: float, v1: float, lw_m: float = 1.0, color: Variant = null, a: float = 0.92) -> void:
	var P := PageInk.line_pts(X(u0), Y(v0), X(u1), Y(v1), amp(), next(), boil, 5.0 * px, 0.0, 0.6, px)
	var c: Color = color if color != null else L.ink
	painter.ribbon(P, lw(lw_m), n, Color(c.r, c.g, c.b, a))


## Thin marks (hatching, grain) as straight local segments [u0, v0, u1, v1, ...].
func marks(segs: Array, color: Color, width_px: float, a: float) -> void:
	var w := maxf(0.6, width_px * px)
	var c := Color(color.r, color.g, color.b, a)
	for i in range(0, segs.size(), 4):
		painter.seg(X(segs[i]), Y(segs[i + 1]), X(segs[i + 2]), Y(segs[i + 3]), w, c)


## A wobbly ellipse, filled and outlined.
func ellipse(cu: float, cv: float, ru: float, rv: float, rot: float, fill: Variant, lw_m: float = 1.0, a: float = 0.95) -> void:
	var P := PageInk.ellipse_pts(X(cu), Y(cv), D(ru), D(rv), -rot * flip, amp(0.7), next(), boil)
	if fill != null:
		_fill(P, fill, a)
	if lw_m > 0.0:
		painter.ring(P, lw(lw_m), next(), PageTones.alpha(L.ink, 0.92))


## A plain filled circle (dots, berries, flecks).
func dot(cu: float, cv: float, r: float, color: Color, a: float = 1.0) -> void:
	painter.dot(X(cu), Y(cv), maxf(0.6, D(r)), Color(color.r, color.g, color.b, color.a * a))


## Radiating ink strokes for light (never a digital glow).
func rays(cu: float, cv: float, r0: float, r1: float, count: int, color: Color, a: float, phase: float = 0.0, width_px: float = 1.0) -> void:
	var w := maxf(0.7, width_px * px)
	var c := Color(color.r, color.g, color.b, a)
	var cx := X(cu)
	var cy := Y(cv)
	var d0 := D(r0)
	for i in count:
		var ang := phase + float(i) / count * TAU
		var j := 0.75 + 0.5 * (float((i * 7919 + seed) % 13) / 13.0)
		var d1 := D(r1 * j)
		painter.seg(cx + cos(ang) * d0, cy - sin(ang) * d0, cx + cos(ang) * d1, cy - sin(ang) * d1, w, c)

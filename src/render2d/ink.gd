class_name PageInk
extends RefCounted
## Ink primitives, the web build's ink.ts. Everything works in whatever space the caller
## draws in (device pixels for the world, local units for characters). Wobble is smooth
## noise along the stroke, seeded per stroke, and the boil index nudges the phases so a
## line redrawn on the next boil frame shifts a little without ever jumping.
##
## Strokes come back as point lists; ribbons and rings as their two sides, which the
## painter fills as an antialiased strip.

const TAU_ := TAU


## Math.round as JavaScript does it (halves go up).
static func jround(x: float) -> int:
	return floori(x + 0.5)


## Samples a wobbly straight stroke.
static func line_pts(x0: float, y0: float, x1: float, y1: float, amp: float, seed: int, boil: int, step: float = 7.0, over: float = 0.0, bow_k: float = 0.6, wl: float = 1.0) -> PackedVector2Array:
	var dx := x1 - x0
	var dy := y1 - y0
	var length := sqrt(dx * dx + dy * dy)
	if length == 0.0:
		length = 1e-6
	var ux := dx / length
	var uy := dy / length
	var nx := -uy
	var ny := ux
	var s := seed
	var b := boil
	var s0 := -over * (0.25 + 0.75 * PageRand.hash01(s, 11)) + PageRand.hs(s, b, 12) * amp * 0.5
	var s1 := length + over * (0.25 + 0.75 * PageRand.hash01(s, 13)) + PageRand.hs(s, b, 14) * amp * 0.5
	var n := maxi(2, mini(400, ceili((s1 - s0) / step) + 1))
	var p1 := PageRand.hash01(s, 1) * TAU + PageRand.hs(s, b, 2) * 0.9
	var p2 := PageRand.hash01(s, 3) * TAU + PageRand.hs(s, b, 4) * 1.3
	var f1 := 1.0 / ((34.0 + PageRand.hash01(s, 5) * 40.0) * wl)
	var f2 := 1.0 / ((9.0 + PageRand.hash01(s, 6) * 9.0) * wl)
	var bow := bow_k * PageRand.hs(s, 7) * amp
	var j0 := PageRand.hs(s, b, 15) * amp * 0.35
	var out := PackedVector2Array()
	out.resize(n)
	var inv := 1.0 / float(n - 1)
	for i in n:
		var t := float(i) * inv
		var d := s0 + (s1 - s0) * t
		var off := amp * (0.7 * sin(d * f1 + p1) + 0.3 * sin(d * f2 + p2)) + bow * sin(PI * t) + j0
		out[i] = Vector2(x0 + ux * d + nx * off, y0 + uy * d + ny * off)
	return out


## Samples a wobbly closed ellipse (optionally rotated).
static func ellipse_pts(cx: float, cy: float, rx: float, ry: float, rot: float, amp: float, seed: int, boil: int, n: int = 0) -> PackedVector2Array:
	var count := n if n > 0 else maxi(12, mini(96, jround(maxf(rx, ry) * 6.3 / 5.0)))
	var c := cos(rot)
	var s := sin(rot)
	var p1 := PageRand.hash01(seed, 1) * TAU + PageRand.hs(seed, boil, 2) * 0.8
	var p2 := PageRand.hash01(seed, 3) * TAU + PageRand.hs(seed, boil, 4) * 1.2
	var k1 := 2.0 + floorf(PageRand.hash01(seed, 5) * 2.0)
	var k2 := 5.0 + floorf(PageRand.hash01(seed, 6) * 3.0)
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var a := float(i) / float(count) * TAU
		var w := amp * (0.65 * sin(a * k1 + p1) + 0.35 * sin(a * k2 + p2))
		var ex := cos(a) * (rx + w)
		var ey := sin(a) * (ry + w)
		out[i] = Vector2(cx + ex * c - ey * s, cy + ex * s + ey * c)
	return out


## Samples a smooth Catmull-Rom curve through control points, with wobble.
static func curve_pts(ctrl: PackedVector2Array, amp: float, seed: int, boil: int, step: float = 6.0, closed: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := ctrl.size()
	if m < 2:
		return out
	var segs := m if closed else m - 1
	var p1 := PageRand.hash01(seed, 1) * TAU + PageRand.hs(seed, boil, 2) * 0.9
	var p2 := PageRand.hash01(seed, 3) * TAU + PageRand.hs(seed, boil, 4) * 1.2
	for sgi in segs:
		var a: Vector2
		var b: Vector2 = ctrl[sgi % m] if closed else ctrl[sgi]
		var c: Vector2
		var d: Vector2
		if closed:
			a = ctrl[(sgi - 1 + m) % m]
			c = ctrl[(sgi + 1) % m]
			d = ctrl[(sgi + 2) % m]
		else:
			a = ctrl[maxi(0, sgi - 1)]
			c = ctrl[mini(m - 1, sgi + 1)]
			d = ctrl[mini(m - 1, sgi + 2)]
		var seg_len := b.distance_to(c)
		var n := maxi(2, ceili(seg_len / step))
		var i0 := 0 if sgi == 0 else 1
		for i in range(i0, n + 1):
			if closed and sgi == segs - 1 and i == n:
				break
			var t := float(i) / float(n)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3))
	if amp > 0.0:
		var n := out.size()
		var res := PackedVector2Array()
		res.resize(n)
		var dist := 0.0
		for i in n:
			var q0 := out[maxi(0, i - 1)]
			var q1 := out[mini(n - 1, i + 1)]
			var tv := q1 - q0
			var l := tv.length()
			if l == 0.0:
				l = 1.0
			tv /= l
			if i > 0:
				dist += out[i].distance_to(out[i - 1])
			var off := amp * (0.7 * sin(dist / 31.0 + p1) + 0.3 * sin(dist / 11.0 + p2))
			res[i] = Vector2(out[i].x - tv.y * off, out[i].y + tv.x * off)
		return res
	return out


## The two sides of a tapered nib ribbon along `pts`: width swells and thins like a pen
## under changing pressure. Returns [A, B].
static func ribbon(pts: PackedVector2Array, w: float, seed: int, taper: float = 0.5) -> Array:
	var n := pts.size()
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	if n < 2:
		return [A, B]
	A.resize(n)
	B.resize(n)
	var total := 0.0
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
	var tl := maxf(1e-3, minf(total * 0.35, w * 5.0)) * taper
	var ph := PageRand.hash01(seed, 21) * TAU
	var fr := 1.0 / ((7.0 + PageRand.hash01(seed, 22) * 12.0) * maxf(1.0, w))
	var d := 0.0
	for i in n:
		var tv := pts[mini(n - 1, i + 1)] - pts[maxi(0, i - 1)]
		var l := tv.length()
		if l == 0.0:
			l = 1.0
		tv /= l
		if i > 0:
			d += pts[i].distance_to(pts[i - 1])
		var k := 0.78 + 0.3 * sin(d * fr + ph)
		if tl > 0.0:
			var e := minf(d, total - d)
			if e < tl:
				k *= 0.3 + 0.7 * (e / tl)
		var hw := w * 0.5 * k
		var p := pts[i]
		A[i] = Vector2(p.x - tv.y * hw, p.y + tv.x * hw)
		B[i] = Vector2(p.x + tv.y * hw, p.y - tv.x * hw)
	return [A, B]


## The two sides of a closed ribbon (a ring) around a closed point loop. Returns [A, B].
static func ring(pts: PackedVector2Array, w: float, seed: int) -> Array:
	var n := pts.size()
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	if n < 3:
		return [A, B]
	A.resize(n)
	B.resize(n)
	var ph := PageRand.hash01(seed, 31) * TAU
	var k1 := 2.0 + floorf(PageRand.hash01(seed, 32) * 3.0)
	for i in n:
		var tv := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		var l := tv.length()
		if l == 0.0:
			l = 1.0
		tv /= l
		var k := 0.72 + 0.38 * (0.5 + 0.5 * sin(float(i) / float(n) * TAU * k1 + ph))
		var hw := w * 0.5 * k
		var p := pts[i]
		A[i] = Vector2(p.x - tv.y * hw, p.y + tv.x * hw)
		B[i] = Vector2(p.x + tv.y * hw, p.y - tv.x * hw)
	return [A, B]


## A closed noisy blob (blot, berry, splat) as a polygon.
static func blob_pts(cx: float, cy: float, r: float, rough: float, seed: int, boil: int = 0, n: int = 0) -> PackedVector2Array:
	var count := n if n > 0 else maxi(8, mini(40, jround(r * 1.2)))
	var p1 := PageRand.hash01(seed, 1) * TAU + PageRand.hs(seed, boil, 2) * 0.4
	var p2 := PageRand.hash01(seed, 3) * TAU + PageRand.hs(seed, boil, 4) * 0.6
	var p3 := PageRand.hash01(seed, 5) * TAU
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var a := float(i) / float(count) * TAU
		var rr := r * (1.0 + rough * (0.5 * sin(a * 3.0 + p1) + 0.3 * sin(a * 5.0 + p2) + 0.2 * sin(a * 9.0 + p3)))
		out[i] = Vector2(cx + cos(a) * rr, cy + sin(a) * rr)
	return out


## A four-pointed glint as two crossing tapered strokes (two quads).
static func glint_quads(x: float, y: float, r: float, rot: float = 0.0) -> Array:
	var w := r * 0.16
	var out: Array = []
	for k in 2:
		var a := rot + k * (PI / 2.0)
		var c := cos(a)
		var s := sin(a)
		out.append(PackedVector2Array([
			Vector2(x + c * r, y + s * r), Vector2(x - s * w, y + c * w),
			Vector2(x - c * r, y - s * r), Vector2(x + s * w, y - c * w)]))
	return out


## Points of a plain ellipse arc (ctx.ellipse / ctx.arc), including both ends.
static func arc_pts(cx: float, cy: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false, seg_px: float = 3.0) -> PackedVector2Array:
	var span := a1 - a0
	if ccw:
		if span > 0.0:
			span = fmod(span, TAU) - TAU if fmod(span, TAU) != 0.0 else -TAU
		if span < -TAU:
			span = -TAU
	else:
		if span < 0.0:
			span = fmod(span, TAU) + TAU if fmod(span, TAU) != 0.0 else TAU
		if span > TAU:
			span = TAU
	var r := maxf(rx, ry)
	var n := clampi(ceili(absf(span) * r / seg_px), 4, 96)
	var c := cos(rot)
	var s := sin(rot)
	var out := PackedVector2Array()
	out.resize(n + 1)
	for i in n + 1:
		var a := a0 + span * float(i) / float(n)
		var ex := cos(a) * rx
		var ey := sin(a) * ry
		out[i] = Vector2(cx + ex * c - ey * s, cy + ex * s + ey * c)
	return out


## A closed circle polygon.
static func circle_pts(cx: float, cy: float, r: float, seg_px: float = 3.0) -> PackedVector2Array:
	var n := clampi(ceili(TAU * r / seg_px), 8, 72)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := float(i) / float(n) * TAU
		out[i] = Vector2(cx + cos(a) * r, cy + sin(a) * r)
	return out


## Applies a transform to every point.
static func xform(xf: Transform2D, pts: PackedVector2Array) -> PackedVector2Array:
	return xf * pts


## Offsets every point.
static func shifted(pts: PackedVector2Array, ox: float, oy: float) -> PackedVector2Array:
	var out := pts.duplicate()
	var o := Vector2(ox, oy)
	for i in out.size():
		out[i] += o
	return out

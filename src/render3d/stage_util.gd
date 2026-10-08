class_name StageUtil
extends RefCounted
## Small helpers shared by the stage modules: ports of the web build's colour, random and
## easing functions, so numbers come out the same. Colours are linear Vector3s, as in
## three.js (whose Color stores linear values made from sRGB hex strings).

const TAU_F := PI * 2.0


## Linear colour from an sRGB hex string (three.js `new Color(hex)`).
static func col(hex: String) -> Vector3:
	var c := Color.html(hex).srgb_to_linear()
	return Vector3(c.r, c.g, c.b)


static func mixc(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


## three.js Color.getHSL on linear values.
static func to_hsl(c: Vector3) -> Vector3:
	var mx := maxf(c.x, maxf(c.y, c.z))
	var mn := minf(c.x, minf(c.y, c.z))
	var l := (mn + mx) / 2.0
	if mn == mx:
		return Vector3(0, 0, l)
	var delta := mx - mn
	var s := delta / (mx + mn) if l <= 0.5 else delta / (2.0 - mx - mn)
	var h := 0.0
	if mx == c.x:
		h = (c.y - c.z) / delta + (6.0 if c.y < c.z else 0.0)
	elif mx == c.y:
		h = (c.z - c.x) / delta + 2.0
	else:
		h = (c.x - c.y) / delta + 4.0
	return Vector3(h / 6.0, s, l)


static func _hue2rgb(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


## three.js Color.setHSL.
static func from_hsl(h: float, s: float, l: float) -> Vector3:
	h = fposmod(h, 1.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	if s == 0.0:
		return Vector3(l, l, l)
	var p := l * (1.0 + s) if l <= 0.5 else l + s - (l * s)
	var q := 2.0 * l - p
	return Vector3(_hue2rgb(q, p, h + 1.0 / 3.0), _hue2rgb(q, p, h), _hue2rgb(q, p, h - 1.0 / 3.0))


## The web build's shade(): scales lightness (and saturation, and shifts hue) in HSL.
static func shade(c: Vector3, light: float, sat: float = 1.0, hue_shift: float = 0.0) -> Vector3:
	var hsl := to_hsl(c)
	return from_hsl(fmod(hsl.x + hue_shift + 1.0, 1.0), minf(1.0, hsl.y * sat), minf(1.0, hsl.z * light))


static func i32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


static func imul(a: int, b: int) -> int:
	return i32((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF))


## The web build's seeded generator: rng(seed) = mulberry32((seed * 2654435761) >>> 0 || 1).
class Rng:
	var a := 0

	func _init(seed: int) -> void:
		var s := int(float(seed) * 2654435761.0) & 0xFFFFFFFF
		a = s if s != 0 else 1

	func next() -> float:
		a = StageUtil.i32(a + 0x6d2b79f5)
		var t := StageUtil.imul(a ^ ((a & 0xFFFFFFFF) >> 15), 1 | a)
		t = StageUtil.i32(t + StageUtil.imul(t ^ ((t & 0xFFFFFFFF) >> 7), 61 | t)) ^ t
		return float((t ^ ((t & 0xFFFFFFFF) >> 14)) & 0xFFFFFFFF) / 4294967296.0


static func lerp_angle(a: float, b: float, t: float) -> float:
	var d := fmod(b - a, TAU_F)
	if d > PI:
		d -= TAU_F
	if d < -PI:
		d += TAU_F
	return a + d * t


static func kdamp(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


static func ease_in_out(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 4.0 * c * c * c if c < 0.5 else 1.0 - pow(-2.0 * c + 2.0, 3.0) / 2.0


static func ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


## Colours shared by a key and its gates (effects.ts groupColor).
static func group_color(g: int) -> Vector3:
	var list := ["#e3b341", "#d5503c", "#3f86d8", "#4aa86a", "#a26ad8", "#e07fb0", "#4ab6b8"]
	return col(list[posmod(g, list.size())])


## three.js TorusGeometry (radius, tube, radial segments, tubular segments, arc), with the
## winding reversed for Godot.
static func torus(radius: float, tube: float, radial: int, tubular: int, arc: float = TAU_F) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var v := float(j) / radial * TAU_F
			var p := Vector3((radius + tube * cos(v)) * cos(u), (radius + tube * cos(v)) * sin(u), tube * sin(v))
			pos.append(p)
			nor.append((p - Vector3(radius * cos(u), radius * sin(u), 0)).normalized())
			uv.append(Vector2(float(i) / tubular, float(j) / radial))
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			idx.append_array([a, d, b, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## three.js PlaneGeometry(1, 1): a unit quad in xy facing +z, uv with v up, Godot winding.
static func quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)])
	# three.js indices (0, 2, 1), (2, 3, 1), reversed.
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

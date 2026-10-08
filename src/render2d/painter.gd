class_name PagePainter
extends RefCounted
## The page's pen on the GPU. Canvas 2D fills and strokes become triangles, batched into
## few RenderingServer commands, on a sequence of canvas items under one parent so draw
## order is the call order. Godot's 2D polygons are not antialiased, so every fill gets a
## one-pixel feather ring and every stroke or nib ribbon is a strip whose sides fade out
## over a pixel (lines thinner than a pixel fade instead of breaking up), which reads like
## the web canvas's coverage antialiasing.
##
## Canvas composite modes map onto canvas item materials:
##   MUL          source-atop with a dark ink (shadows, granulation): multiplies the
##                destination and keeps its alpha.
##   PREMUL       drawing a cached chunk (SubViewport textures hold premultiplied colour).
##   CLIP*        ctx.clip() to a union of rectangles, in target pixels.
##
## Performance: GDScript is the bottleneck, so geometry that only changes with the boil
## is recorded once into meshes (begin_record / end_record) and replayed each frame with
## a transform; thin straight strokes go out as native antialiased multilines, and dots
## as batched sprite quads.

enum { NORMAL, PREMUL, MUL, CLIP, CLIP_PREMUL }

const MAX_RECTS := 48
const FEATHER := 0.5

static var _premul: CanvasItemMaterial
static var _mul: ShaderMaterial
static var _clip_shader: Shader
static var _clip_premul_shader: Shader
static var _dot_tex: ImageTexture

var parent: RID
var items: Array[RID] = []
var clip_mats: Array[ShaderMaterial] = []
var used := 0
var prev_used := 0
var cur := RID()
var cur_kind := -1

var _p := PackedVector2Array()
var _c := PackedColorArray()
var _u := PackedVector2Array()
var _i := PackedInt32Array()
var _tex := RID()
var _textured := false
## A transform applied to all incoming geometry (ctx.setTransform), and a global alpha.
var xf := Transform2D.IDENTITY
var has_xf := false
var galpha := 1.0
## Scratch colour array, grown as needed.
var _cc := PackedColorArray()
## Pending thin lines (one multiline command): point pairs, a colour per segment, width.
var _lp := PackedVector2Array()
var _lc := PackedColorArray()
var _lw := 0.0
var _recording := false
var _rec: Array = []


static func _materials() -> void:
	if _premul != null:
		return
	_premul = CanvasItemMaterial.new()
	_premul.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var mul := Shader.new()
	mul.code = "shader_type canvas_item;\nrender_mode blend_mul;\nvoid fragment() {\n\tvec4 c = COLOR;\n\tCOLOR = vec4(mix(vec3(1.0), c.rgb, c.a), 1.0);\n}\n"
	_mul = ShaderMaterial.new()
	_mul.shader = mul
	var body := "uniform int count = 0;\nuniform vec4 rects[%d];\nvoid fragment() {\n\tvec2 p = FRAGCOORD.xy;\n\tbool inside = false;\n\tfor (int i = 0; i < count; i++) {\n\t\tvec4 r = rects[i];\n\t\tif (p.x >= r.x && p.y >= r.y && p.x < r.z && p.y < r.w) { inside = true; }\n\t}\n\tif (!inside) { discard; }\n}\n" % MAX_RECTS
	_clip_shader = Shader.new()
	_clip_shader.code = "shader_type canvas_item;\n" + body
	_clip_premul_shader = Shader.new()
	_clip_premul_shader.code = "shader_type canvas_item;\nrender_mode blend_premul_alpha;\n" + body
	# A soft-edged disc for dots (radius 30 of 64, a one-texel edge), mipmapped so it
	# stays smooth at any size.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(30.5 - d, 0.0, 1.0)))
	img.generate_mipmaps()
	_dot_tex = ImageTexture.create_from_image(img)


func _init(parent_item: RID) -> void:
	_materials()
	parent = parent_item


func free_items() -> void:
	for it in items:
		RenderingServer.free_rid(it)
	items.clear()
	clip_mats.clear()
	used = 0
	prev_used = 0
	cur = RID()


func begin() -> void:
	used = 0
	cur = RID()
	cur_kind = -1
	_clear_batch()
	reset_state()


func reset_state() -> void:
	xf = Transform2D.IDENTITY
	has_xf = false
	galpha = 1.0


func set_xf(t: Transform2D) -> void:
	xf = t
	has_xf = t != Transform2D.IDENTITY


## Moves on to a fresh canvas item with the given compositing.
func use(kind: int = NORMAL, rects: PackedVector4Array = PackedVector4Array()) -> void:
	flush()
	if used >= items.size():
		var it := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(it, parent)
		RenderingServer.canvas_item_set_draw_index(it, items.size())
		RenderingServer.canvas_item_set_default_texture_filter(it, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
		# Replayed meshes are culled by their untransformed bounds; the page is one screen,
		# so never cull.
		RenderingServer.canvas_item_set_custom_rect(it, true, Rect2(-1e6, -1e6, 2e6, 2e6))
		items.append(it)
		clip_mats.append(null)
	cur = items[used]
	cur_kind = kind
	RenderingServer.canvas_item_clear(cur)
	match kind:
		NORMAL:
			RenderingServer.canvas_item_set_material(cur, RID())
		PREMUL:
			RenderingServer.canvas_item_set_material(cur, _premul.get_rid())
		MUL:
			RenderingServer.canvas_item_set_material(cur, _mul.get_rid())
		CLIP, CLIP_PREMUL:
			var m := clip_mats[used]
			if m == null or m.shader != (_clip_shader if kind == CLIP else _clip_premul_shader):
				m = ShaderMaterial.new()
				m.shader = _clip_shader if kind == CLIP else _clip_premul_shader
				clip_mats[used] = m
			var arr := PackedVector4Array()
			arr.resize(MAX_RECTS)
			var n := mini(rects.size(), MAX_RECTS)
			for i in n:
				arr[i] = rects[i]
			m.set_shader_parameter("rects", arr)
			m.set_shader_parameter("count", n)
			RenderingServer.canvas_item_set_material(cur, m.get_rid())
	used += 1


## Makes sure drawing goes to an item with the given (unclipped) compositing.
func ensure(kind: int = NORMAL) -> void:
	if not cur.is_valid() or cur_kind != kind:
		use(kind)


func end() -> void:
	flush()
	for i in range(used, prev_used):
		RenderingServer.canvas_item_clear(items[i])
	prev_used = maxi(used, 0)
	cur = RID()
	cur_kind = -1


func _clear_batch() -> void:
	_p.clear()
	_c.clear()
	_u.clear()
	_i.clear()


func flush() -> void:
	if not _lp.is_empty():
		if not cur.is_valid():
			use(NORMAL)
		RenderingServer.canvas_item_add_multiline(cur, _lp, _lc, _lw, true)
		_lp.clear()
		_lc.clear()
	if _i.is_empty():
		_clear_batch()
		return
	if _recording:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _p.duplicate()
		arrays[Mesh.ARRAY_COLOR] = _c.duplicate()
		if _textured:
			arrays[Mesh.ARRAY_TEX_UV] = _u.duplicate()
		arrays[Mesh.ARRAY_INDEX] = _i.duplicate()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_rec.append([mesh, _tex])
		_clear_batch()
		return
	if not cur.is_valid():
		use(NORMAL)
	RenderingServer.canvas_item_add_triangle_array(cur, _i, _p, _c, _u if _textured else PackedVector2Array(), PackedInt32Array(), PackedFloat32Array(), _tex)
	_clear_batch()


func _want(tex: RID, textured: bool) -> void:
	if not cur.is_valid():
		use(NORMAL)
	if not _lp.is_empty():
		flush()
	if textured != _textured or tex != _tex or _p.size() > 40000:
		flush()
		_tex = tex
		_textured = textured


# ---------------------------------------------------------------- recordings

## Starts recording geometry into meshes instead of drawing it.
func begin_record() -> void:
	flush()
	_recording = true
	_rec = []
	reset_state()


## Stops recording; returns the recording (a list of [ArrayMesh, texture RID]).
func end_record() -> Array:
	flush()
	_recording = false
	var r := _rec
	_rec = []
	return r


## Draws a recording through a transform.
func replay(rec: Array, t: Transform2D, modulate: Color = Color.WHITE) -> void:
	if rec.is_empty():
		return
	flush()
	if not cur.is_valid():
		use(NORMAL)
	modulate.a *= galpha
	for r in rec:
		RenderingServer.canvas_item_add_mesh(cur, r[0].get_rid(), t, modulate, r[1])


# ---------------------------------------------------------------- lines and dots

## Straight strokes given as point pairs. Thin ones go out as one native antialiased
## multiline (butt ends, which at these widths read the same as the web's round caps).
func lines(pairs: PackedVector2Array, w: float, c: Color) -> void:
	c.a *= galpha
	if pairs.size() < 2 or c.a <= 0.0:
		return
	if _recording or w > 2.6 or has_xf:
		var g := galpha
		galpha = 1.0
		for i in range(0, pairs.size() - 1, 2):
			stroke(PackedVector2Array([pairs[i], pairs[i + 1]]), w, c)
		galpha = g
		return
	if not cur.is_valid():
		use(NORMAL)
	if not _i.is_empty() or (not _lp.is_empty() and absf(w - _lw) > 1e-4):
		flush()
	_lw = w
	_lp.append_array(pairs)
	var n := pairs.size() / 2
	if _cc.size() != n:
		_cc.resize(n)
	_cc.fill(c)
	_lc.append_array(_cc)


## A filled circle: a sprite quad when drawing live, a polygon when recording.
func dot(x: float, y: float, r: float, c: Color) -> void:
	if _recording:
		fill(PageInk.circle_pts(x, y, maxf(1e-4, r), maxf(1e-4, r) * 0.7 if has_xf else 2.0), c)
		return
	c.a *= galpha
	if c.a <= 0.0:
		return
	flush()
	if not cur.is_valid():
		use(NORMAL)
	var R := maxf(1e-4, r) * (32.0 / 30.0)
	if has_xf:
		RenderingServer.canvas_item_add_set_transform(cur, xf)
	RenderingServer.canvas_item_add_texture_rect(cur, Rect2(x - R, y - R, R * 2.0, R * 2.0), _dot_tex.get_rid(), false, c)
	if has_xf:
		RenderingServer.canvas_item_add_set_transform(cur, Transform2D.IDENTITY)


## An axis-aligned ellipse (rotated by the painter transform if any) as a sprite.
func ellipse_dot(x: float, y: float, rx: float, ry: float, c: Color) -> void:
	if _recording:
		var e := PageInk.arc_pts(x, y, rx, ry, 0, 0, TAU, false, 2.0)
		e.resize(e.size() - 1)
		fill(e, c)
		return
	c.a *= galpha
	if c.a <= 0.0:
		return
	flush()
	if not cur.is_valid():
		use(NORMAL)
	var f := 32.0 / 30.0
	if has_xf:
		RenderingServer.canvas_item_add_set_transform(cur, xf)
	RenderingServer.canvas_item_add_texture_rect(cur, Rect2(x - rx * f, y - ry * f, rx * 2.0 * f, ry * 2.0 * f), _dot_tex.get_rid(), false, c)
	if has_xf:
		RenderingServer.canvas_item_add_set_transform(cur, Transform2D.IDENTITY)


func _colors(c: Color, n: int) -> void:
	if _cc.size() != n:
		_cc.resize(n)
	_cc.fill(c)
	_c.append_array(_cc)


# ---------------------------------------------------------------- fills

## Fills a closed polygon (nonzero rule within the polygon; overlapping separate fills blend).
func fill(P: PackedVector2Array, c: Color, aa: bool = true) -> void:
	var n := P.size()
	c.a *= galpha
	if n < 3 or c.a <= 0.0:
		return
	if has_xf:
		P = xf * P
	_want(RID(), false)
	var base := _p.size()
	var idx := PackedInt32Array()
	if n > 4:
		idx = Geometry2D.triangulate_polygon(P)
	_p.append_array(P)
	_colors(c, n)
	if idx.is_empty():
		# Convex quads, and anything ear clipping gave up on (self-crossing): a fan.
		if n == 3:
			_i.append_array(PackedInt32Array([base, base + 1, base + 2]))
		elif n == 4:
			_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		else:
			var ctr := Vector2.ZERO
			for q in P:
				ctr += q
			ctr /= float(n)
			var ci := _p.size()
			_p.append(ctr)
			_c.append(c)
			for k in n:
				_i.append(ci)
				_i.append(base + k)
				_i.append(base + (k + 1) % n)
	else:
		for k in idx.size():
			_i.append(base + idx[k])
	if aa:
		_feather_ring(P, base, c)


func _feather_ring(P: PackedVector2Array, base: int, c: Color) -> void:
	var n := P.size()
	var area := 0.0
	for k in n:
		var a := P[k]
		var b := P[(k + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area >= 0.0 else -1.0
	var ob := _p.size()
	var c0 := Color(c.r, c.g, c.b, 0.0)
	var prev_n := Vector2.ZERO
	var e := P[0] - P[n - 1]
	if e.length_squared() > 1e-12:
		prev_n = Vector2(e.y, -e.x).normalized() * sgn
	for k in n:
		var e2 := P[(k + 1) % n] - P[k]
		var nn := prev_n
		if e2.length_squared() > 1e-12:
			nn = Vector2(e2.y, -e2.x).normalized() * sgn
		var v := prev_n + nn
		var vl := v.length()
		if vl < 1e-6:
			v = nn
		else:
			v /= vl
		var mit := 1.0 / maxf(0.35, v.dot(nn))
		_p.append(P[k] + v * (FEATHER * 2.0 * mit))
		prev_n = nn
	_colors(c0, n)
	for k in n:
		var k1 := (k + 1) % n
		_i.append(base + k)
		_i.append(base + k1)
		_i.append(ob + k1)
		_i.append(base + k)
		_i.append(ob + k1)
		_i.append(ob + k)


func fill_rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	if has_xf:
		fill(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), c, false)
		return
	c.a *= galpha
	if c.a <= 0.0 or w <= 0.0 or h <= 0.0:
		return
	_want(RID(), false)
	var base := _p.size()
	_p.append(Vector2(x, y))
	_p.append(Vector2(x + w, y))
	_p.append(Vector2(x + w, y + h))
	_p.append(Vector2(x, y + h))
	_colors(c, 4)
	_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## Fills every subpath of a path.
func fill_path(path: PagePath, c: Color, aa: bool = true) -> void:
	for s in path.count():
		fill(path.subpath(s), c, aa)


# ---------------------------------------------------------------- textured fills

## Fills a polygon with a repeating texture anchored at `anchor` (a canvas pattern).
func fill_tex(P: PackedVector2Array, tex: RID, tile: Vector2, anchor: Vector2, c: Color) -> void:
	var n := P.size()
	c.a *= galpha
	if n < 3 or c.a <= 0.0:
		return
	if has_xf:
		P = xf * P
	_want(tex, true)
	var base := _p.size()
	var idx := PackedInt32Array()
	if n > 4:
		idx = Geometry2D.triangulate_polygon(P)
	_p.append_array(P)
	_colors(c, n)
	for q in P:
		_u.append((q - anchor) / tile)
	if idx.is_empty():
		if n == 3:
			_i.append_array(PackedInt32Array([base, base + 1, base + 2]))
		elif n == 4:
			_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		else:
			var ctr := Vector2.ZERO
			for q in P:
				ctr += q
			ctr /= float(n)
			var ci := _p.size()
			_p.append(ctr)
			_c.append(c)
			_u.append((ctr - anchor) / tile)
			for k in n:
				_i.append(ci)
				_i.append(base + k)
				_i.append(base + (k + 1) % n)
	else:
		for k in idx.size():
			_i.append(base + idx[k])


func rect_tex(x: float, y: float, w: float, h: float, tex: RID, tile: Vector2, anchor: Vector2, c: Color) -> void:
	if has_xf:
		fill_tex(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), tex, tile, anchor, c)
		return
	c.a *= galpha
	if c.a <= 0.0 or w <= 0.0 or h <= 0.0:
		return
	_want(tex, true)
	var base := _p.size()
	var q := PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])
	_p.append_array(q)
	_colors(c, 4)
	for v in q:
		_u.append((v - anchor) / tile)
	_i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## Draws a texture (or a region of it) into a rectangle.
func texture(tex: RID, rect: Rect2, modulate: Color = Color.WHITE, src: Rect2 = Rect2()) -> void:
	assert(not _recording)
	if not cur.is_valid():
		use(NORMAL)
	flush()
	modulate.a *= galpha
	if src.size.x > 0.0:
		RenderingServer.canvas_item_add_texture_rect_region(cur, rect, tex, src, modulate)
	else:
		RenderingServer.canvas_item_add_texture_rect(cur, rect, tex, false, modulate)


# ---------------------------------------------------------------- strips and strokes

## Fills the band between two sides (a nib ribbon, ring or stroke), fading both edges
## over a pixel. A band thinner than a pixel fades out instead.
func strip(A: PackedVector2Array, B: PackedVector2Array, c: Color, closed: bool = false) -> void:
	var n := A.size()
	c.a *= galpha
	if n < 2 or c.a <= 0.0:
		return
	if has_xf:
		A = xf * A
		B = xf * B
	_want(RID(), false)
	var base := _p.size()
	var c0 := Color(c.r, c.g, c.b, 0.0)
	var last_u := Vector2(0, 1)
	for k in n:
		var a := A[k]
		var b := B[k]
		var d := a - b
		var l := d.length()
		var u: Vector2
		if l > 1e-6:
			u = d / l
		else:
			var t := (A[mini(n - 1, k + 1)] + B[mini(n - 1, k + 1)]) - (A[maxi(0, k - 1)] + B[maxi(0, k - 1)])
			u = Vector2(-t.y, t.x).normalized() if t.length_squared() > 1e-12 else last_u
		last_u = u
		var m := (a + b) * 0.5
		var inner: float
		var outer: float
		var ca: float
		if l >= 1.0:
			inner = l * 0.5 - FEATHER
			outer = l * 0.5 + FEATHER
			ca = c.a
		else:
			inner = 0.0
			outer = 1.0
			ca = c.a * l
		_p.append(m + u * outer)
		_p.append(m + u * inner)
		_p.append(m - u * inner)
		_p.append(m - u * outer)
		_c.append(c0)
		var cc := Color(c.r, c.g, c.b, ca)
		_c.append(cc)
		_c.append(cc)
		_c.append(c0)
	var segs := n if closed else n - 1
	for k in segs:
		var i0 := base + k * 4
		var i1 := base + ((k + 1) % n) * 4
		for q in 3:
			_i.append(i0 + q)
			_i.append(i0 + q + 1)
			_i.append(i1 + q + 1)
			_i.append(i0 + q)
			_i.append(i1 + q + 1)
			_i.append(i1 + q)


## The sides of a stroke of width w along a polyline (round caps approximated by
## extending the ends half a width). Returns [A, B].
static func stroke_sides(P: PackedVector2Array, w: float, closed: bool = false, cap: bool = true) -> Array:
	var n := P.size()
	var A := PackedVector2Array()
	var B := PackedVector2Array()
	A.resize(n)
	B.resize(n)
	var hw := w * 0.5
	var prev_t := Vector2.ZERO
	if closed:
		prev_t = (P[0] - P[n - 1]).normalized()
	for k in n:
		var nxt: Vector2
		if k + 1 < n:
			nxt = P[k + 1] - P[k]
		elif closed:
			nxt = P[0] - P[k]
		else:
			nxt = Vector2.ZERO
		var t := nxt.normalized() if nxt.length_squared() > 1e-12 else prev_t
		if prev_t == Vector2.ZERO:
			prev_t = t
		var bis := prev_t + t
		var bl := bis.length()
		bis = t if bl < 1e-6 else bis / bl
		var nrm := Vector2(-bis.y, bis.x)
		var mit := 1.0 / maxf(0.5, absf(bis.dot(t)) if t != Vector2.ZERO else 1.0)
		var p := P[k]
		if cap and not closed:
			if k == 0:
				p -= t * hw
			elif k == n - 1:
				p += prev_t * hw
		A[k] = p + nrm * (hw * mit)
		B[k] = p - nrm * (hw * mit)
		if t != Vector2.ZERO:
			prev_t = t
	return [A, B]


func stroke(P: PackedVector2Array, w: float, c: Color, closed: bool = false, cap: bool = true) -> void:
	if P.size() < 2:
		return
	var s := stroke_sides(P, w, closed, cap)
	strip(s[0], s[1], c, closed)


## A stroke built in a local space and drawn through a transform (widths scale with it).
func seg(x0: float, y0: float, x1: float, y1: float, w: float, c: Color) -> void:
	lines(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)]), w, c)


## Strokes every subpath of a path.
func stroke_path(path: PagePath, w: float, c: Color) -> void:
	for s in path.count():
		var sp := path.subpath(s)
		if sp.size() >= 2:
			stroke(sp, w, c, path.is_closed(s))


## A nib ribbon along points.
func ribbon(pts: PackedVector2Array, w: float, seed: int, c: Color, taper: float = 0.5) -> void:
	var s := PageInk.ribbon(pts, w, seed, taper)
	strip(s[0], s[1], c)


## A closed ribbon (an outline) round a point loop.
func ring(pts: PackedVector2Array, w: float, seed: int, c: Color) -> void:
	var s := PageInk.ring(pts, w, seed)
	strip(s[0], s[1], c, true)

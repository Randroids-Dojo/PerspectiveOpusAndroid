class_name UiStyle
extends RefCounted
## Colours, type and drawing helpers shared by the whole UI, a port of the web build's
## src/ui/ui.css. The UI is styled twice: gilt on dark velvet for the Stage and ink on
## parchment for the Score. `k` (0 = Score, 1 = Stage) blends between them; the
## director eases it over half a second whenever the world turns, like the CSS
## transitions on :root[data-world].

const EASE := Vector4(0.22, 0.8, 0.24, 1.0)
const EASE_CSS := Vector4(0.25, 0.1, 0.25, 1.0)

static var k := 1.0
## "keyboard", "gamepad" or "touch", mirrored from the input router.
static var device := "keyboard"
## Text and layout sizes follow the web build's small-height media query.
static var compact := true
## Backdrop blur on cards (off on the lowest detail).
static var blur := true

static var display: Font
static var display_i: Font
static var body: Font
static var body_i: Font
static var glyph: Texture2D
static var page_icon: Texture2D
static var stage_icon: Texture2D
static var chevron: Texture2D
static var card_shader: Shader
static var gold_shader: Shader

static var _stage := {}
static var _score := {}
static var _spaced := {}
static var _ready := false


static func setup() -> void:
	if _ready:
		return
	_ready = true
	_stage = {
		"fg": _rgba(245, 234, 210),
		"fg_dim": _rgba(245, 234, 210, 0.62),
		"accent": _rgba(230, 196, 124),
		"accent_deep": _rgba(185, 138, 58),
		"card": _rgba(22, 14, 22, 0.78),
		"card_edge": _rgba(230, 196, 124, 0.42),
		"slot_empty": _rgba(245, 234, 210, 0.42),
		"fade": _rgba(13, 10, 16),
		"scrim_in": _rgba(10, 6, 14, 0.25),
		"scrim_out": _rgba(10, 6, 14, 0.72),
		"plate_in": _rgba(14, 8, 18, 0.5),
		"plate_mid": _rgba(14, 8, 18, 0.28),
		"title_bg": _rgba(10, 6, 14, 0.5),
		"shadow": _rgba(0, 0, 0, 0.55),
	}
	_score = {
		"fg": _rgba(42, 32, 27),
		"fg_dim": _rgba(42, 32, 27, 0.62),
		"accent": _rgba(168, 50, 42),
		"accent_deep": _rgba(122, 32, 24),
		"card": _rgba(244, 234, 210, 0.94),
		"card_edge": _rgba(42, 32, 27, 0.55),
		"slot_empty": _rgba(42, 32, 27, 0.3),
		"fade": _rgba(239, 228, 201),
		"scrim_in": _rgba(240, 228, 200, 0.2),
		"scrim_out": _rgba(120, 96, 64, 0.42),
		"plate_in": _rgba(244, 234, 210, 0.75),
		"plate_mid": _rgba(244, 234, 210, 0.4),
		"title_bg": _rgba(244, 234, 210, 0.66),
		"shadow": _rgba(255, 248, 230, 0.7),
	}
	display = load("res://assets/fonts/CormorantGaramond-Medium.woff2")
	display_i = load("res://assets/fonts/CormorantGaramond-MediumItalic.woff2")
	var fr: FontFile = load("res://assets/fonts/Fraunces-Variable.woff2")
	# The variable font's default instance is its heaviest; CSS asks for 400. Godot only
	# honours the numeric axis tag here.
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var b := FontVariation.new()
	b.base_font = fr
	b.variation_opentype = {wght: 400}
	body = b
	# The web build loads no italic Fraunces, so the browser slants the roman. Same here.
	var bi := FontVariation.new()
	bi.base_font = fr
	bi.variation_opentype = {wght: 400}
	# FreeType reads the x axis's y as the shear of x by y (x' = x + 0.21 y).
	bi.variation_transform = Transform2D(Vector2(1, 0.21), Vector2(0, 1), Vector2.ZERO)
	body_i = bi
	glyph = _svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 32" width="24" height="32"><g fill="#fff">'
		+ '<ellipse cx="9" cy="25" rx="6.6" ry="4.8" transform="rotate(-22 9 25)"/>'
		+ '<rect x="14" y="4" width="2.2" height="21" rx="1"/>'
		+ '<path d="M16 4c1 4.5 7 6 6.4 12.5-.3-3.6-3.2-6-6.4-6.4z"/></g></svg>', 8.0)
	# A flat sheet for the Score: a bordered page with three ruled lines.
	page_icon = _svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 22" width="22" height="22">'
		+ '<rect x="4.75" y="3.75" width="12.5" height="14.5" rx="1" fill="none" stroke="#fff" stroke-width="1.5"/>'
		+ '<g fill="#fff"><rect x="8.5" y="8.5" width="5" height="1"/><rect x="8.5" y="12.5" width="5" height="1"/>'
		+ '<rect x="8.5" y="16.5" width="5" height="1"/></g></svg>', 8.0)
	# A little cube for the Stage: the CSS square turned 45 degrees, scaled and skewed.
	var pts := PackedStringArray()
	var inner := PackedStringArray()
	for c in [Vector2(-7.25, -7.25), Vector2(7.25, -7.25), Vector2(7.25, 7.25), Vector2(-7.25, 7.25)]:
		pts.append(_stage_corner(c, 0.0))
	for c in [Vector2(-7.25, 7.25), Vector2(-7.25, -7.25), Vector2(7.25, -7.25)]:
		inner.append(_stage_corner(c, 1.9))
	stage_icon = _svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 22" width="22" height="22">'
		+ '<polygon points="%s" fill="none" stroke="#fff" stroke-width="1.5" stroke-linejoin="miter"/>' % " ".join(pts)
		+ '<polyline points="%s" fill="none" stroke="#fff" stroke-opacity="0.45" stroke-width="2"/></svg>' % " ".join(inner), 8.0)
	# The jump button's chevron: a 22 px square's top and left borders, turned 45 degrees.
	chevron = _svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-16 -16 32 32" width="32" height="32">'
		+ '<g transform="translate(0 5) rotate(45)"><path d="M-11 11V-11H11V-8H-8V11Z" fill="#fff"/></g></svg>', 6.0)
	card_shader = load("res://src/ui/card.gdshader")
	gold_shader = load("res://src/ui/gold.gdshader")


static func _stage_corner(c: Vector2, inset: float) -> String:
	var p := c * (1.0 - inset / 7.25)
	var sk := tan(deg_to_rad(-8.0))
	p = Vector2(p.x + sk * p.y, sk * p.x + p.y) * 0.78
	p = p.rotated(PI / 4.0)
	return "%.3f,%.3f" % [11.0 + p.x, 11.0 + p.y]


static func _svg(src: String, scale: float) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(src, scale)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _rgba(r: int, g: int, b: int, a := 1.0) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)


## The current colour for a role, blended between the two worlds.
static func c(role: String) -> Color:
	return (_score[role] as Color).lerp(_stage[role], k)


## color-mix(in srgb, col p%, transparent)
static func fade(col: Color, p: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * p)


## A CSS cubic-bezier timing function.
static func bezier(e: Vector4, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0:
		return t
	var lo := 0.0
	var hi := 1.0
	var u := t
	for i in 20:
		var x := _bz(e.x, e.z, u)
		if absf(x - t) < 1e-4:
			break
		if x < t:
			lo = u
		else:
			hi = u
		u = (lo + hi) / 2.0
	return _bz(e.y, e.w, u)


static func _bz(p1: float, p2: float, u: float) -> float:
	var v := 1.0 - u
	return 3.0 * v * v * u * p1 + 3.0 * v * u * u * p2 + u * u * u


static func ease(t: float) -> float:
	return bezier(EASE, t)


## A font with CSS letter-spacing (in em).
static func spaced(font: Font, size: int, em: float) -> Font:
	var px := roundi(em * size)
	if px == 0:
		return font
	var key := "%d:%d" % [font.get_instance_id(), px]
	if _spaced.has(key):
		return _spaced[key]
	var v := FontVariation.new()
	# Variations do not stack, so copy the weight and slant onto the spaced one.
	if font is FontVariation:
		var fv := font as FontVariation
		v.base_font = fv.base_font
		v.variation_opentype = fv.variation_opentype
		v.variation_transform = fv.variation_transform
	else:
		v.base_font = font
	v.spacing_glyph = px
	_spaced[key] = v
	return v


static func width(font: Font, size: int, s: String) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Baseline offset from the top of a CSS line box of the given line height.
static func baseline(font: Font, size: int, line_height: float) -> float:
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	return (line_height - (asc + desc)) / 2.0 + asc


## The HUD's text shadow: a soft dark blur on the Stage, a crisp light offset on the Score.
static func shadow_text(ci: CanvasItem, font: Font, size: int, pos: Vector2, s: String, alpha := 1.0, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if k > 0.01:
		# 0 2px 10px rgba(0, 0, 0, 0.55): a faint haze, built from widening outlines.
		var a := 0.55 * k * alpha
		for pass_i in 3:
			var o: int = [20, 12, 6][pass_i]
			ci.draw_string_outline(font, pos + Vector2(0, 2), s, align, w, size, o, Color(0, 0, 0, a * [0.035, 0.045, 0.055][pass_i]))
	if k < 0.99:
		ci.draw_string(font, pos + Vector2(0, 1), s, align, w, size, fade(_score["shadow"], (1.0 - k) * alpha))


static func text(ci: CanvasItem, font: Font, size: int, pos: Vector2, s: String, col: Color, shadow := false, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if shadow:
		shadow_text(ci, font, size, pos, s, col.a, w, align)
	ci.draw_string(font, pos, s, align, w, size, col)


## The eighth-note glyph, fitted to the CSS .glyph box (0.9em by 1.2em) at `rect`.
static func draw_glyph(ci: CanvasItem, rect: Rect2, col: Color) -> void:
	# The SVG's 24 by 32 view box sits centred in the box with `contain` scaling.
	var s := minf(rect.size.x / 24.0, rect.size.y / 32.0)
	var sz := Vector2(24, 32) * s
	ci.draw_texture_rect(glyph, Rect2(rect.position + (rect.size - sz) / 2.0, sz), false, col)


## Glyph with the HUD's drop shadow.
static func draw_glyph_shadowed(ci: CanvasItem, rect: Rect2, col: Color) -> void:
	if k > 0.01:
		draw_glyph(ci, rect.grow(1.5).grow_individual(0, -1, 0, 3), Color(0, 0, 0, 0.22 * k * col.a))
	if k < 0.99:
		draw_glyph(ci, Rect2(rect.position + Vector2(0, 1), rect.size), fade(_score["shadow"], (1.0 - k) * col.a))
	draw_glyph(ci, rect, col)


## A CSS radial-gradient background: `ellipse farthest-corner at <at>`, painted only
## inside `box` (backgrounds are clipped to their element). Colours are evaluated on a
## grid and interpolated across it.
static func radial_box(ci: CanvasItem, box: Rect2, at: Vector2, stops: Array, nx := 24, ny := 12) -> void:
	var cx := box.size.x * at.x
	var cy := box.size.y * at.y
	var rx := maxf(cx, box.size.x - cx) * sqrt(2.0)
	var ry := maxf(cy, box.size.y - cy) * sqrt(2.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in ny + 1:
		for i in nx + 1:
			var p := Vector2(box.size.x * i / nx, box.size.y * j / ny)
			var d := Vector2((p.x - cx) / rx, (p.y - cy) / ry).length()
			pts.append(box.position + p)
			cols.append(_stop_color(stops, d))
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			idx.append_array([a, a + 1, a + nx + 2, a, a + nx + 2, a + nx + 1])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _stop_color(stops: Array, d: float) -> Color:
	if d <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		var o: float = stops[i][0]
		if d <= o:
			var o0: float = stops[i - 1][0]
			return (stops[i - 1][1] as Color).lerp(stops[i][1], (d - o0) / maxf(1e-5, o - o0))
	return stops[stops.size() - 1][1]


## A radial gradient filling an ellipse. Stops: [[offset, Color], ...] from the centre
## (0) to the rim (1), on rings placed exactly at the stops.
static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, stops: Array, segs := 40) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	pts.append(center)
	cols.append(stops[0][1])
	var rings: Array = stops.duplicate()
	if float(rings[0][0]) <= 0.0:
		rings.remove_at(0)
	for r in rings:
		var off: float = r[0]
		for i in segs:
			var a := TAU * i / segs
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * off)
			cols.append(r[1])
	for i in segs:
		idx.append_array([0, 1 + i, 1 + (i + 1) % segs])
	for ri in range(1, rings.size()):
		var a0 := 1 + (ri - 1) * segs
		var b0 := 1 + ri * segs
		for i in segs:
			var j := (i + 1) % segs
			idx.append_array([a0 + i, b0 + i, b0 + j, a0 + i, b0 + j, a0 + j])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


## A horizontal linear gradient: stops [[offset, Color], ...] across `box`.
static func linear_x(ci: CanvasItem, box: Rect2, stops: Array) -> void:
	for i in stops.size() - 1:
		var x0 := box.position.x + box.size.x * float(stops[i][0])
		var x1 := box.position.x + box.size.x * float(stops[i + 1][0])
		var c0: Color = stops[i][1]
		var c1: Color = stops[i + 1][1]
		ci.draw_polygon(
			PackedVector2Array([Vector2(x0, box.position.y), Vector2(x1, box.position.y), Vector2(x1, box.end.y), Vector2(x0, box.end.y)]),
			PackedColorArray([c0, c1, c1, c0]))


## A pill or circle (CSS border-radius: 999px) with a 1 px edge and a translucent fill.
static func pill(ci: CanvasItem, rect: Rect2, fill: Color, edge: Color) -> void:
	_pill_box.bg_color = fill
	_pill_box.border_color = edge
	_pill_box.set_corner_radius_all(ceili(minf(rect.size.x, rect.size.y) / 2.0))
	ci.draw_style_box(_pill_box, rect)


static var _pill_box := _make_pill_box()


static func _make_pill_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.set_border_width_all(1)
	b.anti_aliasing = true
	b.anti_aliasing_size = 0.5
	b.corner_detail = 16
	return b


## m:ss.s, like the web build's fmtTime.
static func fmt_time(seconds: float) -> String:
	var m := floori(seconds / 60.0)
	var s := seconds - m * 60.0
	return "%d:%s%.1f" % [m, "0" if s < 10.0 else "", s]


const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]

class_name PageBackdrop
extends RefCounted
## The page and the world behind the world (paper.ts and backdrop.ts): parchment fixed to
## the screen, faint hand-ruled staves through the sky, the sky emblem (sun, moon, clock
## face or chandelier), drifting clouds and ink-wash silhouettes in two parallax bands.
## Every picture is baked from the web build's own generators by
## tools/bake_page_textures.ts; this places them exactly as the web build does.


class Band:
	var tex: Texture2D
	var tw := 0.0
	var th := 0.0
	var skirt := 0.0
	var fx := 0.0
	var fy := 0.0
	var lift := 0.0
	var base := Color.TRANSPARENT
	var has_base := false


var paper: Texture2D
var vignette: Texture2D
var staves: Texture2D
var sky: Texture2D
var clouds: Texture2D
var wash: Texture2D
var wash_color := Color.BLACK
var bands: Array[Band] = []
var staves_tw := 0.0
var staves_th := 0.0
var emblem_front := false
var rs := 1.5
var bake_ppu := 31.2
## Low quality: skip the clouds.
var lite := false
var _ref_y := NAN
var _ground_y := NAN
var _last_now := 0.0


func load_palette(t: PageTones) -> void:
	var dir := "res://assets/page/%s/" % t.id
	paper = load(dir + "paper.png")
	vignette = load(dir + "vignette.png")
	staves = load(dir + "staves.png")
	sky = load(dir + "sky.png")
	var f := FileAccess.open(dir + "backdrop.json", FileAccess.READ)
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	clouds = load(dir + "clouds.png") if bool(m.clouds) else null
	rs = float(m.rs)
	bake_ppu = float(m.ppu)
	staves_tw = float(m.stavesTW)
	staves_th = float(m.stavesTH)
	emblem_front = bool(m.emblemFront)
	bands.clear()
	for i in m.bands.size():
		var bd: Dictionary = m.bands[i]
		var b := Band.new()
		b.tex = load(dir + "band%d.png" % i)
		b.tw = float(bd.tw)
		b.th = float(bd.th)
		b.skirt = float(bd.skirt)
		b.fx = float(bd.fx)
		b.fy = float(bd.fy)
		b.lift = float(bd.lift)
		if bd.base != null:
			b.base = PageTones.parse_css(String(bd.base))
			b.has_base = true
		bands.append(b)
	wash = load("res://assets/page/patterns/%s.png" % ("band_wash_inv" if t.inv else "band_wash"))
	wash_color = t.paper_shade if t.inv else t.shade
	_ref_y = NAN
	_ground_y = NAN


func draw_paper(pt: PagePainter, W: float, H: float) -> void:
	pt.texture(paper.get_rid(), Rect2(0, 0, W, H))


## The vignette as four edge strips: its middle is clear.
func draw_vignette(pt: PagePainter, W: float, H: float) -> void:
	var vw := float(vignette.get_width())
	var vh := float(vignette.get_height())
	var ex := floorf(vw * 0.2)
	var ey := floorf(vh * 0.2)
	var sx := W / vw
	var sy := H / vh
	var r := vignette.get_rid()
	pt.texture(r, Rect2(0, 0, W, ey * sy), Color.WHITE, Rect2(0, 0, vw, ey))
	pt.texture(r, Rect2(0, H - ey * sy, W, ey * sy), Color.WHITE, Rect2(0, vh - ey, vw, ey))
	pt.texture(r, Rect2(0, ey * sy, ex * sx, H - 2 * ey * sy), Color.WHITE, Rect2(0, ey, ex, vh - 2 * ey))
	pt.texture(r, Rect2(W - ex * sx, ey * sy, ex * sx, H - 2 * ey * sy), Color.WHITE, Rect2(vw - ex, ey, ex, vh - 2 * ey))


## Draws staves, the sky emblem, clouds and the silhouette bands. `ground` is the height
## the player stands at; the bands settle on it slowly, so they sit behind the ground
## however the camera frames the page.
func draw(pt: PagePainter, view: View, W: float, H: float, level_w: float, now: float, ground: float) -> void:
	var dt := clampf(now - _last_now, 0.0, 0.1)
	_last_now = now
	var c2 := view.c2
	if is_nan(_ref_y) or absf(c2.y - _ref_y) > 9.0:
		_ref_y = c2.y
	_ref_y += (c2.y - _ref_y) * (1.0 - exp(-0.7 * dt))
	if is_nan(_ground_y) or absf(ground - _ground_y) > 6.0:
		_ground_y = ground
	_ground_y += (ground - _ground_y) * (1.0 - exp(-0.9 * dt))
	var dpr := view.dpr
	var ppu := view.ppu
	# Baked texels to target pixels (the web build's dpr / rs, and the page scale if it differs).
	var s := dpr / rs * (ppu / bake_ppu)
	var dy := (c2.y - _ref_y) * ppu * dpr

	if staves != null:
		var tw := staves_tw * s
		var th := staves_th * s
		var ox := -fposmod(c2.x * ppu * 0.06 * dpr, tw)
		var oy := dy * 0.08 - th * 0.12
		var rows := ceili((H * 0.62) / th) + 1
		for r in rows:
			var y := oy + r * th
			if y > H * 0.7:
				break
			var a := maxf(0.0, 0.75 - (y / H) * 0.85)
			var x := ox
			while x < W:
				pt.texture(staves.get_rid(), Rect2(x, y, tw, th), Color(1, 1, 1, a))
				x += tw
	if sky != null and not emblem_front:
		var size := sky.get_width() * s
		var x := W * 0.76 - (c2.x - level_w / 2.0) * ppu * dpr * 0.015 - size / 2.0
		var y := H * 0.19 + dy * 0.03 - size / 2.0
		pt.texture(sky.get_rid(), Rect2(x, y, size, size), Color(1, 1, 1, 0.82))
	if clouds != null and not lite:
		var tw := clouds.get_width() * s
		var th := clouds.get_height() * s
		var ox := -fposmod(c2.x * ppu * 0.04 * dpr + now * 5.0 * dpr, tw)
		var oy := H * 0.04 + dy * 0.04
		var x := ox
		while x < W:
			pt.texture(clouds.get_rid(), Rect2(x, oy, tw, th))
			x += tw
	for bi in bands.size():
		var b := bands[bi]
		if bi == 1 and emblem_front and sky != null:
			var size := sky.get_width() * s
			var x := W * 0.62 - (c2.x - level_w / 2.0) * ppu * dpr * 0.03 - size / 2.0
			pt.texture(sky.get_rid(), Rect2(x, H * 0.1 + dy * 0.05 - size / 2.0, size, size))
		var tw := b.tw * s
		var th := b.th * s
		var full := (b.th + b.skirt) * s
		var ground_line := H / 2.0 - (_ground_y - c2.y) * ppu * dpr
		var base_y := ground_line - b.lift * ppu * dpr + dy * b.fy
		var top := base_y - th
		var ox := -fposmod(c2.x * ppu * b.fx * dpr, tw)
		var x := ox
		while x < W:
			pt.texture(b.tex.get_rid(), Rect2(x, top, tw, full))
			x += tw
		if b.has_base and top + full < H:
			# Continue the band's wash below it with the same granulation, aligned to the tile.
			var y0 := top + full - 1.0
			pt.fill_rect(0, y0, W, H - y0, b.base)
			var ws := 256.0 * s
			pt.rect_tex(0, y0, W, H - y0, wash.get_rid(), Vector2(ws, ws), Vector2(ox, top), wash_color)

class_name PageEnv
extends RefCounted
## Everything a drawing function needs to know about the current page (env.ts): the level
## analysis, the tones, the pattern tiles and the clocks.

enum { HATCH, CROSS, DENSE, WASH, LIGHT }


## A projection from world units to target pixels: x' = ox + x * k, y' = oy - y * k.
class Proj:
	## A copy whose origin is moved so (bx, by) in world units lands on (0, 0): drawing
	## made with it is in "local pixels" and can be replayed anywhere with a translation.
	func local(bx: float, by: float) -> Proj:
		var q := copy()
		q.ox = -bx * k
		q.oy = by * k
		return q

	## Target pixels per world unit.
	var k := 1.0
	var ox := 0.0
	var oy := 0.0
	## Target pixels per UI pixel.
	var dpr := 1.0
	## Stroke scale: target pixels per drawing pixel (dpr adjusted for the page scale).
	var px := 1.0
	## Boil frame index (changes about 8 times a second).
	var boil := 0

	func copy() -> Proj:
		var p := Proj.new()
		p.k = k
		p.ox = ox
		p.oy = oy
		p.dpr = dpr
		p.px = px
		p.boil = boil
		return p


## The hatching and wash tiles, baked from the web build as white masks and tinted here.
class Patterns:
	var tex: Array[Texture2D] = []
	var rid: Array[RID] = []
	var tile: Array[Vector2] = []
	var color: Array[Color] = []

	func _init(t: PageTones, dpr: float) -> void:
		var sp := maxi(3, PageInk.jround(4.2 * dpr))
		var spc := clampi(sp, 3, 18)
		var inv := "Inv" if t.inv else ""
		var names := ["hatch%s_%d" % [inv, spc], "cross%s_%d" % [inv, spc], "dense_%d" % spc, "", "light_%d" % spc]
		var light_c := PageTones.mix(t.paper, Color.WHITE, 0.75) if t.inv else PageTones.mix(t.paper, Color8(255, 252, 240), 0.6)
		var cols := [t.shade, t.shade, t.shade, t.paper_shade if t.inv else t.shade, light_c]
		for i in 5:
			var tx: Texture2D
			var ts: Vector2
			if i == WASH:
				tx = load("res://assets/page/patterns/%s.png" % ("wash_inv" if t.inv else "wash"))
				var ws := float(PageInk.jround(256.0 * minf(2.0, dpr)))
				ts = Vector2(ws, ws)
			else:
				tx = load("res://assets/page/patterns/%s.png" % names[i])
				# The baked tile is made for the rounded spacing; keep its pixel size.
				ts = Vector2(tx.get_width(), tx.get_height())
				if spc != sp:
					var f := float(sp) / float(spc)
					ts *= f
			tex.append(tx)
			rid.append(tx.get_rid())
			tile.append(ts)
			color.append(cols[i])


var world: PageWorld
var tones: PageTones
var pats: Patterns
## Real seconds (live decor).
var now := 0.0
## Game seconds.
var time := 0.0
var quality := "high"
## Recorded geometry of live things.
var cache := PageCache.new()


static func stroke_scale(ppu: float) -> float:
	return pow(maxf(0.45, minf(1.6, ppu / 57.6)), 0.6)


## Fills a polygon with a pattern anchored to the world bitmap origin of a projection.
func pat(painter: PagePainter, P: PackedVector2Array, kind: int, a: float, p: Proj, shift: Vector2 = Vector2.ZERO) -> void:
	var c: Color = pats.color[kind]
	painter.fill_tex(P, pats.rid[kind], pats.tile[kind], Vector2(p.ox, p.oy) + shift, Color(c.r, c.g, c.b, a))


func pat_rect(painter: PagePainter, x: float, y: float, w: float, h: float, kind: int, a: float, p: Proj, shift: Vector2 = Vector2.ZERO) -> void:
	var c: Color = pats.color[kind]
	painter.rect_tex(x, y, w, h, pats.rid[kind], pats.tile[kind], Vector2(p.ox, p.oy) + shift, Color(c.r, c.g, c.b, a))


func pat_path(painter: PagePainter, path: PagePath, kind: int, a: float, p: Proj, shift: Vector2 = Vector2.ZERO) -> void:
	for s in path.count():
		pat(painter, path.subpath(s), kind, a, p, shift)

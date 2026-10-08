class_name PageWorld
extends RefCounted
## What the page needs to know about a level, computed once per load (world.ts): which
## voxel shows at the front of each column, the silhouette of every depth layer as long
## merged edge runs (so outlines are drawn as single strokes), seams between materials,
## thorns and decor with their bounds.

enum { TOP, BOTTOM, LEFT, RIGHT }

## Drawing extents per decor kind at scale 1: half width, height above base, depth below base.
const DECOR_SIZE := {
	"tree": [1.5, 3.9, 0.1], "pine": [1.1, 4.1, 0.1], "lamp": [0.8, 2.6, 0.05], "pillar": [0.65, 3.3, 0.05],
	"banner": [0.75, 2.3, 0.9], "flowers": [0.6, 0.75, 0.05], "grass": [0.6, 0.8, 0.05], "rock": [0.75, 0.75, 0.08],
	"reeds": [0.6, 1.8, 0.05], "lantern": [0.7, 2.3, 0.05], "pipes": [1.2, 3.6, 0.05], "gear": [1.5, 2.9, 0.1],
	"crystals": [0.8, 1.3, 0.05], "statue": [0.8, 3.0, 0.05], "curtain": [1.3, 4.2, 0.05], "arch": [1.5, 3.4, 0.05],
	"mushroom": [0.6, 0.7, 0.05], "bell": [0.9, 2.5, 0.05], "candles": [0.6, 1.1, 0.05],
}
const LIVE_DECOR := ["gear", "banner", "candles", "lantern", "lamp", "bell"]


class Run:
	var x0: int
	var y0: int
	var x1: int
	var y1: int
	var side: int
	var z: int
	var seed: int


class DecorInfo:
	var kind: String
	var px: float
	var py: float
	var pz: float
	var scale: float
	var seed: int
	var x0: float
	var y0: float
	var x1: float
	var y1: float
	var z: int
	var live: bool


var lv: Level
var w: int
var h: int
var d: int
var front: PackedByteArray
## Outline runs per layer.
var edges: Array = []
## Seams per layer as flat [x0, y0, x1, y1, ...].
var seams: Array = []
## Thorn cells per layer as flat [x, y, ...].
var thorns: Array = []
var decor: Array[DecorInfo] = []
var decor_by_layer: Array = []
var live_decor: Array[DecorInfo] = []
## 1 where a cell has anything static to draw (for skipping empty chunks).
var content: PackedByteArray


func _init(level: Level) -> void:
	lv = level
	w = lv.w
	h = lv.h
	d = lv.d
	front = lv.front
	for z in d:
		edges.append(_build_edges(z))
		seams.append(_build_seams(z))
		thorns.append(PackedInt32Array())
	for z in d:
		var list: PackedInt32Array = thorns[z]
		for y in h:
			for x in w:
				if lv.cells[x + w * (y + h * z)] != Level.MAT_THORN:
					continue
				var f := front[x + w * y]
				if f != Level.NO_DEPTH and f < z:
					continue
				list.append(x)
				list.append(y)
		thorns[z] = list
	for z in d:
		decor_by_layer.append([])
	for def in lv.decor:
		var sz: Array = DECOR_SIZE.get(def.kind, [1.0, 2.0, 0.1])
		var s: float = def.scale if def.scale != 0.0 else 1.0
		var di := DecorInfo.new()
		di.kind = def.kind
		var p: V3 = def.pos
		di.px = p.x
		di.py = p.y
		di.pz = p.z
		di.scale = s
		di.seed = def.seed
		di.x0 = p.x - sz[0] * s
		di.x1 = p.x + sz[0] * s
		di.y0 = p.y - sz[2] * s - 0.05
		di.y1 = p.y + sz[1] * s
		di.z = clampi(floori(p.z), 0, d - 1)
		di.live = LIVE_DECOR.has(di.kind)
		decor.append(di)
		decor_by_layer[di.z].append(di)
		if di.live:
			live_decor.append(di)
	content = PackedByteArray()
	content.resize(w * h)
	for i in w * h:
		if front[i] != Level.NO_DEPTH or lv.thorn_col[i] != 0:
			content[i] = 1
	for di in decor:
		for y in range(maxi(0, floori(di.y0)), mini(h - 1, floori(di.y1)) + 1):
			for x in range(maxi(0, floori(di.x0)), mini(w - 1, floori(di.x1)) + 1):
				content[x + w * y] = 1


func mat(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= w or y >= h or z >= d:
		return Level.MAT_EMPTY
	return lv.cells[x + w * (y + h * z)]


func solid(x: int, y: int, z: int) -> bool:
	return Level.is_solid_mat(mat(x, y, z))


func front_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return Level.NO_DEPTH
	return front[x + w * y]


func has_content(x0: int, y0: int, x1: int, y1: int) -> bool:
	for y in range(maxi(0, y0), mini(h - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			if content[x + w * y] != 0:
				return true
	return false


func _visible(z: int, sx: int, sy: int, ex: int, ey: int) -> bool:
	var fs := front_at(sx, sy)
	var fe := front_at(ex, ey)
	return fs == z or fe == Level.NO_DEPTH or fe > z


func _run(out: Array, x0: int, y0: int, x1: int, y1: int, side: int, z: int, seed: int) -> void:
	var r := Run.new()
	r.x0 = x0
	r.y0 = y0
	r.x1 = x1
	r.y1 = y1
	r.side = side
	r.z = z
	r.seed = PageRand.i32(seed)
	out.append(r)


func _build_edges(z: int) -> Array:
	var out: Array = []
	for side in [TOP, BOTTOM]:
		var dy := 1 if side == TOP else -1
		for y in h:
			var start := -1
			for x in w + 1:
				var is_edge := x < w and solid(x, y, z) and not solid(x, y + dy, z) and _visible(z, x, y, x, y + dy)
				if is_edge and start < 0:
					start = x
				if not is_edge and start >= 0:
					var ey := y + 1 if side == TOP else y
					_run(out, start, ey, x, ey, side, z, start * 7349 + ey * 3911 + z * 101 + side * 17)
					start = -1
	for side in [LEFT, RIGHT]:
		var dx := -1 if side == LEFT else 1
		for x in w:
			var start := -1
			for y in h + 1:
				var is_edge := y < h and solid(x, y, z) and not solid(x + dx, y, z) and _visible(z, x, y, x + dx, y)
				if is_edge and start < 0:
					start = y
				if not is_edge and start >= 0:
					var ex := x if side == LEFT else x + 1
					_run(out, ex, start, ex, y, side, z, ex * 5113 + start * 2711 + z * 131 + side * 29)
					start = -1
	return out


func _build_seams(z: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in h:
		for x in w:
			var m := mat(x, y, z)
			if not Level.is_solid_mat(m):
				continue
			var vis := front_at(x, y) == z
			var mr := mat(x + 1, y, z)
			if Level.is_solid_mat(mr) and mr != m and (vis or front_at(x + 1, y) == z):
				out.append_array(PackedInt32Array([x + 1, y, x + 1, y + 1]))
			var mu := mat(x, y + 1, z)
			if Level.is_solid_mat(mu) and mu != m and (vis or front_at(x, y + 1) == z):
				out.append_array(PackedInt32Array([x, y + 1, x + 1, y + 1]))
	return out

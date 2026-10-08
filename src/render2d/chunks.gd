class_name PageChunks
extends RefCounted
## Cached static ink (chunks.ts). The world is laid out as a bitmap on a fixed pixel grid
## (X = x * k, Y = -y * k) cut into square chunks, so chunks always meet on whole pixels
## and never seam. Each chunk keeps up to `variants` boil drawings, each painted once into
## its own SubViewport texture; the first is made the moment a chunk is needed, the rest
## in idle time. The SubViewports live inside the page's own viewport, so a chunk painted
## this frame is rendered before the page that shows it.

const S := 512


class Chunk:
	var i := 0
	var j := 0
	## -1 until probed; 1 if there is nothing to draw.
	var empty := -1
	var vps: Array = [null, null, null]
	var used := 0


var host: Node
## (painter: PagePainter, i: int, j: int, variant: int) -> void
var paint_fn: Callable
## (i: int, j: int) -> bool, true if the chunk has anything to draw.
var probe_fn: Callable
var variants := 3
## Maximum chunk drawings kept alive.
var budget := 64
var i0 := 0
var i1 := -1
var j0 := 0
var j1 := -1
## True when every visible chunk has all of its boil drawings.
var boil_ready := false
## Milliseconds spent painting this frame (for diagnostics).
var paint_ms := 0.0
## Optional (ahead-of-time or boil) paints allowed per frame.
var max_optional := 1
var live := 0

var _map := {}
var _pool: Array[SubViewport] = []
var _frame := 0
var _to_clear: Array[PagePainter] = []


func _init(host_: Node, paint: Callable, probe: Callable) -> void:
	host = host_
	paint_fn = paint
	probe_fn = probe


func clear() -> void:
	for c in _map.values():
		for v in 3:
			if c.vps[v] != null:
				_release(c.vps[v])
				c.vps[v] = null
	_map.clear()
	live = 0
	boil_ready = false


## Drops pooled viewports too.
func purge() -> void:
	clear()
	for vp in _pool:
		vp.queue_free()
	_pool.clear()


static func _key(i: int, j: int) -> int:
	return (i + 4096) * 8192 + (j + 4096)


func _chunk(i: int, j: int) -> Chunk:
	var key := _key(i, j)
	var c: Chunk = _map.get(key)
	if c == null:
		c = Chunk.new()
		c.i = i
		c.j = j
		_map[key] = c
	if c.empty < 0:
		c.empty = 0 if probe_fn.call(i, j) else 1
	return c


func _acquire() -> SubViewport:
	live += 1
	if not _pool.is_empty():
		return _pool.pop_back()
	var vp := SubViewport.new()
	vp.size = Vector2i(S, S)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
	host.add_child(vp)
	var root := Node2D.new()
	vp.add_child(root)
	vp.set_meta("painter", PagePainter.new(root.get_canvas_item()))
	return vp


func _release(vp: SubViewport) -> void:
	live -= 1
	var pt: PagePainter = vp.get_meta("painter")
	pt.begin()
	pt.end()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _pool.size() < 8:
		_pool.append(vp)
	else:
		vp.queue_free()


func _render(c: Chunk, v: int) -> void:
	var t0 := Time.get_ticks_usec()
	var vp := _acquire()
	var pt: PagePainter = vp.get_meta("painter")
	pt.begin()
	paint_fn.call(pt, c.i, c.j, v)
	pt.end()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_to_clear.append(pt)
	c.vps[v] = vp
	paint_ms += (Time.get_ticks_usec() - t0) / 1000.0


## Makes sure the visible chunks exist and spends spare time on boil drawings and a ring
## of chunks around the view. `idle_ms` caps the optional work.
func prepare(a0: int, a1: int, b0: int, b1: int, idle_ms: float, want_variants: int) -> void:
	_frame += 1
	paint_ms = 0.0
	# Chunks painted last frame have been rendered: free their geometry.
	for pt in _to_clear:
		pt.begin()
		pt.end()
	_to_clear.clear()
	i0 = a0
	i1 = a1
	j0 = b0
	j1 = b1
	var vis: Array[Chunk] = []
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var c := _chunk(i, j)
			c.used = _frame
			if c.empty == 1:
				continue
			vis.append(c)
			if c.vps[0] == null:
				_render(c, 0)
	var start := Time.get_ticks_usec()
	var optional := 0 if paint_ms > 0.0 else max_optional
	var ready := true
	for c in vis:
		for v in range(1, want_variants):
			if c.vps[v] != null:
				continue
			if optional > 0 and idle_ms - (Time.get_ticks_usec() - start) / 1000.0 > 0.0:
				_render(c, v)
				optional -= 1
			else:
				ready = false
	boil_ready = ready and want_variants > 1
	if optional > 0 and idle_ms - (Time.get_ticks_usec() - start) / 1000.0 > 0.0:
		for j in range(j0 - 1, j1 + 2):
			for i in range(i0 - 1, i1 + 2):
				if optional <= 0 or idle_ms - (Time.get_ticks_usec() - start) / 1000.0 <= 0.0:
					break
				if i >= i0 and i <= i1 and j >= j0 and j <= j1:
					continue
				var c := _chunk(i, j)
				c.used = maxi(c.used, _frame - 1)
				if c.empty == 1:
					continue
				if c.vps[0] == null:
					_render(c, 0)
					optional -= 1
	_evict()


func _evict() -> void:
	if live <= budget:
		return
	var list: Array = []
	for c in _map.values():
		if c.vps[0] != null or c.vps[1] != null or c.vps[2] != null:
			list.append(c)
	list.sort_custom(func(a: Chunk, b: Chunk) -> bool: return a.used < b.used)
	# First boil drawings of chunks off screen, then whole chunks, oldest first.
	for c in list:
		if live <= budget:
			break
		if c.used >= _frame:
			continue
		for v in [2, 1]:
			if c.vps[v] != null:
				_release(c.vps[v])
				c.vps[v] = null
	for c in list:
		if live <= budget:
			break
		if c.used >= _frame - 1:
			continue
		for v in 3:
			if c.vps[v] != null:
				_release(c.vps[v])
				c.vps[v] = null


## The texture to show for a chunk this frame, or an empty RID.
func texture_for(i: int, j: int, variant: int) -> RID:
	var c: Chunk = _map.get(_key(i, j))
	if c == null or c.empty == 1:
		return RID()
	var vp: SubViewport = c.vps[variant] if boil_ready else null
	if vp == null:
		vp = c.vps[0]
	return vp.get_texture().get_rid() if vp != null else RID()


## Draws the visible chunks at the world-bitmap offset (ox, oy).
func draw(pt: PagePainter, ox: float, oy: float, variant: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var t := texture_for(i, j, variant)
			if t.is_valid():
				pt.texture(t, Rect2(ox + i * S, oy + j * S, S, S))


## Redraws the cached page inside a pixel rectangle (the caller sets any clip).
func draw_rect(pt: PagePainter, ox: float, oy: float, variant: int, x0: float, y0: float, x1: float, y1: float) -> void:
	var ia := floori((x0 - ox) / S)
	var ib := floori((x1 - ox) / S)
	var ja := floori((y0 - oy) / S)
	var jb := floori((y1 - oy) / S)
	for j in range(ja, jb + 1):
		for i in range(ia, ib + 1):
			var t := texture_for(i, j, variant)
			if not t.is_valid():
				continue
			var cx := ox + i * S
			var cy := oy + j * S
			var sx := maxf(0.0, floorf(x0 - cx))
			var sy := maxf(0.0, floorf(y0 - cy))
			var ex := minf(S, ceilf(x1 - cx))
			var ey := minf(S, ceilf(y1 - cy))
			if ex <= sx or ey <= sy:
				continue
			pt.texture(t, Rect2(cx + sx, cy + sy, ex - sx, ey - sy), Color.WHITE, Rect2(sx, sy, ex - sx, ey - sy))


func stats() -> Dictionary:
	return {"chunks": _map.size(), "canvases": live}

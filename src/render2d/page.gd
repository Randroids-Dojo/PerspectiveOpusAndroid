extends CanvasLayer
## The Score: the world drawn as a living illuminated manuscript, a port of the web
## build's src/render2d (page.ts).
##
## The page is painted into its own SubViewport at full device resolution and shown
## through a TextureRect whose shader cuts the ink-blot wipe, so the Stage shows through
## the hole. Per frame: fixed parchment, sky staves and ink-wash silhouettes in parallax,
## the cached static page (voxels by depth layer, thorns and decor painted back to front
## into chunk SubViewports, three boil drawings each), then live things in painter's
## order. Anything live that sits behind scenery gets the cached page redrawn over it,
## clipped to the cells in front, so depth on the flat page stays correct. Effects,
## ambient particles, the vignette and the wipe finish the frame.

const CHUNK := PageChunks.S

var _vp: SubViewport
var _root: Node2D
var _display: TextureRect
var _wipe_mat: ShaderMaterial
var _overlay: Node2D
var _pt: PagePainter
var _opt: PagePainter

var _game: Sim
var _palette: Dictionary
var _tones: PageTones
var _world: PageWorld
var _env: PageEnv
var _backdrop := PageBackdrop.new()
var _fx := PageFx.new()
var _quaver := PageQuaver.new()
var _wipe := PageWipe.new()
var _chunks: PageChunks
var _chunk_k := 0.0
var _chunk_px := 1.0
var _pats_dpr := -1.0
var _w := 844.0
var _h := 390.0
var _dpr := 1.0
var _W := 844
var _H := 390
## Height Quaver last stood at (the backdrop settles on it).
var _ground_y := NAN
var _shown := true
var _ghosts: Array = []
## --page-stats prints the page's frame cost once a second.
var _print_stats := OS.get_cmdline_user_args().has("--page-stats")
var _sec := {}
var _dw := {}
var _sec_t := 0


func _mark(name: String) -> void:
	if not _print_stats:
		return
	var t := Time.get_ticks_usec()
	_sec[name] = _sec.get(name, 0.0) * 0.95 + (t - _sec_t) / 1000.0 * 0.05
	_sec_t = t
## Frame cost in milliseconds (for measurement).
var stats := {"ms": 0.0, "avg": 0.0, "max": 0.0, "paint": 0.0, "frames": 0, "chunks": 0, "canvases": 0}


func _ready() -> void:
	layer = 1
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.gui_disable_input = true
	_vp.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root = Node2D.new()
	_vp.add_child(_root)
	_pt = PagePainter.new(_root.get_canvas_item())

	_display = TextureRect.new()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture = _vp.get_texture()
	var sh := Shader.new()
	sh.code = PageWipe.SHADER
	_wipe_mat = ShaderMaterial.new()
	_wipe_mat.shader = sh
	_display.material = _wipe_mat
	add_child(_display)

	_overlay = Node2D.new()
	add_child(_overlay)
	_opt = PagePainter.new(_overlay.get_canvas_item())
	_chunks = PageChunks.new(_vp, _paint_chunk, _probe_chunk)


func _exit_tree() -> void:
	if _pt != null:
		_pt.free_items()
	if _opt != null:
		_opt.free_items()


# ---------------------------------------------------------------- the renderer contract

func resize(view: View) -> void:
	var changed_dpr := not is_equal_approx(view.dpr, _dpr)
	_w = view.w
	_h = view.h
	_dpr = view.dpr
	_W = roundi(_w * _dpr)
	_H = roundi(_h * _dpr)
	if _vp == null:
		return
	_vp.size = Vector2i(_W, _H)
	_display.position = Vector2.ZERO
	_display.size = Vector2(_w, _h)
	_overlay.scale = Vector2(1.0 / _dpr, 1.0 / _dpr)
	if changed_dpr and _tones != null:
		_make_patterns()
		_chunks.purge()
		_chunk_k = 0.0


func load_level(game: Sim, palette: Dictionary) -> void:
	_game = game
	_palette = palette
	var lv := game.level
	_tones = PageTones.new(palette, lv.d)
	_world = PageWorld.new(lv)
	_env = PageEnv.new()
	_env.world = _world
	_env.tones = _tones
	_pats_dpr = -1.0
	_make_patterns()
	_backdrop.load_palette(_tones)
	_chunks.clear()
	_chunk_k = 0.0
	_fx.set_tones(_tones)
	_quaver.reset()
	_env.cache.clear()
	_ground_y = NAN


func set_world_visible(v: bool) -> void:
	if v == _shown:
		return
	_shown = v
	visible = v
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED


func render(game: Sim, view: View, frame: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	_sec_t = t0
	if game != _game or _env == null:
		if _palette.is_empty():
			return
		load_level(game, _palette)
	if view.dpr != _dpr or roundi(view.w * view.dpr) != _W or roundi(view.h * view.dpr) != _H:
		resize(view)
	var env := _env
	var T := _tones
	var world := _world
	var W := float(_W)
	var H := float(_H)
	var dpr := _dpr
	var reduce := view.reduce_motion
	var quality: String = frame.quality
	env.now = frame.now
	env.time = game.time
	env.quality = quality

	# The cache is laid out for one scale; rebuild when it changes.
	var k := view.ppu * dpr
	if absf(k - _chunk_k) > 1e-6:
		_chunks.clear()
		_chunk_k = k
		_chunk_px = dpr * PageEnv.stroke_scale(view.ppu)

	var boil := 0 if reduce else floori(float(frame.now) * 8.0)
	var variants := 1 if quality == "low" or reduce else 3
	var variant := boil % 3 if variants > 1 else 0
	var sx := 0.0
	var sy := 0.0
	if not reduce and view.shake > 0.0:
		var s := view.shake * view.shake * 7.0 * dpr
		sx = roundf(sin(frame.now * 61.3) * s)
		sy = roundf(cos(frame.now * 47.9) * s)
	var ox := roundf(W / 2.0 - view.c2.x * k) + sx
	var oy := roundf(H / 2.0 + view.c2.y * k) + sy
	var p := PageEnv.Proj.new()
	p.k = k
	p.ox = ox
	p.oy = oy
	p.dpr = dpr
	p.px = _chunk_px
	p.boil = boil

	# Events and simulation-driven state.
	var events: Array = frame.events
	if not events.is_empty():
		_fx.handle(events, game, reduce)
		for e in events:
			if e.t == "respawn":
				_quaver.respawn_at = game.time
	_fx.update(frame.game_dt)
	_quaver.update(game, frame)
	env.cache.next_frame()
	_mark("setup")

	# Paper and the world behind the world.
	_pt.begin()
	_pt.use(PagePainter.NORMAL)
	_backdrop.draw_paper(_pt, W, H)
	var pl := game.player
	if pl.grounded or is_nan(_ground_y):
		_ground_y = pl.pos.y
	if pl.dead > 0.0:
		_ground_y = game.respawn_pos.y
	_backdrop.lite = quality == "low"
	_backdrop.draw(_pt, view, W, H, world.w, frame.now, _ground_y)
	_mark("backdrop")

	# The cached page.
	var i0 := floori(-ox / CHUNK)
	var i1 := floori((W - ox) / CHUNK)
	var j0 := floori(-oy / CHUNK)
	var j1 := floori((H - oy) / CHUNK)
	var vis := (i1 - i0 + 1) * (j1 - j0 + 1)
	var ring := (i1 - i0 + 3) * (j1 - j0 + 3) - vis
	_chunks.variants = variants
	_chunks.budget = ceili(vis * variants + ring + 10)
	_chunks.prepare(i0, i1, j0, j1, 3.0 if quality == "high" else 1.8, variants)
	_pt.use(PagePainter.PREMUL)
	_chunks.draw(_pt, ox, oy, variant)
	_mark("chunks")

	# Live things in painter's order, back to front.
	_pt.use(PagePainter.NORMAL)
	var vx0 := (0.0 - ox) / k
	var vx1 := (W - ox) / k
	var vy0 := (oy - H) / k
	var vy1 := oy / k
	var list: Array = []
	PageEntities.collect(list, _pt, game, env, frame, vx0 - 1, vy0 - 1, vx1 + 1, vy1 + 1)
	for di in world.live_decor:
		if di.x1 < vx0 or di.x0 > vx1 or di.y1 < vy0 or di.y0 > vy1:
			continue
		var dd := PageEntities.Drawable.new(di.z + 0.2, di.x0, di.y0, di.x1, di.y1,
			func(pp: PageEnv.Proj) -> void: _live_decor(env, pp, di, boil))
		dd.tag = di.kind
		list.append(dd)
	if _quaver.visible:
		var q := _quaver
		var dq := PageEntities.Drawable.new(q.z - 0.3, q.x - 0.55, q.y - 0.1, q.x + 0.6, q.y + 1.45,
			func(pp: PageEnv.Proj) -> void: q.draw(_pt, pp, env, game, frame))
		dq.tag = "quaver"
		dq.core(q.x - 0.28, q.y + 0.02, q.x + 0.28, q.y + 0.84)
		dq.ghost = func(pp: PageEnv.Proj) -> void: q.ghost(_pt, pp, env, game, frame)
		list.append(dq)
	# Stable, nearest last (the web build's sort).
	var keyed: Array = []
	for i in list.size():
		keyed.append([list[i].z, i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	_mark("collect")
	_ghosts.clear()
	for e in keyed:
		var d: PageEntities.Drawable = list[e[1]]
		_pt.ensure(PagePainter.NORMAL)
		var td := Time.get_ticks_usec()
		d.draw.call(p)
		_pt.reset_state()
		_occlude(d, p, variant)
		if _print_stats:
			var nm := d.tag
			_dw[nm] = _dw.get(nm, 0.0) + (Time.get_ticks_usec() - td) / 1000.0
	for g in _ghosts:
		var d: PageEntities.Drawable = g[0]
		var cells: PackedInt32Array = g[1]
		var rects := PackedVector4Array()
		for i in range(0, cells.size(), 2):
			var X := p.ox + cells[i] * k
			var Y := p.oy - (cells[i + 1] + 1) * k
			rects.append(Vector4(X, Y, X + k, Y + k))
		_pt.use(PagePainter.CLIP, rects)
		d.ghost.call(p)
		_pt.reset_state()
	_pt.ensure(PagePainter.NORMAL)
	_mark("live")

	_draw_water(game, p, frame)
	_fx.draw(_pt, p)
	_mark("fx")
	# Ambient drift runs on real time but holds still while the game is paused.
	_fx.ambient(_pt, frame.dt if frame.game_dt > 0.0 else 0.0, view.c2.x, view.c2.y, view.ppu, W, H, dpr, quality, frame.now)
	if quality != "low":
		_backdrop.draw_vignette(_pt, W, H)
	_mark("ambient")

	_wipe.compute(W, H, view.wipe_origin * dpr, view.wipe, frame.now * 0.5, dpr)
	_wipe.draw_page(_pt, T)
	_pt.end()
	_wipe.shader_params(_wipe_mat, T, W, H)
	_opt.begin()
	_opt.use(PagePainter.NORMAL)
	_wipe.draw_over(_opt, T)
	_opt.end()
	_mark("wipe")

	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats.ms = ms
	stats.frames += 1
	stats.avg = ms if stats.frames < 2 else stats.avg * 0.95 + ms * 0.05
	stats.max = maxf(stats.max * 0.995, ms)
	stats.paint = _chunks.paint_ms
	var cs := _chunks.stats()
	stats.chunks = cs.chunks
	stats.canvases = cs.canvases
	if _print_stats and stats.frames % 60 == 0:
		for key in _dw:
			_dw[key] = snappedf(_dw[key] / 60.0, 0.001)
		print(_dw)
		_dw.clear()
		print("page ms avg %.2f max %.2f paint %.2f chunks %d canvases %d " % [stats.avg, stats.max, stats.paint, stats.chunks, stats.canvases], _sec)


## Moving decor, recorded once per boil frame (flames flicker and banners wave on the
## boil, like the ink); gears are recorded unturned and turned smoothly when replayed.
func _live_decor(env: PageEnv, p: PageEnv.Proj, di: PageWorld.DecorInfo, boil: int) -> void:
	var key := "L%d.%d" % [di.get_instance_id(), boil]
	var rec: Variant = env.cache.lookup(key)
	if di.kind == "gear":
		var gt := PageDecor.gear_turn(di, env.time)
		if rec == null:
			_pt.begin_record()
			PageDecor.gear_part = 1
			PageDecor.draw(_pt, env, p.local(di.px, di.py), di, boil, PageDecor.LIVE)
			PageDecor.gear_part = 0
			rec = _pt.end_record()
			env.cache.store(key, rec)
		var centre := Vector2(0, -gt.x * di.scale * p.k)
		var base := Vector2(p.ox + di.px * p.k, p.oy - di.py * p.k)
		_pt.replay(rec, Transform2D(0.0, base + centre) * Transform2D(-gt.y, Vector2.ZERO) * Transform2D(0.0, -centre))
		PageDecor.gear_part = 2
		PageDecor.draw(_pt, env, p, di, boil, PageDecor.LIVE)
		PageDecor.gear_part = 0
		return
	if rec == null:
		_pt.begin_record()
		PageDecor.draw(_pt, env, p.local(0, 0), di, boil, PageDecor.LIVE)
		rec = _pt.end_record()
		env.cache.store(key, rec)
	_pt.replay(rec, Transform2D(0.0, Vector2(p.ox, p.oy)))


# ---------------------------------------------------------------- chunk cache hooks

func _make_patterns() -> void:
	if _tones == null or is_equal_approx(_pats_dpr, _dpr):
		return
	_env.pats = PageEnv.Patterns.new(_tones, _dpr)
	_pats_dpr = _dpr


func _paint_chunk(pt: PagePainter, i: int, j: int, variant: int) -> void:
	if _env == null:
		return
	var k := _chunk_k
	var p := PageEnv.Proj.new()
	p.k = k
	p.ox = -i * CHUNK
	p.oy = -j * CHUNK
	p.dpr = _dpr
	p.px = _chunk_px
	p.boil = variant
	var x0 := float(i * CHUNK) / k
	var x1 := float((i + 1) * CHUNK) / k
	var y0 := -float((j + 1) * CHUNK) / k
	var y1 := -float(j * CHUNK) / k
	PageTerrain.paint_static(pt, _env, p, x0, y0, x1, y1, variant)
	PageTerrain.granulate(pt, _env, p, CHUNK, CHUNK)


func _probe_chunk(i: int, j: int) -> bool:
	if _world == null:
		return false
	var k := _chunk_k
	var x0 := float(i * CHUNK) / k
	var x1 := float((i + 1) * CHUNK) / k
	var y0 := -float((j + 1) * CHUNK) / k
	var y1 := -float(j * CHUNK) / k
	return _world.has_content(floori(x0) - 1, floori(y0) - 1, ceili(x1) + 1, ceili(y1) + 1)


# ---------------------------------------------------------------- occlusion

func _thorns_near(d: PageEntities.Drawable, lim: float) -> bool:
	var world := _world
	var z := 0
	while z < world.d and z + 1 <= lim:
		var th: PackedInt32Array = world.thorns[z]
		for i in range(0, th.size(), 2):
			if th[i] + 1 > d.x0 and th[i] < d.x1 and th[i + 1] + 1 > d.y0 and th[i + 1] < d.y1:
				return true
		z += 1
	return false


func _nearer_decor(d: PageEntities.Drawable, lim: float) -> Array:
	var out: Array = []
	for di in _world.decor:
		if di.z + 1 <= lim and di.x1 > d.x0 and di.x0 < d.x1 and di.y1 > d.y0 and di.y0 < d.y1:
			out.append(di)
	return out


## Redraws nearer decor and thorns over a thing, clipped to its bounds.
func _redraw_decor(d: PageEntities.Drawable, p: PageEnv.Proj, variant: int, lim: float, decor: Array, rect: Vector4) -> void:
	var world := _world
	_pt.use(PagePainter.CLIP, PackedVector4Array([rect]))
	var pen := PageTerrain.Pen.new()
	pen.painter = _pt
	pen.env = _env
	pen.p = p.copy()
	pen.p.px = _chunk_px
	pen.p.boil = variant
	pen.variant = variant
	for z in range(world.d - 1, -1, -1):
		if z + 1 > lim:
			continue
		pen.z = z
		pen.L = _tones.layers[z]
		var th: PackedInt32Array = world.thorns[z]
		for i in range(0, th.size(), 2):
			if th[i] + 1 > d.x0 and th[i] < d.x1 and th[i + 1] + 1 > d.y0 and th[i + 1] < d.y1:
				PageTerrain.draw_thorn(pen, th[i], th[i + 1])
		for di in decor:
			if di.z == z:
				PageDecor.draw(_pt, _env, pen.p, di, variant, PageDecor.STATIC)


## Redraws whatever static scenery stands in front of a live thing: decor and thorns
## nearer than it, then the cached page clipped to the nearer voxel cells. Queues the
## thing's ghost if solid scenery hid it.
func _occlude(d: PageEntities.Drawable, p: PageEnv.Proj, variant: int) -> void:
	var world := _world
	if d.z < 0.98:
		return
	var lim := d.z + 0.02
	var k := p.k
	if d.has_core:
		var covered := false
		for y in range(maxi(0, floori(d.cy0)), mini(world.h - 1, floori(d.cy1)) + 1):
			for x in range(maxi(0, floori(d.cx0)), mini(world.w - 1, floori(d.cx1)) + 1):
				var f := world.front[x + world.w * y]
				if f != Level.NO_DEPTH and f + 1 <= lim:
					covered = true
					break
			if covered:
				break
		if not covered:
			# Decor and thorns in front still overlap it (a tuft of grass before Quaver).
			var dec := _nearer_decor(d, lim)
			if dec.is_empty() and not _thorns_near(d, lim):
				return
			var rx0 := floorf(p.ox + d.x0 * k) - 2
			var ry0 := floorf(p.oy - d.y1 * k) - 2
			_redraw_decor(d, p, variant, lim, dec, Vector4(rx0, ry0, rx0 + ceilf((d.x1 - d.x0) * k) + 4, ry0 + ceilf((d.y1 - d.y0) * k) + 4))
			_pt.use(PagePainter.NORMAL)
			return
	var cells := PackedInt32Array()
	for y in range(maxi(0, floori(d.y0)), mini(world.h - 1, floori(d.y1)) + 1):
		for x in range(maxi(0, floori(d.x0)), mini(world.w - 1, floori(d.x1)) + 1):
			var f := world.front[x + world.w * y]
			if f != Level.NO_DEPTH and f + 1 <= lim:
				cells.append(x)
				cells.append(y)
	var decor := _nearer_decor(d, lim)
	var thorns := _thorns_near(d, lim)
	if cells.is_empty() and decor.is_empty() and not thorns:
		return
	var bx0 := floorf(p.ox + d.x0 * k) - 2
	var bx1 := ceilf(p.ox + d.x1 * k) + 2
	var by0 := floorf(p.oy - d.y1 * k) - 2
	var by1 := ceilf(p.oy - d.y0 * k) + 2
	if not decor.is_empty() or thorns:
		_redraw_decor(d, p, variant, lim, decor, Vector4(bx0, by0, bx1, by1))
	if not cells.is_empty():
		var g := maxf(1.0, roundf(p.dpr))
		var rects := PackedVector4Array()
		for i in range(0, cells.size(), 2):
			var X := p.ox + cells[i] * k
			var Y := p.oy - (cells[i + 1] + 1) * k
			rects.append(Vector4(maxf(bx0, X - g), maxf(by0, Y - g), minf(bx1, X + k + g), minf(by1, Y + k + g)))
		if rects.size() > PagePainter.MAX_RECTS:
			rects = PackedVector4Array([Vector4(bx0, by0, bx1, by1)])
		_pt.use(PagePainter.CLIP_PREMUL, rects)
		_chunks.draw_rect(_pt, p.ox, p.oy, variant, bx0, by0, bx1, by1)
	_pt.use(PagePainter.NORMAL)
	# Only solid scenery hides a thing enough to need its ghost; decor stays see-through.
	if d.ghost.is_valid() and not cells.is_empty():
		_ghosts.append([d, cells])


# ---------------------------------------------------------------- water

## Still water across the level at the water line, tinting whatever is below it.
func _draw_water(game: Sim, p: PageEnv.Proj, frame: Dictionary) -> void:
	var lv := game.level
	if not lv.has_water():
		return
	var T := _tones
	var W := float(_W)
	var H := float(_H)
	var Y := p.oy - lv.water * p.k
	if Y > H:
		return
	var top := maxf(0.0, Y)
	var water := PageTones.rgb(T.pal.water) if T.pal.get("water") != null else PageTones.rgb(T.pal.washFar)
	_pt.fill_rect(0, top, W, H - top, PageTones.alpha(PageTones.mix(water, T.paper, 0.35 if T.inv else 0.45), 0.55))
	var t: float = frame.now
	var step := 0.55 * p.k
	var rows := ceili((H - top) / (0.22 * p.k))
	var lc := PageTones.alpha(PageTones.mix(T.ink_far, water, 0.3), 0.55)
	var lw := maxf(0.8, 1.1 * p.px)
	for r in mini(rows, 30):
		var y := Y + 0.05 * p.k + r * 0.22 * p.k * (1.0 + r * 0.08)
		if y < 0.0:
			continue
		var drift := fmod(t * (12.0 + r * 3.0) * p.dpr, step) * (1.0 if r % 2 else -1.0)
		var x := -step + drift - fmod(fmod(p.ox, step) + step, step)
		while x < W + step:
			var h := PageRand.hash01(PageInk.jround((x - p.ox) / step), r, 3)
			if h >= 0.45:
				var length := step * (0.3 + h * 0.6)
				_pt.seg(x, y, x + length, y + sin(x * 0.01 + r) * 0.5, lw, lc)
			x += step
	var edge := PackedVector2Array()
	var x2 := 0.0
	while x2 <= W:
		edge.append(Vector2(x2, Y + sin(x2 * 0.02 + t * 1.5) * 1.2 * p.dpr))
		x2 += 12.0 * p.dpr
	_pt.stroke(edge, maxf(1.0, 1.5 * p.px), PageTones.alpha(T.ink_far, 0.8), false, false)

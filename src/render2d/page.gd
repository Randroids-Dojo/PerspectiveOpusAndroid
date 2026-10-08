extends CanvasLayer
## Placeholder Score: flat columns. The real renderer replaces this file.

var _canvas := Control.new()
var _game: Sim
var _view: View
var _palette: Dictionary


func _ready() -> void:
	layer = 1
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_page)
	add_child(_canvas)


func resize(_view_: View) -> void:
	pass


func load_level(game: Sim, palette: Dictionary) -> void:
	_game = game
	_palette = palette


func set_world_visible(v: bool) -> void:
	visible = v


func render(game: Sim, view: View, _frame: Dictionary) -> void:
	_game = game
	_view = view
	_canvas.queue_redraw()


func _draw_page() -> void:
	if _game == null or _view == null:
		return
	var v := _view
	var lv := _game.level
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(v.w, v.h)), Color(_palette.paper))
	var s := v.ppu
	for y in lv.h:
		for x in lv.w:
			var fz := lv.front[x + lv.w * y]
			if fz == Level.NO_DEPTH:
				continue
			var p := v.world_to_page(x, y + 1)
			_canvas.draw_rect(Rect2(p, Vector2(s + 0.5, s + 0.5)), Color(_palette.washNear).lerp(Color(_palette.washFar), fz / 7.0))
	var pl := _game.player
	var pp := v.world_to_page(pl.pos.x - Sim.HW, pl.pos.y + Sim.PH)
	_canvas.draw_rect(Rect2(pp, Vector2(0.6 * s, 0.86 * s)), Color(_palette.ink))
	if v.wipe > 0:
		# The real page cuts an ink-edged hole; the placeholder draws a ring.
		_canvas.draw_arc(v.wipe_origin, Vector2(v.w, v.h).length() * v.wipe, 0, TAU, 64, Color(_palette.ink), 3)

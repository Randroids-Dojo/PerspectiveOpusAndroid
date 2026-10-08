class_name UiMenuItem
extends Control
## One row of a UiMenu: the CSS .menu-item with its label, value or detail, or a
## programme row. Draws itself in the current world's colours.

const FOCUS_SECONDS := 0.3

var menu: UiMenu
var i := 0
var it: Dictionary
var focused := false
## Focus animation, 0..1: colour, glyph scale and underline width follow it.
var f := 0.0
var _pressed := false
var _press_pos := Vector2.ZERO


func _init(m: UiMenu, idx: int, item: Dictionary) -> void:
	menu = m
	i = idx
	it = item
	mouse_filter = Control.MOUSE_FILTER_PASS


func label_text() -> String:
	var l = it.get("label", "")
	return l.call() if l is Callable else String(l)


func _is_back() -> bool:
	return it.get("cls", "") == "back"


func _disabled() -> bool:
	var d = it.get("disabled")
	return d is Callable and d.call()


func _process(dt: float) -> void:
	var target := 1.0 if focused else 0.0
	if f != target:
		f = move_toward(f, target, dt / FOCUS_SECONDS)
		queue_redraw()


# ---------------------------------------------------------------- metrics

func _label_font() -> Font:
	return UiStyle.display_i if _is_back() else UiStyle.display


func _label_size() -> int:
	return roundi(menu.fs * (1.05 if _is_back() else 1.22))


func _value_size() -> int:
	return roundi(menu.fs * menu.value_scale)


func _value_font() -> Font:
	return UiStyle.spaced(UiStyle.body, _value_size(), menu.value_em)


func _detail_size() -> int:
	return roundi(menu.fs * 0.72)


## [above baseline, below baseline] of the first row.
func _row() -> Vector2:
	var lf := _label_font()
	var ls := _label_size()
	var lh := ls * 1.1
	var above := UiStyle.baseline(lf, ls, lh)
	var below := lh + 1.0 - above
	if it.has("value") or it.has("bar"):
		var vf := _value_font()
		var vs := _value_size()
		above = maxf(above, vf.get_ascent(vs))
		below = maxf(below, vf.get_descent(vs))
	return Vector2(above, below)


func measure() -> float:
	if it.get("kind", "") == "prog":
		return _prog_measure()
	var r := _row()
	var h := menu.pad.x + r.x + r.y + menu.pad.z
	if it.has("detail") and not menu.inline_detail:
		# The detail sits in the grid's second row: an 18 px row gap, then margin-top -2.
		var ds := _detail_size()
		h += 16.0 + UiStyle.body_i.get_ascent(ds) + UiStyle.body_i.get_descent(ds)
	return h


func natural_width() -> float:
	if it.get("kind", "") == "prog":
		return 600.0
	var w := UiStyle.width(_label_font(), _label_size(), label_text())
	if it.has("value"):
		w += 18.0 + UiStyle.width(_value_font(), _value_size(), "<  " + String(it.value.call()) + "  >")
	elif it.has("bar"):
		w += 18.0 + 120.0
	if it.has("detail"):
		var dw := UiStyle.width(UiStyle.body_i, _detail_size(), String(it.detail.call()))
		w = w + 12.0 + dw if menu.inline_detail else maxf(w, dw)
	return w + menu.pad.w + menu.pad.y


# ---------------------------------------------------------------- drawing

func _ink() -> Color:
	return UiStyle.c("fg").lerp(UiStyle.c("accent"), UiStyle.ease(f))


func _draw() -> void:
	var dim := 0.4 if _disabled() else 1.0
	if it.get("kind", "") == "prog":
		_prog_draw(dim)
	else:
		_item_draw(dim)
	_draw_mark(dim)


func _draw_mark(dim: float) -> void:
	if f <= 0.0:
		return
	var s := 0.4 + 0.6 * UiStyle.ease(f)
	var sz := Vector2(14, 18) * s
	var col := UiStyle.c("accent")
	col.a *= clampf(f / 0.83, 0.0, 1.0) * dim
	UiStyle.draw_glyph(self, Rect2(Vector2(6.0 + 7.0 - sz.x / 2.0, size.y / 2.0 - sz.y / 2.0), sz), col)


func _item_draw(dim: float) -> void:
	var ink := _ink()
	ink.a *= dim
	var r := _row()
	var base := menu.pad.x + r.x
	var lf := _label_font()
	var ls := _label_size()
	var label := label_text()
	var x := menu.pad.w
	draw_string(lf, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, ink)
	if it.get("underline", true) and f > 0.0:
		var lh := ls * 1.1
		var top := base - UiStyle.baseline(lf, ls, lh)
		var uw := UiStyle.width(lf, ls, label) * UiStyle.bezier(UiStyle.EASE, f / (0.35 / FOCUS_SECONDS))
		draw_rect(Rect2(x, top + lh, uw, 1.0), ink)
	var right := size.x - menu.pad.y
	if it.has("value") or it.has("bar"):
		var vcol := UiStyle.c("fg_dim").lerp(UiStyle.c("accent"), UiStyle.ease(f))
		vcol.a *= dim
		var vf := _value_font()
		var vs := _value_size()
		var arrow_r := ""
		var arrow_l := ""
		if focused:
			arrow_l = "‹  "
			arrow_r = "  ›"
		var awr := UiStyle.width(vf, vs, arrow_r)
		var awl := UiStyle.width(vf, vs, arrow_l)
		var acol := Color(vcol.r, vcol.g, vcol.b, vcol.a * 0.6)
		var vx := right - awr
		if it.has("bar"):
			var bw := 85.0
			_draw_bar(Vector2(vx - bw, base), float(it.bar.call()), vcol, vs)
			vx -= bw
		else:
			var v := String(it.value.call())
			var vw := UiStyle.width(vf, vs, v)
			draw_string(vf, Vector2(vx - vw, base), v, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, vcol)
			vx -= vw
		if focused:
			draw_string(vf, Vector2(right - awr, base), arrow_r, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, acol)
			draw_string(vf, Vector2(vx - awl, base), arrow_l, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, acol)
	if it.has("detail"):
		var ds := _detail_size()
		var dcol := UiStyle.c("fg_dim")
		dcol.a *= dim
		if menu.inline_detail:
			# Short screens: the detail follows the label on its row.
			var dx := x + UiStyle.width(lf, ls, label) + 12.0
			draw_string(UiStyle.body_i, Vector2(dx, base), String(it.detail.call()), HORIZONTAL_ALIGNMENT_LEFT, -1, ds, dcol)
			return
		var top := base + r.y + 16.0
		draw_string(UiStyle.body_i, Vector2(x, top + UiStyle.body_i.get_ascent(ds)), String(it.detail.call()), HORIZONTAL_ALIGNMENT_LEFT, -1, ds, dcol)


## Ten filled or hollow dots, the web build's "●●●●●●●●○○" volume bar.
func _draw_bar(at: Vector2, v: float, col: Color, vs: int) -> void:
	var n := roundi(v * 10.0)
	var pitch := 8.5
	var r := 2.75 * vs / 12.0
	var cy := at.y - vs * 0.33
	for d in 10:
		var c := Vector2(at.x + pitch * d + pitch / 2.0, cy)
		if d < n:
			draw_circle(c, r, col, true, -1.0, true)
		else:
			draw_arc(c, r - 0.45, 0, TAU, 20, col, 0.9, true)


# ---------------------------------------------------------------- programme rows

func _prog_fonts() -> Dictionary:
	var fs := menu.fs
	var open: bool = it.get("open", false)
	return {
		"num": UiStyle.display_i, "num_size": roundi(fs * (1.15 if UiStyle.compact else 1.5)),
		"title": UiStyle.display if open else UiStyle.display_i,
		"title_size": roundi(fs * ((1.1 if UiStyle.compact else 1.35) if open else 1.1)),
		"tempo_size": roundi(fs * 0.72),
	}


func _prog_metrics() -> Vector2:
	var p := _prog_fonts()
	var nf: Font = p.num
	var ns: int = p.num_size
	var tf: Font = p.title
	var ts: int = p.title_size
	var above := maxf(nf.get_ascent(ns), UiStyle.baseline(tf, ts, ts))
	var below := maxf(nf.get_descent(ns), ts - UiStyle.baseline(tf, ts, ts))
	if not UiStyle.compact:
		var tz: int = p.tempo_size
		below += 2.0 + UiStyle.body_i.get_ascent(tz) + UiStyle.body_i.get_descent(tz)
	return Vector2(above, below)


func _prog_measure() -> float:
	var m := _prog_metrics()
	var py := 5.0 if UiStyle.compact else 10.0
	return py + m.x + m.y + py + 1.0


func _prog_draw(dim: float) -> void:
	var p := _prog_fonts()
	var m := _prog_metrics()
	var py := 5.0 if UiStyle.compact else 10.0
	var base := py + m.x
	var left := 28.0 if UiStyle.compact else 30.0
	var right := size.x - (12.0 if UiStyle.compact else 14.0)
	var edge := UiStyle.fade(UiStyle.c("card_edge"), 0.4)
	draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), edge)
	var dimc := UiStyle.c("fg_dim")
	dimc.a *= dim
	var ink := _ink()
	ink.a *= dim
	draw_string(p.num, Vector2(left, base), String(it.num), HORIZONTAL_ALIGNMENT_LEFT, -1, p.num_size, dimc)
	var mx := left + 3.2 * menu.fs + 18.0
	var title: String = it.title if it.open else "Not yet performed"
	draw_string(p.title, Vector2(mx, base), title, HORIZONTAL_ALIGNMENT_LEFT, -1, p.title_size, ink)
	if it.open:
		var tz: int = p.tempo_size
		if UiStyle.compact:
			var tx: float = mx + UiStyle.width(p.title, p.title_size, title) + 12.0
			draw_string(UiStyle.body_i, Vector2(tx, base), String(it.tempo), HORIZONTAL_ALIGNMENT_LEFT, -1, tz, dimc)
		else:
			# Taller screens stack the tempo under the title (line-height 1, 2 px gap).
			var ts: int = p.title_size
			var title_bottom: float = base - UiStyle.baseline(p.title, ts, ts) + ts
			draw_string(UiStyle.body_i, Vector2(mx, title_bottom + 2.0 + UiStyle.body_i.get_ascent(tz)), String(it.tempo), HORIZONTAL_ALIGNMENT_LEFT, -1, tz, dimc)
	# Seven notes, found ones in the accent colour.
	var gw := 0.7 * menu.fs
	var gh := 0.95 * menu.fs
	var notes: Array = it.notes
	var x0 := right - (gw * 7.0 + 6.0)
	var empty := UiStyle.fade(UiStyle.c("fg"), 0.22)
	empty.a *= dim
	var gold := UiStyle.c("accent")
	gold.a *= dim
	for k in 7:
		var found := k < notes.size() and bool(notes[k])
		UiStyle.draw_glyph(self, Rect2(x0 + k * (gw + 1.0), base + 1.0 - gh, gw, gh), gold if found else empty)
	if not UiStyle.compact and String(it.get("time", "")) != "":
		var tsz := roundi(menu.fs * 0.7)
		var tw := UiStyle.width(UiStyle.body, tsz, it.time)
		draw_string(UiStyle.body, Vector2(right - tw, base + 4.0 + tsz), it.time, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, dimc)


# ---------------------------------------------------------------- input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_pressed = true
			_press_pos = e.global_position
		elif _pressed:
			_pressed = false
			var dragged := menu.scroller != null and menu.scroller.dragged
			if not dragged and Rect2(Vector2.ZERO, size).has_point(e.position):
				menu.clicked(i, e.position.x / maxf(1.0, size.x))
	elif e is InputEventMouseMotion and not OS.has_feature("mobile") and e.device != InputEvent.DEVICE_ID_EMULATION and e.button_mask == 0:
		menu.hovered(i)

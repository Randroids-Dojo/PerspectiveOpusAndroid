class_name UiBlocks
extends RefCounted
## Small custom-drawn pieces of the screens: card headers, the title's mark, the
## completion card's notes and stats, the controls table and the credits roll.


## Sizes taken from ui.css at a screen size, including its max-height: 480px rules.
static func metrics(w: float, h: float) -> Dictionary:
	var compact := h <= 480.0
	var vh := h / 100.0
	var vw := w / 100.0
	return {
		"compact": compact,
		"vh": vh,
		"vw": vw,
		"fs": clampf(2.3 * vh, 17.0, 21.0),
		"item_pad": Vector4(6, 12, 6, 28) if compact else Vector4(9, 14, 9, 30),
		"card_pad": Vector2(22, 14) if compact else Vector2(clampf(4.0 * vw, 22.0, 48.0), clampf(4.0 * vh, 22.0, 40.0)),
		"h2": 30.0 if compact else clampf(5.4 * vh, 34.0, 52.0),
		"head_mb": 8.0 if compact else 18.0,
		"min_w": minf(440.0, 0.88 * w),
		"max_w": minf(640.0, 0.92 * w),
		"max_h": (94.0 if compact else 88.0) * vh,
	}


## A card's header: kicker, title and subtitle (only the title on short screens).
class Head:
	extends Control
	var kicker := ""
	var title := ""
	var sub := ""
	var h2 := 30.0
	var compact := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func block_width() -> float:
		return UiStyle.width(UiStyle.display_i, roundi(h2), title)

	func _kicker_font() -> Font:
		return UiStyle.spaced(UiStyle.body, 12, 0.32)

	func block_layout(w: float) -> float:
		var y := 0.0
		if not compact and kicker != "":
			var kf := _kicker_font()
			y += kf.get_ascent(12) + kf.get_descent(12)
		y += 8.0 + h2
		if not compact and sub != "":
			y += 6.0 + UiStyle.body_i.get_ascent(14) + UiStyle.body_i.get_descent(14)
		size = Vector2(w, y)
		return y

	func _draw() -> void:
		var y := 0.0
		var w := size.x
		if not compact and kicker != "":
			var kf := _kicker_font()
			draw_string(kf, Vector2(0, y + kf.get_ascent(12)), kicker.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 12, UiStyle.c("fg_dim"))
			y += kf.get_ascent(12) + kf.get_descent(12)
		y += 8.0
		var s := roundi(h2)
		draw_string(UiStyle.display_i, Vector2(0, y + UiStyle.baseline(UiStyle.display_i, s, h2)), title, HORIZONTAL_ALIGNMENT_CENTER, w, s, UiStyle.c("fg"))
		y += h2
		if not compact and sub != "":
			y += 6.0
			draw_string(UiStyle.body_i, Vector2(0, y + UiStyle.body_i.get_ascent(14)), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 14, UiStyle.c("fg_dim"))


## The title's lettering: kicker, "Perspective", gilt "Opus" and the rule.
class TitleMark:
	extends Control
	var w1 := 40.0
	var w2 := 70.0
	var rule_w := 340.0
	var gold := Control.new()
	var _mat := ShaderMaterial.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat.shader = UiStyle.gold_shader
		gold.material = _mat
		gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gold.draw.connect(_draw_gold)
		add_child(gold)

	func _kf() -> Font:
		return UiStyle.spaced(UiStyle.body, 12, 0.32)

	## Top of the h1 (below the kicker and its 10 px margin).
	func _h1_top() -> float:
		return _kf().get_ascent(12) + _kf().get_descent(12) + 10.0

	func _w2_top() -> float:
		return _h1_top() + w1 * 0.82

	func block_height() -> float:
		return _w2_top() + w2 * 0.82 + 18.0 + 1.0

	func layout(at: Vector2) -> void:
		position = at
		size = Vector2(maxf(rule_w + 10.0, UiStyle.width(_kf(), 12, "A SYMPHONY IN TWO WORLDS")), block_height())
		gold.position = Vector2.ZERO
		gold.size = size

	func _process(_dt: float) -> void:
		_mat.set_shader_parameter("top", _w2_top())
		_mat.set_shader_parameter("height", w2 * 0.82)
		_mat.set_shader_parameter("flat_color", UiStyle.c("accent"))
		_mat.set_shader_parameter("k", UiStyle.k)
		queue_redraw()
		gold.queue_redraw()

	func _w2_pos() -> Vector2:
		var s := roundi(w2)
		return Vector2(0.32 * w2, _w2_top() + UiStyle.baseline(UiStyle.display_i, s, w2 * 0.82))

	func _draw() -> void:
		var kf := _kf()
		draw_string(kf, Vector2(0, kf.get_ascent(12)), "A SYMPHONY IN TWO WORLDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.c("fg_dim"))
		var s1 := roundi(w1)
		var b1 := _h1_top() + UiStyle.baseline(UiStyle.display_i, s1, w1 * 0.82)
		UiStyle.text(self, UiStyle.display_i, s1, Vector2(0, b1), "Perspective", UiStyle.c("fg"), true)
		# The gilt word's drop shadows (Stage only): a close brown edge and a soft fall.
		var k := UiStyle.k
		if k > 0.01:
			var s2 := roundi(w2)
			var p := _w2_pos()
			for pass_i in 3:
				var o: int = [16, 10, 5][pass_i]
				draw_string_outline(UiStyle.display_i, p + Vector2(0, 8), "Opus", HORIZONTAL_ALIGNMENT_LEFT, -1, s2, o, Color(0, 0, 0, 0.35 * k * [0.12, 0.16, 0.22][pass_i]))
			draw_string_outline(UiStyle.display_i, p + Vector2(0, 2), "Opus", HORIZONTAL_ALIGNMENT_LEFT, -1, s2, 2, Color(60 / 255.0, 30 / 255.0, 0, 0.3 * k))
			draw_string(UiStyle.display_i, p + Vector2(0, 2), "Opus", HORIZONTAL_ALIGNMENT_LEFT, -1, s2, Color(60 / 255.0, 30 / 255.0, 0, 0.55 * k))
		var ry := _w2_top() + w2 * 0.82 + 18.0
		var acc := UiStyle.c("accent")
		UiStyle.linear_x(self, Rect2(9.6, ry, rule_w, 1.0), [[0.0, acc], [1.0, UiStyle.fade(acc, 0.0)]])

	func _draw_gold() -> void:
		gold.draw_string(UiStyle.display_i, _w2_pos(), "Opus", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(w2), Color.WHITE)


## The completion card's seven notes; found ones drop in one after another.
class NotesRow:
	extends Control
	var notes: Array = []
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func block_width() -> float:
		return 27.0 * 7.0 + 6.0 * 6.0

	func block_layout(w: float) -> float:
		size = Vector2(w, 36.0)
		return 36.0

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var x0 := (size.x - block_width()) / 2.0
		var empty := UiStyle.fade(UiStyle.c("fg"), 0.2)
		for i in notes.size():
			var r := Rect2(x0 + i * 33.0, 0, 27, 36)
			if not notes[i]:
				UiStyle.draw_glyph(self, r, empty)
				continue
			# note-in: from translateY(-14px) scale(1.4) and transparent, 0.6 s after 0.5 + 0.12 i.
			var p := UiStyle.ease(clampf((t - 0.5 - i * 0.12) / 0.6, 0.0, 1.0))
			var s := lerpf(1.4, 1.0, p)
			var rr := Rect2(r.get_center() - r.size * s / 2.0 + Vector2(0, -14.0 * (1.0 - p)), r.size * s)
			var col := UiStyle.c("accent")
			col.a *= p
			UiStyle.draw_glyph(self, rr, col)


## Time, turns of the world and restarts in three columns.
class Stats:
	extends Control
	var cells: Array = []  # [[label, value], ...]
	var compact := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _lf() -> Font:
		return UiStyle.spaced(UiStyle.body, 11, 0.2)

	func _dd() -> int:
		return 20 if compact else 26

	func block_width() -> float:
		var m := 0.0
		for c in cells:
			m = maxf(m, maxf(UiStyle.width(_lf(), 11, String(c[0]).to_upper()), UiStyle.width(UiStyle.display, _dd(), c[1])))
		return m * 3.0 + 16.0

	func block_layout(w: float) -> float:
		var lf := _lf()
		var hh := lf.get_ascent(11) + lf.get_descent(11) + 4.0 + UiStyle.display.get_ascent(_dd()) + UiStyle.display.get_descent(_dd())
		size = Vector2(w, hh)
		return hh

	func _draw() -> void:
		var lf := _lf()
		var cw := (size.x - 16.0) / 3.0
		for i in cells.size():
			var x := i * (cw + 8.0)
			draw_string(lf, Vector2(x, lf.get_ascent(11)), String(cells[i][0]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, cw, 11, UiStyle.c("fg_dim"))
			var y := lf.get_ascent(11) + lf.get_descent(11) + 4.0 + UiStyle.display.get_ascent(_dd())
			draw_string(UiStyle.display, Vector2(x, y), cells[i][1], HORIZONTAL_ALIGNMENT_CENTER, cw, _dd(), UiStyle.c("fg"))


## The controls table: action, keyboard, controller, touch.
class Table:
	extends Control
	const HEAD := ["", "Keyboard", "Controller", "Touch"]
	const ROWS := [
		["Move", "A D or arrows", "Left stick or d-pad", "Drag on the left"],
		["Walk in depth (Stage)", "W S or arrows", "Stick up and down", "Drag up and down"],
		["Jump", "Space, Z or K", "A", "Round button"],
		["Turn the world", "Shift, E or X", "Y, X or a shoulder", "Page button"],
		["Pause", "Esc or P", "Start", "Top right"],
	]
	var compact := true
	var _cols: Array[float] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _hf() -> Font:
		return UiStyle.spaced(UiStyle.body, 11, 0.24)

	func _pad() -> Vector2:
		return Vector2(8, 4) if compact else Vector2(10, 8)

	func _measure_cols() -> void:
		_cols = []
		for c in 4:
			var m := UiStyle.width(_hf(), 11, String(HEAD[c]).to_upper())
			for r in ROWS:
				m = maxf(m, UiStyle.width(UiStyle.display, 18, r[c]) if c == 0 else UiStyle.width(UiStyle.body, 14, r[c]))
			_cols.append(m + _pad().x * 2.0)

	func block_width() -> float:
		_measure_cols()
		var s := 0.0
		for c in _cols:
			s += c
		return s

	func _row_h(head: bool) -> float:
		if head:
			return _hf().get_ascent(11) + _hf().get_descent(11) + _pad().y * 2.0 + 1.0
		return maxf(UiStyle.display.get_ascent(18) + UiStyle.display.get_descent(18), UiStyle.body.get_ascent(14) + UiStyle.body.get_descent(14)) + _pad().y * 2.0 + 1.0

	func block_layout(w: float) -> float:
		_measure_cols()
		var hh := _row_h(true) + _row_h(false) * ROWS.size()
		size = Vector2(w, hh)
		return hh

	func _draw() -> void:
		var total := 0.0
		for c in _cols:
			total += c
		var extra := (size.x - total) / 4.0
		var p := _pad()
		var edge := UiStyle.fade(UiStyle.c("card_edge"), 0.4)
		var y := 0.0
		var hh := _row_h(true)
		var x := 0.0
		for c in 4:
			draw_string(_hf(), Vector2(x + p.x, y + p.y + _hf().get_ascent(11)), String(HEAD[c]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.c("fg_dim"))
			x += _cols[c] + extra
		y += hh
		draw_rect(Rect2(0, y - 1.0, size.x, 1.0), edge)
		var rh := _row_h(false)
		for r in ROWS:
			x = 0.0
			var base := y + p.y + maxf(UiStyle.display.get_ascent(18), UiStyle.body.get_ascent(14))
			for c in 4:
				if c == 0:
					draw_string(UiStyle.display, Vector2(x + p.x, base), r[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.c("fg"))
				else:
					draw_string(UiStyle.body, Vector2(x + p.x, base), r[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.c("fg"))
				x += _cols[c] + extra
			y += rh
			draw_rect(Rect2(0, y - 1.0, size.x, 1.0), edge)


## The credits: who made it, then how many notes are home.
class Roll:
	extends Control
	var total := 0
	## [kind, text]: "kicker", "p", "h3", "notes".
	var lines: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_total(n: int) -> void:
		total = n
		lines = [
			["kicker", "Perspective Opus"],
			["p", "A game by toyboxes.games"],
			["h3", "Performed by"], ["p", "Quaver, the last little note"],
			["h3", "The Score"], ["p", "Ink, gold leaf and parchment, drawn live in canvas"],
			["h3", "The Stage"], ["p", "Lit and built in Godot"],
			["h3", "The Opus"], ["p", "Composed and synthesised in code, every note of it"],
			["h3", "Type"], ["p", "Cormorant Garamond and Fraunces"],
			["notes", "%d of 42 notes restored" % n],
		]

	func _style(kind: String) -> Array:
		match kind:
			"kicker":
				return [UiStyle.display_i, 40, "accent", 0.0, 0.0]
			"h3":
				return [UiStyle.spaced(UiStyle.body, 11, 0.3), 11, "fg_dim", 18.0, 4.0]
			"notes":
				return [UiStyle.display_i, 16, "fg_dim", 22.0, 0.0]
		return [UiStyle.display, 21, "fg", 0.0, 0.0]

	func block_width() -> float:
		var m := 0.0
		for l in lines:
			var st := _style(l[0])
			m = maxf(m, UiStyle.width(st[0], st[1], l[1].to_upper() if l[0] == "h3" else l[1]))
		return m

	func block_layout(w: float) -> float:
		var y := 0.0
		var prev_mb := 0.0
		for l in lines:
			var st := _style(l[0])
			var f: Font = st[0]
			y += maxf(prev_mb, st[3]) if y > 0.0 else 0.0
			y += f.get_ascent(st[1]) + f.get_descent(st[1])
			prev_mb = st[4]
		size = Vector2(w, y)
		return y

	func _draw() -> void:
		var y := 0.0
		var prev_mb := 0.0
		for l in lines:
			var st := _style(l[0])
			var f: Font = st[0]
			y += maxf(prev_mb, st[3]) if y > 0.0 else 0.0
			var t: String = l[1].to_upper() if l[0] == "h3" else l[1]
			draw_string(f, Vector2(0, y + f.get_ascent(st[1])), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, st[1], UiStyle.c(st[2]))
			y += f.get_ascent(st[1]) + f.get_descent(st[1])
			prev_mb = st[4]

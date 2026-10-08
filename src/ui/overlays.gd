class_name UiOverlays
extends RefCounted
## The full-screen pieces the director layers over everything: each movement's
## title card, the fade between scenes and the ending's lines.


## The web build's .intro-card: movement, title, tempo and epigraph, shown for 2.8 s.
class IntroCard:
	extends Control
	var info: Dictionary = {}
	var t := 99.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func show_card(level_info: Dictionary) -> void:
		info = level_info
		t = 0.0

	func hide_card() -> void:
		t = 99.0

	func showing() -> bool:
		return t < 2.8

	func _process(dt: float) -> void:
		var was := t < 2.8
		t += dt
		if was or t < 2.8:
			queue_redraw()

	## card-show: in over the first 14 %, held to 70 %, out by 100 %.
	func _anim() -> Vector2:
		var p := t / 2.8
		if p >= 1.0:
			return Vector2(0, -6)
		if p < 0.14:
			var q := UiStyle.ease(p / 0.14)
			return Vector2(q, 10.0 * (1.0 - q))
		if p < 0.7:
			return Vector2(1, 0)
		var q2 := UiStyle.ease((p - 0.7) / 0.3)
		return Vector2(1.0 - q2, -6.0 * q2)

	func _draw() -> void:
		if t >= 2.8 or info.is_empty():
			return
		var an := _anim()
		if UiStyle.reduce_motion:
			an.y = 0.0
		var a := an.x
		var y := 0.22 * size.y + an.y
		var w := size.x
		var kf := UiStyle.spaced(UiStyle.body, 12, 0.32)
		var dimc := UiStyle.fade(UiStyle.c("fg_dim"), a)
		y += kf.get_ascent(12)
		UiStyle.text(self, kf, 12, Vector2(0, y), String(info.movement).to_upper(), dimc, true, w, HORIZONTAL_ALIGNMENT_CENTER)
		y += kf.get_descent(12) + 8.0
		var ts := roundi(clampf(0.11 * size.y, 52.0, 120.0))
		UiStyle.text(self, UiStyle.display_i, ts, Vector2(0, y + UiStyle.baseline(UiStyle.display_i, ts, ts)), info.title, UiStyle.fade(UiStyle.c("fg"), a), true, w, HORIZONTAL_ALIGNMENT_CENTER)
		y += ts + 4.0
		y += UiStyle.display_i.get_ascent(22)
		UiStyle.text(self, UiStyle.display_i, 22, Vector2(0, y), info.tempo, UiStyle.fade(UiStyle.c("accent"), a), true, w, HORIZONTAL_ALIGNMENT_CENTER)
		y += UiStyle.display_i.get_descent(22) + 14.0 + UiStyle.body_i.get_ascent(16)
		if size.y > 480.0:
			UiStyle.text(self, UiStyle.body_i, 16, Vector2(0, y), info.epigraph, dimc, true, w, HORIZONTAL_ALIGNMENT_CENTER)


## The curtain between scenes, in the world's fade colour (CSS transition: ease).
class Fade:
	extends Control
	var value := 0.0
	var _from := 0.0
	var _to := 0.0
	var _t := 1.0
	var _dur := 0.45

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func go(to: float, seconds: float) -> void:
		_from = value
		_to = to
		_t = 0.0
		_dur = maxf(0.01, seconds)

	func snap(v: float) -> void:
		value = v
		_from = v
		_to = v
		_t = 1.0

	func _process(dt: float) -> void:
		if _t < 1.0:
			_t = minf(1.0, _t + dt / _dur)
			value = lerpf(_from, _to, UiStyle.bezier(UiStyle.EASE_CSS, _t))
		# While on, it swallows taps, like the web build's .fade.on.
		mouse_filter = Control.MOUSE_FILTER_STOP if _to > 0.5 else Control.MOUSE_FILTER_IGNORE
		visible = value > 0.001
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiStyle.fade(UiStyle.c("fade"), value))


## The last bow's four lines, one after another over the hall (2 s, then every 6 s).
class EndingLines:
	extends Control
	var lines: Array = []
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	## ending-line: in by 20 %, held to 78 %, out by 100 %. [opacity, y offset]
	func _anim(i: int) -> Vector2:
		var dur := 7.0 if i == lines.size() - 1 else 6.0
		var p := (t - (2.0 + i * 6.0)) / dur
		if p <= 0.0 or p >= 1.0:
			return Vector2(0, 0)
		if p < 0.2:
			var q := UiStyle.ease(p / 0.2)
			return Vector2(q, 0.0 if UiStyle.reduce_motion else 12.0 * (1.0 - q))
		if p < 0.78:
			return Vector2(1, 0)
		var q2 := UiStyle.ease((p - 0.78) / 0.22)
		return Vector2(1.0 - q2, 0.0 if UiStyle.reduce_motion else -8.0 * q2)

	func _draw() -> void:
		var fs := roundi(clampf(0.046 * size.y, 26.0, 44.0))
		var f := UiStyle.display_i
		for i in lines.size():
			var an := _anim(i)
			if an.x <= 0.0:
				continue
			var y := 0.4 * size.y + an.y + f.get_ascent(fs)
			UiStyle.text(self, f, fs, Vector2(0, y), lines[i], UiStyle.fade(UiStyle.c("fg"), an.x), true, size.x, HORIZONTAL_ALIGNMENT_CENTER)

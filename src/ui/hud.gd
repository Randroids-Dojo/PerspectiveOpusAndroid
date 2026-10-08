class_name Hud
extends Control
## The in-game overlay, a port of the web build's src/ui/hud.ts: the movement's title,
## seven note slots (found notes fly to theirs), the world badge (tap to turn the
## world), the pause button, the signposts' hints and the optional timer.

signal switch_pressed
signal pause_pressed

var show_timer := false
## Safe-area insets: left, top, right, bottom.
var safe := Vector4.ZERO

var _title := ""
var _slots: Array[bool] = []
var _arrive: Array[float] = []
var _mode := "3d"
var _device := "keyboard"
var _play_time := 0.0
var _shown := false
var _alpha := 0.0
## Badge icons: page and stage visibility, 0..1, eased towards the current mode.
var _page_t := 0.0
var _stage_t := 1.0
var _pulse := 9.0
var _hint := ""
var _hint_id := ""
var _hint_device := ""
var _hint_on := false
var _hint_t := 0.0
## Flying notes: {from: Vector2, slot: int, t: float}
var _fly: Array = []
var _badge := Rect2()
var _pause := Rect2()
var _left := Rect2()
var _touch_down := {}
var _key_box := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_key_box.draw_center = false
	_key_box.set_border_width_all(1)
	_key_box.set_corner_radius_all(4)
	_key_box.anti_aliasing = true


func set_level(game: Sim) -> void:
	var info := game.level.info
	var idx := int(info.index)
	_title = ("%s  %s" % [UiStyle.ROMAN[idx], info.title]) if idx >= 0 else String(info.title)
	_slots = []
	_arrive = []
	for i in game.level.notes.size():
		_slots.append(game.notes_taken[i])
		_arrive.append(9.0)
	_fly.clear()
	_hint_id = ""
	_hint_on = false
	_hint_t = 0.0
	_mode = game.mode
	_page_t = 1.0 if _mode == "2d" else 0.0
	_stage_t = 1.0 - _page_t


func show_hud(v: bool) -> void:
	_shown = v
	_touch_down.clear()


func is_shown() -> bool:
	return _shown


## Hints wait until this time (msec) so they never sit on top of the movement's title card.
var quiet_until := 0


func update(game: Sim, device: String) -> void:
	_mode = game.mode
	_device = device
	_play_time = game.play_time
	var id := ""
	var quiet := Time.get_ticks_msec() < quiet_until
	if game.active_sign != null and not quiet and not game.finished and game.player.dead <= 0.0:
		id = String(game.active_sign.hint)
	if id != _hint_id or device != _hint_device:
		_hint_id = id
		_hint_device = device
		if id != "":
			_hint = Hints.text(id, device)
			_hint_on = true
		else:
			_hint_on = false


func on_events(events: Array, game: Sim, view: View) -> void:
	for e in events:
		if e.t == "note":
			_fly_note(int(e.id), game, view)
		elif e.t == "switch":
			_pulse = 0.0


func _fly_note(id: int, game: Sim, view: View) -> void:
	if id >= _slots.size():
		return
	var p := game.player.pos
	var from := view.world_to_screen(p.x, p.y + Sim.PH * 0.6, p.z)
	_fly.append({"from": from, "slot": id, "t": 0.0})


# ---------------------------------------------------------------- layout

func _layout() -> void:
	var sl := safe.x
	var st := safe.y
	var sr := safe.z
	var tw := UiStyle.width(_title_font(), 19, _title)
	var w := 14.0 + maxf(tw, 7.0 * 19.8 + 18.0) + 34.0
	_left = Rect2(sl + 8.0, st + 8.0, w, 10.0 + _title_lh() + 4.0 + 29.2 + 14.0)
	var bw := 9.0 + 22.0 + 10.0 + UiStyle.width(UiStyle.display_i, 18, _badge_label()) + 14.0 + 2.0
	var key := _badge_key()
	if key != "":
		bw += 10.0 + UiStyle.width(_key_font(), 11, key) + 12.0 + 2.0
	_pause = Rect2(size.x - sr - 18.0 - 40.0, st + 16.0, 40.0, 40.0)
	_badge = Rect2(_pause.position.x - 10.0 - bw, st + 17.0, bw, 38.0)


func _title_font() -> Font:
	return UiStyle.spaced(UiStyle.display_i, 19, 0.04)


func _title_lh() -> float:
	return UiStyle.display_i.get_ascent(19) + UiStyle.display_i.get_descent(19)


func _key_font() -> Font:
	return UiStyle.spaced(UiStyle.body, 11, 0.12)


func _badge_label() -> String:
	return "Stage" if _mode == "3d" else "Score"


func _badge_key() -> String:
	return "Shift" if _device == "keyboard" else ("Y" if _device == "gamepad" else "")


func slot_rect(i: int) -> Rect2:
	var x := _left.position.x + 14.0 + i * (19.8 + 3.0)
	var y := _left.position.y + 10.0 + _title_lh() + 4.0 + 2.8
	return Rect2(x, y, 19.8, 26.4)


func badge_rect() -> Rect2:
	return _badge


func pause_rect() -> Rect2:
	return _pause


# ---------------------------------------------------------------- animation

func _process(dt: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if _shown else 0.0, dt / 0.4)
	var page_target := 1.0 if _mode == "2d" else 0.0
	_page_t = move_toward(_page_t, page_target, dt / 0.45)
	_stage_t = move_toward(_stage_t, 1.0 - page_target, dt / 0.45)
	_pulse += dt
	_hint_t = move_toward(_hint_t, 1.0 if _hint_on else 0.0, dt / 0.45)
	for i in _arrive.size():
		_arrive[i] += dt
	var keep: Array = []
	for f in _fly:
		f.t += dt
		if f.t >= 0.9:
			_slots[f.slot] = true
			_arrive[f.slot] = 0.0
		else:
			keep.append(f)
	_fly = keep
	visible = _alpha > 0.0
	if visible:
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_layout()
	var a := UiStyle.ease(_alpha)
	var fg := UiStyle.c("fg")
	fg.a *= a
	# The left plate: a soft wash behind the title and notes.
	UiStyle.radial_box(self, _left, Vector2(0.4, 0.5), [
		[0.0, UiStyle.fade(UiStyle.c("plate_in"), a)],
		[0.45, UiStyle.fade(UiStyle.c("plate_mid"), a)],
		[0.72, UiStyle.fade(UiStyle.c("plate_mid"), 0.0)],
		[1.0, UiStyle.fade(UiStyle.c("plate_mid"), 0.0)],
	])
	var tf := _title_font()
	UiStyle.text(self, tf, 19, _left.position + Vector2(14, 10 + UiStyle.display_i.get_ascent(19)), _title, fg, true)
	var empty := UiStyle.c("slot_empty")
	empty.a *= a
	var gold := UiStyle.c("accent")
	gold.a *= a
	for i in _slots.size():
		var r := slot_rect(i)
		var col := gold if _slots[i] else empty
		var t := _arrive[i]
		if t < 0.7:
			# slot-arrive: from scale 1.8 turned -12 degrees, through 0.9, back to rest.
			var s := 1.0
			var rot := 0.0
			var p := t / 0.7
			if p < 0.6:
				var q := UiStyle.ease(p / 0.6)
				s = lerpf(1.8, 0.9, q)
				rot = lerpf(-12.0, 0.0, q)
			else:
				s = lerpf(0.9, 1.0, UiStyle.ease((p - 0.6) / 0.4))
			draw_set_transform(r.get_center(), deg_to_rad(rot), Vector2.ONE * s)
			UiStyle.draw_glyph_shadowed(self, Rect2(-r.size / 2.0, r.size), col)
			draw_set_transform(Vector2.ZERO)
		else:
			UiStyle.draw_glyph_shadowed(self, r, col)
	_draw_badge(a)
	_draw_pause(a)
	if show_timer:
		var tm := UiStyle.fmt_time(_play_time)
		var f := UiStyle.spaced(UiStyle.body, 16, 0.05)
		var dimc := UiStyle.c("fg_dim")
		dimc.a *= a
		var y := safe.y + 20.0 + f.get_ascent(16)
		UiStyle.text(self, f, 16, Vector2(0, y), tm, dimc, true, size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_hint(a)
	for fl in _fly:
		_draw_fly(fl, a)


func _draw_badge(a: float) -> void:
	var r := _badge
	var pulse := 1.0
	if _pulse < 0.7:
		var p := _pulse / 0.7
		pulse = 1.0 + 0.12 * (UiStyle.ease(p / 0.3) if p < 0.3 else 1.0 - UiStyle.ease((p - 0.3) / 0.7))
	draw_set_transform(r.get_center(), 0.0, Vector2.ONE * pulse)
	var lr := Rect2(-r.size / 2.0, r.size)
	UiStyle.pill(self, lr, UiStyle.fade(UiStyle.c("card"), 0.7 * a), UiStyle.fade(UiStyle.c("card_edge"), a))
	var fg := UiStyle.c("fg")
	fg.a *= a
	var ic := Rect2(lr.position + Vector2(10, 8), Vector2(22, 22))
	_draw_world_icon(ic, fg, 1.0)
	var lx := ic.end.x + 10.0
	var base := lr.get_center().y + UiStyle.baseline(UiStyle.display_i, 18, 18.0) - 9.0
	draw_string(UiStyle.display_i, Vector2(lx, base), _badge_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, fg)
	var key := _badge_key()
	if key != "":
		var kf := _key_font()
		var kx := lx + UiStyle.width(UiStyle.display_i, 18, _badge_label()) + 10.0
		var kw := UiStyle.width(kf, 11, key) + 12.0
		var kh := kf.get_ascent(11) + kf.get_descent(11) + 4.0
		var kr := Rect2(kx, lr.get_center().y - kh / 2.0, kw + 2.0, kh + 2.0)
		_key_box.border_color = UiStyle.fade(UiStyle.c("fg"), 0.3 * a)
		draw_style_box(_key_box, kr)
		var dimc := UiStyle.c("fg_dim")
		dimc.a *= a
		draw_string(kf, Vector2(kr.position.x + 7.0, kr.position.y + 3.0 + kf.get_ascent(11)), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dimc)
	draw_set_transform(Vector2.ZERO)


## The page (Score) and cube (Stage) icons, crossfading as the world turns.
func _draw_world_icon(box: Rect2, col: Color, s: float) -> void:
	var c := box.get_center()
	if _page_t > 0.0:
		# rotateY(80deg) as it hides.
		var sx := cos(deg_to_rad(80.0) * UiStyle.ease(1.0 - _page_t))
		var sz := box.size * s
		var pc := Color(col.r, col.g, col.b, col.a * _page_t)
		draw_texture_rect(UiStyle.page_icon, Rect2(c - Vector2(sz.x * sx, sz.y) / 2.0, Vector2(sz.x * sx, sz.y)), false, pc)
	if _stage_t > 0.0:
		var sc := lerpf(0.3, 1.0, UiStyle.ease(_stage_t))
		var sz := box.size * s * sc
		var scol := Color(col.r, col.g, col.b, col.a * _stage_t)
		draw_texture_rect(UiStyle.stage_icon, Rect2(c - sz / 2.0, sz), false, scol)


func _draw_pause(a: float) -> void:
	var r := _pause
	var dev_a := 0.6 if _device != "touch" else 1.0
	UiStyle.pill(self, r, UiStyle.fade(UiStyle.c("card"), 0.7 * a * dev_a), UiStyle.fade(UiStyle.c("card_edge"), a * dev_a))
	var fg := UiStyle.c("fg")
	fg.a *= a * dev_a
	var c := r.get_center()
	draw_rect(Rect2(c + Vector2(-5.5, -7), Vector2(3, 14)), fg)
	draw_rect(Rect2(c + Vector2(2.5, -7), Vector2(3, 14)), fg)


func _draw_hint(a: float) -> void:
	if _hint_t <= 0.0 or _hint == "":
		return
	var f := UiStyle.display_i
	var fs := int(clampf(2.8 * size.y / 100.0, 19.0, 25.0))
	var lh := fs * 1.25
	var max_w := minf(640.0, 0.86 * size.x) - 52.0
	var lines := _wrap(f, fs, _hint, max_w)
	var tw := 0.0
	for l in lines:
		tw = maxf(tw, UiStyle.width(f, fs, l))
	var box := Vector2(tw + 52.0, lines.size() * lh + 20.0)
	var p := UiStyle.ease(_hint_t)
	var y := 0.0
	if _device == "touch":
		y = safe.y + 74.0 - 8.0 * (1.0 - p)
	else:
		y = size.y - safe.w - 0.09 * size.y - box.y + 10.0 * (1.0 - p)
	var rect := Rect2((size.x - box.x) / 2.0, y, box.x, box.y)
	var ha := a * p
	var card := UiStyle.c("card")
	UiStyle.radial_box(self, rect, Vector2(0.5, 0.5), [
		[0.0, UiStyle.fade(card, 0.72 * ha)], [0.3, UiStyle.fade(card, 0.72 * ha)], [0.72, UiStyle.fade(card, 0.0)], [1.0, UiStyle.fade(card, 0.0)],
	])
	var fg := UiStyle.c("fg")
	fg.a *= ha
	for i in lines.size():
		var base := rect.position.y + 10.0 + i * lh + UiStyle.baseline(f, fs, lh)
		UiStyle.text(self, f, fs, Vector2(rect.position.x, base), lines[i], fg, true, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func hint_text() -> String:
	return _hint if _hint_on else ""


func _wrap(f: Font, fs: int, s: String, w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if line != "" and UiStyle.width(f, fs, t) > w:
			out.append(line)
			line = word
		else:
			line = t
	out.append(line)
	return out


## A found note: rises from Quaver, swells, then flies to its slot (0.9 s).
func _draw_fly(fl: Dictionary, a: float) -> void:
	var t: float = fl.t / 0.9
	var e := UiStyle.bezier(Vector4(0.5, 0.0, 0.3, 1.0), t)
	var from: Vector2 = fl.from
	var to := slot_rect(fl.slot).get_center()
	var pos: Vector2
	var s: float
	var op: float
	if e < 0.25:
		var q := e / 0.25
		pos = from + Vector2(0, -40.0 * q)
		s = lerpf(0.6, 1.5, q)
		op = q
	else:
		var q := (e - 0.25) / 0.75
		pos = (from + Vector2(0, -40)).lerp(to, q)
		s = lerpf(1.5, 0.9, q)
		op = 1.0
	var sz := Vector2(27, 36) * s
	var gold := UiStyle.c("accent")
	gold.a *= a * op
	UiStyle.draw_glyph(self, Rect2(pos - sz / 2.0 - Vector2(4, 4), sz + Vector2(8, 8)), Color(1.0, 0.82, 0.47, 0.35 * a * op))
	UiStyle.draw_glyph(self, Rect2(pos - sz / 2.0, sz), gold)


# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if not _shown or _alpha < 0.5:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var hit := _hit(e.position)
			if hit != "":
				_touch_down[e.index] = hit
				get_viewport().set_input_as_handled()
		elif _touch_down.has(e.index):
			var was: String = _touch_down[e.index]
			_touch_down.erase(e.index)
			if _hit(e.position) == was:
				_fire(was)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		var h := _hit(e.position)
		if h != "":
			_fire(h)
			get_viewport().set_input_as_handled()


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _hit(window_pos: Vector2) -> String:
	var p := _to_local(window_pos)
	if _badge.grow(4.0).has_point(p):
		return "badge"
	if _pause.grow(6.0).has_point(p):
		return "pause"
	return ""


func _fire(what: String) -> void:
	if what == "badge":
		switch_pressed.emit()
	else:
		pause_pressed.emit()

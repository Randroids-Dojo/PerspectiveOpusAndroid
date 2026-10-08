class_name UiScreens
extends RefCounted
## The menus, a port of the web build's src/ui/screens.ts: title, programme,
## settings, controls, pause, completion and credits. Each returns a UiScreen whose
## layout follows ui.css at the current screen size.

const QUALITY := ["auto", "low", "medium", "high"]


# ---------------------------------------------------------------- shared card layout

## blocks: [[node, margin_top, margin_bottom], ...] stacked in the card's content box.
static func _layout_card(s: UiScreen, blocks: Array, w: float, h: float, want_w := -1.0) -> void:
	var m := UiBlocks.metrics(w, h)
	var card := s.card
	card.pad = m.card_pad
	card.px_scale = s.get_viewport().get_final_transform().get_scale().x if s.is_inside_tree() else 2.0
	var nat := 0.0
	for b in blocks:
		nat = maxf(nat, _natural(b[0]))
	var cw := clampf(want_w if want_w > 0.0 else nat, m.min_w, m.max_w)
	var y := 0.0
	for b in blocks:
		y += float(b[1])
		var node: Control = b[0]
		var bh := _block_layout(node, cw)
		node.position = Vector2(0, y)
		y += bh + float(b[2])
	var content_h := y
	var total_h := minf(content_h, m.max_h) + card.pad.y * 2.0 + 2.0
	total_h = minf(total_h, h - 6.0)
	var card_w := cw + card.pad.x * 2.0 + 2.0
	card.place(Rect2((w - card_w) / 2.0, (h - total_h) / 2.0, card_w, total_h), content_h)


static func _natural(n: Control) -> float:
	if n is UiMenu:
		return (n as UiMenu).natural_width()
	if n is UiLabel:
		return (n as UiLabel).text_width()
	if n.has_method("block_width"):
		return n.block_width()
	return 0.0


static func _block_layout(n: Control, w: float) -> float:
	if n is UiMenu:
		return (n as UiMenu).layout(w)
	if n is UiLabel:
		return (n as UiLabel).fit(w)
	return n.block_layout(w)


static func _menu_metrics(menu: UiMenu, m: Dictionary) -> void:
	menu.set_metrics(m.fs, m.item_pad)
	UiStyle.compact = m.compact


static func _card_screen(head: UiBlocks.Head, menu: UiMenu, extra_before: Array, want_w_fn: Callable) -> UiScreen:
	var s := UiScreen.new()
	s.kind = "scrim"
	s.card = UiCard.new()
	s.add_child(s.card)
	s.menu = menu
	menu.scroller = s.card
	s.card.content.add_child(head)
	for b in extra_before:
		s.card.content.add_child(b[0])
	s.card.content.add_child(menu)
	s.layout_fn = func(sc: UiScreen, w: float, h: float) -> void:
		var m := UiBlocks.metrics(w, h)
		_menu_metrics(menu, m)
		head.h2 = m.h2
		head.compact = m.compact
		var blocks: Array = [[head, 0.0, m.head_mb]]
		for b in extra_before:
			blocks.append(b)
		blocks.append([menu, 0.0, 0.0])
		_layout_card(sc, blocks, w, h, want_w_fn.call(w) if want_w_fn.is_valid() else -1.0)
	return s


static func _head(title: String, kicker := "", sub := "") -> UiBlocks.Head:
	var hd := UiBlocks.Head.new()
	hd.title = title
	hd.kicker = kicker
	hd.sub = sub
	return hd


# ---------------------------------------------------------------- title

## ctx: {save: OpusSave, ids, infos, hooks, on_begin, on_continue(i), on_programme, on_settings, on_credits}
static func title(ctx: Dictionary) -> UiScreen:
	var sv: OpusSave = ctx.save
	var ids: Array = ctx.ids
	var infos: Array = ctx.infos
	var started := sv.started()
	var next := sv.next_movement(ids)
	var items: Array = []
	if started and next < ids.size():
		items.append({"id": "continue", "label": "Continue",
			"detail": func() -> String: return "Movement %s, %s" % [UiStyle.ROMAN[next], infos[next].title],
			"select": func() -> void: ctx.on_continue.call(next)})
	items.append({"id": "begin", "label": "Begin again" if started else "Begin", "select": ctx.on_begin})
	items.append({"id": "programme", "label": "Programme", "select": ctx.on_programme})
	items.append({"id": "settings", "label": "Settings", "select": ctx.on_settings})
	items.append({"id": "credits", "label": "Credits", "select": ctx.on_credits})
	var menu := UiMenu.new(items, ctx.hooks)
	var mark := UiBlocks.TitleMark.new()
	var foot := UiLabel.make("Shift turns the world", UiStyle.body_i, 13, "fg_dim")
	foot.em = 0.08
	var s := UiScreen.new()
	s.kind = "title"
	s.menu = menu
	s.add_child(mark)
	s.add_child(menu)
	s.add_child(foot)
	s.nav_fn = menu.nav
	s.layout_fn = func(_sc: UiScreen, w: float, h: float) -> void:
		var m := UiBlocks.metrics(w, h)
		var vh: float = m.vh
		var px := clampf(7.0 * m.vw, 24.0, 110.0)
		var py := clampf(6.0 * vh, 24.0, 72.0)
		mark.w1 = 40.0 if m.compact else clampf(9.0 * vh, 46.0, 104.0)
		mark.w2 = 70.0 if m.compact else clampf(17.0 * vh, 78.0, 196.0)
		mark.rule_w = minf(340.0, 0.5 * w)
		mark.layout(Vector2(px, py + clampf(4.0 * vh, 8.0, 48.0)))
		foot.visible = UiStyle.device == "keyboard"
		var foot_h := foot.fit() if foot.visible else 0.0
		foot.position = Vector2(px, h - py - foot_h)
		var bottom := h - py - foot_h - 18.0
		var room := bottom - (mark.position.y + mark.size.y + 6.0)
		# The web build lets a long title menu run off a phone; here the rows close up,
		# then Continue's detail moves onto its row, until the menu fits.
		var p: Vector4 = m.item_pad
		var mh := 0.0
		for attempt in 12:
			var tighten := attempt % 6
			menu.inline_detail = attempt >= 6
			menu.set_metrics(m.fs, Vector4(maxf(1.0, p.x - tighten), p.y, maxf(1.0, p.z - tighten), p.w))
			UiStyle.compact = m.compact
			mh = menu.layout(maxf(300.0, menu.natural_width()))
			if mh <= room:
				break
		menu.position = Vector2(px - 14.0, bottom - mh)
	return s


# ---------------------------------------------------------------- programme

## ctx: {save, ids, infos, hooks, on_play(i), on_back}
static func programme(ctx: Dictionary) -> UiScreen:
	var sv: OpusSave = ctx.save
	var ids: Array = ctx.ids
	var infos: Array = ctx.infos
	var items: Array = []
	for i in ids.size():
		var id: String = ids[i]
		var open := sv.unlocked(ids, i)
		var bt = sv.best_time(id)
		var fnd := sv.found(id)
		var notes: Array = []
		for kk in 7:
			notes.append(sv.note_found(id, kk))
		var time := ""
		if bt != null and float(bt) > 0.0:
			time = UiStyle.fmt_time(float(bt))
		elif not sv.is_done(id) and fnd > 0:
			time = "%d of 7" % fnd
		var idx := i
		items.append({
			"id": id, "label": infos[i].title, "kind": "prog", "open": open, "num": UiStyle.ROMAN[i],
			"title": infos[i].title, "tempo": infos[i].tempo, "notes": notes, "time": time,
			"disabled": func() -> bool: return not open,
			"select": func() -> void: ctx.on_play.call(idx),
		})
	items.append({"id": "back", "label": "Back", "select": ctx.on_back, "cls": "back"})
	var menu := UiMenu.new(items, ctx.hooks)
	var total := sv.total_notes(ids)
	var head := _head("Programme", "Tonight", "%d of %d notes restored" % [total, ids.size() * 7])
	var s := _card_screen(head, menu, [], func(w: float) -> float: return minf(680.0, 0.94 * w))
	s.on_scrim = ctx.on_back
	s.nav_fn = func(a: String) -> bool:
		if a == "back":
			ctx.on_back.call()
			return true
		return menu.nav(a)
	return s


# ---------------------------------------------------------------- settings

## ctx: {settings, hooks, on_change, on_controls, on_back, haptics (show the row)}
static func settings(ctx: Dictionary) -> UiScreen:
	var st: Dictionary = ctx.settings
	var change: Callable = ctx.on_change
	var items: Array = [
		_volume(st, "master", "Volume", change),
		_volume(st, "music", "Music", change),
		_volume(st, "sfx", "Effects", change),
	]
	var flip_start := func() -> void:
		st.startIn = "2d" if st.startIn == "3d" else "3d"
		change.call()
	items.append({"id": "startIn", "label": "Begin each movement on", "value": func() -> String: return "The Stage" if st.startIn == "3d" else "The Score", "left": flip_start, "right": flip_start})
	items.append(_toggle(st, "reduceMotion", "Reduce motion", change))
	var q_left := func() -> void:
		st.quality = QUALITY[(QUALITY.find(st.quality) + QUALITY.size() - 1) % QUALITY.size()]
		change.call()
	var q_right := func() -> void:
		st.quality = QUALITY[(QUALITY.find(st.quality) + 1) % QUALITY.size()]
		change.call()
	items.append({"id": "quality", "label": "Detail", "value": func() -> String: return String(st.quality).capitalize(), "left": q_left, "right": q_right})
	items.append(_toggle(st, "showTimer", "Show timer", change))
	if ctx.get("haptics", false):
		items.append(_toggle(st, "haptics", "Vibration", change))
	items.append({"id": "controls", "label": "Controls", "select": ctx.on_controls})
	items.append({"id": "back", "label": "Back", "select": ctx.on_back, "cls": "back"})
	var menu := UiMenu.new(items, ctx.hooks)
	menu.value_scale = 0.72
	menu.value_em = 0.12
	var s := _card_screen(_head("Settings"), menu, [], func(w: float) -> float: return minf(560.0, 0.94 * w))
	s.on_scrim = ctx.on_back
	s.nav_fn = func(a: String) -> bool:
		if a == "back":
			ctx.on_back.call()
			return true
		return menu.nav(a)
	return s


static func _volume(st: Dictionary, key: String, label: String, change: Callable) -> Dictionary:
	var down := func() -> void:
		st[key] = maxf(0.0, roundf((float(st[key]) - 0.1) * 10.0) / 10.0)
		change.call()
	var up := func() -> void:
		st[key] = minf(1.0, roundf((float(st[key]) + 0.1) * 10.0) / 10.0)
		change.call()
	return {"id": key, "label": label, "bar": func() -> float: return float(st[key]), "left": down, "right": up}


static func _toggle(st: Dictionary, key: String, label: String, change: Callable) -> Dictionary:
	var flip := func() -> void:
		st[key] = not bool(st[key])
		change.call()
	return {"id": key, "label": label, "value": func() -> String: return "On" if st[key] else "Off", "left": flip, "right": flip}


## ctx: {hooks, on_back}
static func controls(ctx: Dictionary) -> UiScreen:
	var menu := UiMenu.new([{"id": "back", "label": "Back", "select": ctx.on_back, "cls": "back"}], ctx.hooks)
	var table := UiBlocks.Table.new()
	var s := _card_screen(_head("Controls"), menu, [[table, 0.0, 14.0]], Callable())
	var base_layout: Callable = s.layout_fn
	s.layout_fn = func(sc: UiScreen, w: float, h: float) -> void:
		table.compact = h <= 480.0
		base_layout.call(sc, w, h)
	s.on_scrim = ctx.on_back
	s.nav_fn = func(a: String) -> bool:
		if a == "back":
			ctx.on_back.call()
			return true
		return menu.nav(a)
	return s


# ---------------------------------------------------------------- pause

## ctx: {title, movement, found, hooks, on_resume, on_checkpoint, on_restart, on_settings, on_programme, on_title}
static func pause(ctx: Dictionary) -> UiScreen:
	var menu := UiMenu.new([
		{"id": "resume", "label": "Resume", "select": ctx.on_resume},
		{"id": "checkpoint", "label": "Back to the metronome", "select": ctx.on_checkpoint},
		{"id": "restart", "label": "Restart the movement", "select": ctx.on_restart},
		{"id": "settings", "label": "Settings", "select": ctx.on_settings},
		{"id": "programme", "label": "Programme", "select": ctx.on_programme},
		{"id": "title", "label": "Leave for the title", "select": ctx.on_title},
	], ctx.hooks)
	var s := _card_screen(_head(ctx.title, ctx.movement, "%d of 7 notes" % ctx.found), menu, [], Callable())
	s.on_scrim = ctx.on_resume
	s.nav_fn = func(a: String) -> bool:
		if a == "back" or a == "pause":
			ctx.on_resume.call()
			return true
		return menu.nav(a)
	return s


# ---------------------------------------------------------------- complete

## ctx: {info, notes: Array[bool], time, deaths, switches, best, last, hooks, on_next, on_replay, on_programme}
static func complete(ctx: Dictionary) -> UiScreen:
	var info: Dictionary = ctx.info
	var notes: Array = ctx.notes
	var found := 0
	for n in notes:
		if n:
			found += 1
	var row := UiBlocks.NotesRow.new()
	row.notes = notes
	var line_text := ""
	if found == 7:
		line_text = "Every note is home. The movement plays in full."
	elif found == 0:
		line_text = "The movement is heard, though its notes are still lost."
	else:
		line_text = "%d %s still lost somewhere in this movement." % [7 - found, "note is" if 7 - found == 1 else "notes are"]
	var line := UiLabel.make(line_text, UiStyle.body_i, 16, "fg_dim", HORIZONTAL_ALIGNMENT_CENTER)
	var stats := UiBlocks.Stats.new()
	stats.cells = [
		["Time", UiStyle.fmt_time(ctx.time) + ("  best" if ctx.best else "")],
		["Turns of the world", str(ctx.switches)],
		["Restarts", str(ctx.deaths)],
	]
	var menu := UiMenu.new([
		{"id": "next", "label": "The last bow" if ctx.last else "Next movement", "select": ctx.on_next},
		{"id": "replay", "label": "Play it again", "select": ctx.on_replay},
		{"id": "programme", "label": "Programme", "select": ctx.on_programme},
	], ctx.hooks)
	var head := _head(info.title, "%s complete" % info.movement)
	var s := _card_screen(head, menu, [[row, 4.0, 14.0], [line, 0.0, 8.0], [stats, 0.0, 8.0]], Callable())
	s.layout_fn = func(sc: UiScreen, w: float, h: float) -> void:
		var m := UiBlocks.metrics(w, h)
		_menu_metrics(menu, m)
		head.h2 = m.h2
		head.compact = m.compact
		stats.compact = m.compact
		var gap := 8.0 if m.compact else 18.0
		_layout_card(sc, [[head, 0.0, m.head_mb], [row, 4.0, 14.0], [line, 0.0, gap], [stats, 0.0, 8.0 if m.compact else 20.0], [menu, 0.0, 0.0]], w, h)
	s.nav_fn = menu.nav
	return s


# ---------------------------------------------------------------- credits

## ctx: {hooks, on_back, total}
static func credits(ctx: Dictionary) -> UiScreen:
	var menu := UiMenu.new([{"id": "back", "label": "Back", "select": ctx.on_back, "cls": "back"}], ctx.hooks)
	var roll := UiBlocks.Roll.new()
	roll.set_total(ctx.total)
	var s := UiScreen.new()
	s.kind = "scrim"
	s.card = UiCard.new()
	s.add_child(s.card)
	s.menu = menu
	menu.scroller = s.card
	s.card.content.add_child(roll)
	s.card.content.add_child(menu)
	s.layout_fn = func(sc: UiScreen, w: float, h: float) -> void:
		var m := UiBlocks.metrics(w, h)
		_menu_metrics(menu, m)
		_layout_card(sc, [[roll, 0.0, 16.0], [menu, 0.0, 0.0]], w, h)
	s.on_scrim = ctx.on_back
	s.nav_fn = func(a: String) -> bool:
		if a == "back":
			ctx.on_back.call()
			return true
		return menu.nav(a)
	return s

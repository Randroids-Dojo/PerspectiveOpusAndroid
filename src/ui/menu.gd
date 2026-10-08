class_name UiMenu
extends Control
## A vertical list driven by keyboard, gamepad, mouse and touch alike, a port of the
## web build's src/ui/menu.ts. The focused item wears the eighth-note glyph.
##
## Items are dictionaries: {id, label (String or Callable), value (Callable -> String),
## bar (Callable -> float, a volume row), detail (Callable -> String), disabled
## (Callable -> bool), select, left, right (Callables), cls ("back"), kind ("prog")}.

var items: Array = []
## {hover, select, blocked}: Callables for the menu sounds.
var hooks: Dictionary = {}
var index := 0
var views: Array[UiMenuItem] = []
## The CSS .menu-item font size and padding (top, right, bottom, left).
var fs := 17.0
var pad := Vector4(6, 12, 6, 28)
var value_scale := 0.86
var value_em := 0.06
## Set by the card that scrolls this menu, so key moves keep the focus in view.
var scroller: UiCard = null
## Cleared while the screen fades out or sits under another.
var live := true
## Put item details on the label's row (the title on short screens).
var inline_detail := false


func _init(list: Array, menu_hooks: Dictionary = {}) -> void:
	items = list
	hooks = menu_hooks
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in items.size():
		var v := UiMenuItem.new(self, i, items[i])
		views.append(v)
		add_child(v)
	index = 0
	for i in items.size():
		if not _disabled(i):
			index = i
			break
	_apply_focus(false)


func set_metrics(font_size: float, padding: Vector4) -> void:
	fs = font_size
	pad = padding


## Lays the items out top to bottom at `width` and returns the menu's height.
func layout(width: float) -> float:
	var y := 0.0
	for i in views.size():
		var v := views[i]
		if i > 0:
			y += 2.0
		if items[i].get("cls", "") == "back":
			y += 10.0
		var hh := v.measure()
		v.position = Vector2(0, y)
		v.size = Vector2(width, hh)
		y += hh
	size = Vector2(width, y)
	return y


## The widest an item wants to be (labels, values and paddings).
func natural_width() -> float:
	var w := 0.0
	for v in views:
		w = maxf(w, v.natural_width())
	return w


func _disabled(i: int) -> bool:
	var d = items[i].get("disabled")
	return d is Callable and d.call()


func focus(i: int, sound: bool) -> void:
	if views.is_empty():
		return
	index = clampi(i, 0, views.size() - 1)
	_apply_focus(true)
	if scroller:
		scroller.reveal(views[index])
	if sound:
		_hook("hover")


func _apply_focus(_animate: bool) -> void:
	for j in views.size():
		views[j].focused = j == index


func _hook(name: String) -> void:
	var h = hooks.get(name)
	if h is Callable:
		h.call()


func _move(dir: int) -> void:
	var n := items.size()
	for kk in range(1, n + 1):
		var j := posmod(index + dir * kk, n)
		if not _disabled(j):
			focus(j, true)
			return


func _step(dir: int) -> void:
	var it: Dictionary = items[index]
	var fn = it.get("left") if dir < 0 else it.get("right")
	if not (fn is Callable):
		return
	fn.call()
	_hook("hover")
	refresh()


func activate() -> void:
	if index >= items.size():
		return
	var it: Dictionary = items[index]
	if _disabled(index):
		_hook("blocked")
		return
	if it.get("select") is Callable:
		_hook("select")
		it.select.call()
	elif it.get("right") is Callable:
		_step(1)


func nav(a: String) -> bool:
	match a:
		"up":
			_move(-1)
		"down":
			_move(1)
		"left":
			_step(-1)
		"right":
			_step(1)
		"confirm":
			activate()
		_:
			return false
	return true


func refresh() -> void:
	for v in views:
		v.queue_redraw()


## A tap or click on item i at a fraction x of its width.
func clicked(i: int, x_frac: float) -> void:
	if not live:
		return
	focus(i, false)
	var it: Dictionary = items[i]
	# Clicking the left or right part of a value row steps it.
	if it.get("left") is Callable and it.get("right") is Callable and (it.has("value") or it.has("bar")):
		_step(-1 if x_frac < 0.4 else 1)
		return
	activate()


## Mouse hover focuses, as on the web build's desktop (never on touch screens).
func hovered(i: int) -> void:
	if live and index != i and not _disabled(i):
		focus(i, true)


func find_label(prefix: String) -> UiMenuItem:
	for v in views:
		if v.label_text().begins_with(prefix):
			return v
	return null

class_name UiScreen
extends Control
## One entry on the director's screen stack, like the web build's .screen: fades in
## (0.35 s), out (then leaves), or under the screen pushed on top of it. Tapping the
## dimmed area around a card can close it.

## "scrim" (menus over the world), "title" (the title's side wash), "ending" or "".
var kind := ""
var card: UiCard
## The screen's main menu, for the director's tests.
var menu: UiMenu
## (a: String) -> bool: true if handled. An unhandled "back" pops the stack.
var nav_fn: Callable
## Tap on the scrim around the card.
var on_scrim: Callable
var leave_fn: Callable
## (screen, w, h) -> void: builds the layout at a size.
var layout_fn: Callable
## "new", "in", "under" or "out".
var state := "new"
var opacity := 0.0
var _press := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func nav(a: String) -> bool:
	return nav_fn.call(a) if nav_fn.is_valid() else false


func relayout(w: float, h: float) -> void:
	size = Vector2(w, h)
	if layout_fn.is_valid():
		layout_fn.call(self, w, h)
	queue_redraw()


func set_state(s: String) -> void:
	state = s
	var live := s == "in"
	_set_live(self, live)
	if card:
		card.rising = live or s == "under"
	if menu:
		menu.live = live


func _set_live(n: Node, live: bool) -> void:
	if n is Control:
		var c := n as Control
		if not c.has_meta("mf"):
			c.set_meta("mf", c.mouse_filter)
		c.mouse_filter = c.get_meta("mf") if live else Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_set_live(ch, live)


func _process(dt: float) -> void:
	var target := 1.0 if state == "in" else 0.0
	if opacity != target:
		opacity = move_toward(opacity, target, dt / 0.35)
	modulate.a = UiStyle.ease(opacity) if target > 0.0 else 1.0 - UiStyle.ease(1.0 - opacity)
	visible = modulate.a > 0.002 or state == "in"
	if kind != "":
		queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	match kind:
		"scrim":
			UiStyle.radial_box(self, box, Vector2(0.5, 0.45), [[0.0, UiStyle.c("scrim_in")], [1.0, UiStyle.c("scrim_out")]])
		"title":
			var c := UiStyle.c("title_bg")
			UiStyle.linear_x(self, box, [[0.0, c], [0.55, UiStyle.fade(c, 0.0)], [1.0, UiStyle.fade(c, 0.0)]])
		"ending":
			var c := Color(8 / 255.0, 4 / 255.0, 10 / 255.0, 0.5)
			UiStyle.radial_box(self, box, Vector2(0.5, 0.6), [[0.0, UiStyle.fade(c, 0.0)], [1.0, c]])


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = true
		elif _press:
			_press = false
			if on_scrim.is_valid():
				on_scrim.call()
		accept_event()

class_name UiLabel
extends Control
## A line of text (or a wrapped paragraph) in a colour role of the current world.

var text := ""
var font: Font
var font_size := 16
## "fg", "fg_dim" or "accent".
var role := "fg"
## CSS letter-spacing in em, and text-transform: uppercase.
var em := 0.0
var upper := false
var align := HORIZONTAL_ALIGNMENT_LEFT
var shadow := false
## CSS line-height in px (<= 0 for "normal"). Text wider than the label wraps.
var line_height := 0.0
var alpha := 1.0


static func make(t: String, f: Font, sz: float, r := "fg", a := HORIZONTAL_ALIGNMENT_LEFT) -> UiLabel:
	var l := UiLabel.new()
	l.text = t
	l.font = f
	l.font_size = roundi(sz)
	l.role = r
	l.align = a
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _font() -> Font:
	return UiStyle.spaced(font, font_size, em) if em != 0.0 else font


func _shown() -> String:
	return text.to_upper() if upper else text


func _lh() -> float:
	var f := _font()
	return line_height if line_height > 0.0 else f.get_ascent(font_size) + f.get_descent(font_size)


func text_width() -> float:
	return UiStyle.width(_font(), font_size, _shown())


func measure_height(w: float) -> float:
	if w > 0.0 and text_width() > w + 0.5:
		return _lh() * _wrap_lines(_font(), _shown(), w).size()
	return _lh()


## Sizes the label to its text at width `w` (or its own width) and returns the height.
func fit(w := -1.0) -> float:
	var ww := w if w > 0.0 else text_width()
	size = Vector2(ww, measure_height(ww))
	return size.y


func _draw() -> void:
	var f := _font()
	var col := UiStyle.c(role)
	col.a *= alpha
	var lh := _lh()
	var s := _shown()
	var base := UiStyle.baseline(f, font_size, lh)
	if text_width() > size.x + 0.5 and size.x > 0.0:
		var lines := _wrap_lines(f, s, size.x)
		for li in lines.size():
			UiStyle.text(self, f, font_size, Vector2(0, base + li * lh), lines[li], col, shadow, size.x, align)
		return
	UiStyle.text(self, f, font_size, Vector2(0, base), s, col, shadow, size.x, align)


func _wrap_lines(f: Font, s: String, w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if line != "" and UiStyle.width(f, font_size, t) > w:
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out

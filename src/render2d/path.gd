class_name PagePath
extends RefCounted
## A Canvas 2D style path: subpaths of points made with move_to, line_to, curves, arcs and
## rects. Curves and arcs are flattened as they are added. The painter fills (each subpath
## as a polygon) or strokes it.

var pts := PackedVector2Array()
var starts := PackedInt32Array()
var closed := PackedByteArray()
## Target length of the straight pieces curves are flattened into.
var seg_px := 3.0


func clear() -> void:
	pts.clear()
	starts.clear()
	closed.clear()


func is_empty() -> bool:
	return starts.is_empty()


func count() -> int:
	return starts.size()


func subpath(i: int) -> PackedVector2Array:
	var e := pts.size() if i + 1 >= starts.size() else starts[i + 1]
	return pts.slice(starts[i], e)


func is_closed(i: int) -> bool:
	return closed[i] != 0


func move_to(x: float, y: float) -> void:
	starts.append(pts.size())
	closed.append(0)
	pts.append(Vector2(x, y))


func line_to(x: float, y: float) -> void:
	if starts.is_empty():
		move_to(x, y)
		return
	pts.append(Vector2(x, y))


func close() -> void:
	if not closed.is_empty():
		closed[closed.size() - 1] = 1


func _last() -> Vector2:
	return pts[pts.size() - 1]


func quad_to(cx: float, cy: float, x: float, y: float) -> void:
	if starts.is_empty():
		move_to(cx, cy)
	var p0 := _last()
	var c := Vector2(cx, cy)
	var p1 := Vector2(x, y)
	var n := clampi(ceili((p0.distance_to(c) + c.distance_to(p1)) / seg_px), 2, 32)
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * (u * u) + c * (2.0 * u * t) + p1 * (t * t))


func bezier_to(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void:
	if starts.is_empty():
		move_to(c1x, c1y)
	var p0 := _last()
	var c1 := Vector2(c1x, c1y)
	var c2 := Vector2(c2x, c2y)
	var p1 := Vector2(x, y)
	var n := clampi(ceili((p0.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(p1)) / seg_px), 2, 48)
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(p0 * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + p1 * (t * t * t))


## ctx.ellipse: joins from the current point (if any) to the start of the arc.
func ellipse(cx: float, cy: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false) -> void:
	var a := PageInk.arc_pts(cx, cy, rx, ry, rot, a0, a1, ccw, seg_px)
	var i0 := 0
	if starts.is_empty():
		move_to(a[0].x, a[0].y)
		i0 = 1
	elif _last().distance_squared_to(a[0]) < 1e-6:
		i0 = 1
	for i in range(i0, a.size()):
		pts.append(a[i])


func arc(cx: float, cy: float, r: float, a0: float, a1: float, ccw: bool = false) -> void:
	ellipse(cx, cy, r, r, 0.0, a0, a1, ccw)


## A full circle as its own closed subpath.
func circle(cx: float, cy: float, r: float) -> void:
	move_to(cx + r, cy)
	arc(cx, cy, r, 0.0, TAU)
	close()


func rect(x: float, y: float, w: float, h: float) -> void:
	move_to(x, y)
	pts.append(Vector2(x + w, y))
	pts.append(Vector2(x + w, y + h))
	pts.append(Vector2(x, y + h))
	close()


## Adds a whole point list as a subpath.
func add(p: PackedVector2Array, is_closed: bool) -> void:
	if p.is_empty():
		return
	starts.append(pts.size())
	closed.append(1 if is_closed else 0)
	pts.append_array(p)

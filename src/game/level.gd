class_name Level
extends RefCounted
## A compiled level, loaded from the data baked by tools/export_levels.ts from the
## web build, so both builds play the identical world.

const NO_DEPTH := 255

const MAT_EMPTY := 0
const MAT_STONE := 1
const MAT_BRICK := 2
const MAT_WOOD := 3
const MAT_BRASS := 4
const MAT_DARK := 5
const MAT_CRYSTAL := 6
const MAT_LEAF := 7
const MAT_THORN := 8
const MAT_MARBLE := 9
const MAT_NAMES := ["empty", "stone", "brick", "wood", "brass", "dark", "crystal", "leaf", "thorn", "marble"]

var info: Dictionary
var w: int
var h: int
var d: int
## Material per voxel, index x + w * (y + h * z).
var cells: PackedByteArray
## Front-most solid z per column (x, y), or NO_DEPTH. Index x + w * y.
var front: PackedByteArray
var depth_count: PackedByteArray
## 1 if any thorn lies in the column (x, y).
var thorn_col: PackedByteArray
var spawn: V3
## Each: {id, pos: V3}
var notes: Array = []
## Each: {id, pos: V3}
var checkpoints: Array = []
var exit_pos: V3
## Each: {id, size: V3, path: Array[V3], speed, pause, loop, group (-1 if none), phase, mat}
var platforms: Array = []
## Each: {id, pos: V3, power}
var drums: Array = []
## Each: {id, pos: V3, group, width}
var keys: Array = []
## Each: {id, min: V3, max: V3, group, solidWhenOn}
var gates: Array = []
## Each: {id, path: Array[V3], speed, phase}
var discords: Array = []
## Each: {id, pos: V3, radius, hint, mode ("" if any)}
var signs: Array = []
## Each: {id, kind, pos: V3, scale, rot, seed}
var decor: Array = []
var groups_on: Array = []
var id: String
var water: float = NAN


static func is_solid_mat(m: int) -> bool:
	return m != MAT_EMPTY and m != MAT_THORN


static func load_id(level_id: String) -> Level:
	var f := FileAccess.open("res://assets/data/levels/%s.json" % level_id, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var lv := Level.new()
	lv._parse(data)
	return lv


static func movement_ids() -> Array:
	var f := FileAccess.open("res://assets/data/levels/index.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	return data.movements


func _parse(data: Dictionary) -> void:
	info = data.info
	id = String(info.id)
	if info.has("water"):
		water = float(info.water)
	w = int(data.w)
	h = int(data.h)
	d = int(data.d)
	cells = Marshalls.base64_to_raw(data.cells)
	front = PackedByteArray()
	front.resize(w * h)
	front.fill(NO_DEPTH)
	depth_count = PackedByteArray()
	depth_count.resize(w * h)
	thorn_col = PackedByteArray()
	thorn_col.resize(w * h)
	for y in h:
		for x in w:
			for z in d:
				var m := cells[x + w * (y + h * z)]
				if is_solid_mat(m):
					if front[x + w * y] == NO_DEPTH:
						front[x + w * y] = z
					depth_count[x + w * y] += 1
				elif m == MAT_THORN:
					thorn_col[x + w * y] = 1
	spawn = V3.from_dict(data.spawn)
	exit_pos = V3.from_dict(data.exit.pos)
	for n in data.notes:
		notes.append({"id": int(n.id), "pos": V3.from_dict(n.pos)})
	for c in data.checkpoints:
		checkpoints.append({"id": int(c.id), "pos": V3.from_dict(c.pos)})
	for p in data.platforms:
		var path: Array = []
		for q in p.path:
			path.append(V3.from_dict(q))
		platforms.append({
			"id": int(p.id), "size": V3.from_dict(p.size), "path": path, "speed": float(p.speed),
			"pause": float(p.pause), "loop": bool(p.loop), "group": int(p.group) if p.has("group") and p.group != null else -1,
			"phase": float(p.phase), "mat": String(p.mat),
		})
	for dr in data.drums:
		drums.append({"id": int(dr.id), "pos": V3.from_dict(dr.pos), "power": float(dr.power)})
	for k in data["keys"]:
		keys.append({"id": int(k.id), "pos": V3.from_dict(k.pos), "group": int(k.group), "width": int(k.width)})
	for g in data.gates:
		gates.append({"id": int(g.id), "min": V3.from_dict(g.min), "max": V3.from_dict(g.max), "group": int(g.group), "solidWhenOn": bool(g.solidWhenOn)})
	for ds in data.discords:
		var dpath: Array = []
		for q in ds.path:
			dpath.append(V3.from_dict(q))
		discords.append({"id": int(ds.id), "path": dpath, "speed": float(ds.speed), "phase": float(ds.phase)})
	for s in data.signs:
		signs.append({
			"id": int(s.id), "pos": V3.from_dict(s.pos), "radius": float(s.radius), "hint": String(s.hint),
			"mode": String(s.mode) if s.has("mode") and s.mode != null else "",
		})
	for dc in data.decor:
		decor.append({"id": int(dc.id), "kind": String(dc.kind), "pos": V3.from_dict(dc.pos), "scale": float(dc.scale), "rot": float(dc.rot), "seed": int(dc.seed)})
	for g in data.groupsOn:
		groups_on.append(int(g))


func mat_at(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= w or y >= h or z >= d:
		return MAT_EMPTY
	return cells[x + w * (y + h * z)]


func solid_at(x: int, y: int, z: int) -> bool:
	return is_solid_mat(mat_at(x, y, z))


func has_water() -> bool:
	return not is_nan(water)

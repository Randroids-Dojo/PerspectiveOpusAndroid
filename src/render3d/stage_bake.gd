class_name StageBake
extends RefCounted
## One level start of the web Stage, baked by tools/bake_stage.ts: its scene graph, the
## geometry and materials of every mesh, and the state each stage module animates from.
## build() turns the scene graph into Godot nodes; resolve() turns a module's state into
## dictionaries whose scene references point at those nodes and materials.

var data: Dictionary
var bin: PackedByteArray
var level_id := ""
var palette_id := ""
## Godot node per baked node id.
var nodes: Array = []
## Godot materials made for each baked material id (one per shadow and sort variant).
var mat_instances: Array = []
var _meshes := {}
var _mats := {}
var _texs := {}
var _factory: StageMaterials


static func exists(level: String, palette: String) -> bool:
	return FileAccess.file_exists("res://assets/data/stage/%s__%s.json" % [level, palette])


static func open(level: String, palette: String, factory: StageMaterials) -> StageBake:
	var b := StageBake.new()
	var base := "res://assets/data/stage/%s__%s" % [level, palette]
	b.data = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	b.bin = FileAccess.get_file_as_bytes(base + ".bin").decompress(int(b.data.binSize), FileAccess.COMPRESSION_ZSTD)
	b.level_id = level
	b.palette_id = palette
	b._factory = factory
	b.nodes.resize(b.data.nodes.size())
	b.mat_instances.resize(b.data.mats.size())
	for i in b.mat_instances.size():
		b.mat_instances[i] = []
	return b


## Decodes one packed array from the blob.
func arr(rec: Dictionary) -> Variant:
	var off := int(rec.off)
	return bytes_to_var(bin.slice(off, off + int(rec.len)))


func texture(name: String) -> Dictionary:
	if _texs.has(name):
		return _texs[name]
	var info := {}
	match name:
		"sprites":
			info = {"tex": _factory.sprites, "srgb": false}
		"clouds":
			info = {"tex": _factory.clouds, "srgb": false}
		"moon":
			info = {"tex": _factory.moon, "srgb": true}
		_:
			for t in data.texs:
				if t.name == name:
					info = {"tex": load(String(t.file)), "srgb": bool(t.srgb)}
	_texs[name] = info
	return info


func mesh(gid: int) -> ArrayMesh:
	if _meshes.has(gid):
		return _meshes[gid]
	var g: Dictionary = data.geos[gid]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = arr(g.v)
	if g.has("n"):
		arrays[Mesh.ARRAY_NORMAL] = arr(g.n)
	if g.has("uv"):
		arrays[Mesh.ARRAY_TEX_UV] = arr(g.uv)
	var fmt := 0
	if g.has("c0"):
		arrays[Mesh.ARRAY_CUSTOM0] = arr(g.c0)
		fmt |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if g.has("c1"):
		var c1: PackedFloat32Array = arr(g.c1)
		if g.get("c1IsSeed", false):
			# Stars keep their seed in CUSTOM0.x.
			arrays[Mesh.ARRAY_CUSTOM0] = c1
			fmt |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		else:
			arrays[Mesh.ARRAY_CUSTOM1] = c1
			fmt |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	if g.has("i"):
		arrays[Mesh.ARRAY_INDEX] = arr(g.i)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS if g.get("points", false) else Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	_meshes[gid] = m
	return m


## The Godot material for a baked material id, for a node that does or does not receive
## shadows and sorts at `order`.
func material(mid: int, receive: bool, order: int, level: bool) -> ShaderMaterial:
	var key := "%d:%s:%d:%s" % [mid, receive, order, level]
	if _mats.has(key):
		return _mats[key]
	var m := _factory.make(data.mats[mid], receive, order, level, texture)
	_mats[key] = m
	if m != null:
		mat_instances[mid].append(m)
	return m


## Builds the subtree under baked node `id` and adds it to `parent`. `level` is false for
## the backdrop scene: no fog and no shadows there.
func build(id: int, parent: Node, level: bool) -> Node3D:
	var n: Dictionary = data.nodes[id]
	var node: Node3D
	var t := String(n.type)
	var mat_id := -1
	if n.has("mat"):
		mat_id = int(n.mat[0]) if n.mat is Array else int(n.mat)
	if n.has("buffer"):
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = bool(n.colors)
		mm.mesh = mesh(int(n.geo))
		mm.instance_count = int(n.capacity)
		mm.buffer = arr(n.buffer)
		mm.visible_instance_count = int(n.count)
		mmi.multimesh = mm
		node = mmi
	elif n.has("geo") and not data.geos[int(n.geo)].inst.is_empty():
		node = _instanced(n)
	elif n.has("geo"):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh(int(n.geo))
		node = mi
	else:
		node = Node3D.new()
	node.name = "n%d_%s" % [id, t]
	node.rotation_order = EULER_ORDER_XYZ
	node.position = StageMaterials.v3(n.p)
	node.quaternion = Quaternion(float(n.q[0]), float(n.q[1]), float(n.q[2]), float(n.q[3]))
	node.scale = StageMaterials.v3(n.s)
	node.visible = bool(n.vis)
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (level and bool(n.cast)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not bool(n.culled):
			gi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		if mat_id >= 0:
			gi.material_override = material(mat_id, bool(n.recv), int(n.ro), level)
	nodes[id] = node
	parent.add_child(node)
	for c in n.children:
		build(int(c), node, level)
	return node


## A mesh drawn from instanced attributes (clouds, mist banks): a MultiMesh whose
## INSTANCE_CUSTOM is the first vec4 attribute and COLOR.xy the size attribute.
func _instanced(n: Dictionary) -> Node3D:
	var g: Dictionary = data.geos[int(n.geo)]
	var count := int(g.instanceCount)
	var main: PackedFloat32Array
	var size: PackedFloat32Array
	for k in g.inst:
		var a: Dictionary = g.inst[k]
		if int(a.size) == 4:
			main = arr(a)
		elif int(a.size) == 2:
			size = arr(a)
	var buf := PackedFloat32Array()
	buf.resize(count * 20)
	for i in count:
		var o := i * 20
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
		buf[o + 12] = size[i * 2] if size.size() > 0 else 1.0
		buf[o + 13] = size[i * 2 + 1] if size.size() > 0 else 1.0
		buf[o + 14] = 0.0
		buf[o + 15] = 1.0
		for k in 4:
			buf[o + 16 + k] = main[i * 4 + k]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh(int(n.geo))
	mm.instance_count = count
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A module's state with references replaced: {$node} -> Node3D, {$mat} -> baked material
## id (see mat_instances), {$c}/{$v3} -> Vector3, {$v2} -> Vector2, {$q} -> Quaternion.
func resolve(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("$node"):
			return nodes[int(v["$node"])]
		if v.has("$mat"):
			return {"mat": int(v["$mat"])}
		if v.has("$c"):
			return StageMaterials.v3(v["$c"])
		if v.has("$v3"):
			return StageMaterials.v3(v["$v3"])
		if v.has("$v2"):
			return Vector2(float(v["$v2"][0]), float(v["$v2"][1]))
		if v.has("$v4"):
			var a: Array = v["$v4"]
			return Vector4(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		if v.has("$q"):
			var q: Array = v["$q"]
			return Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
		if v.has("$geo"):
			return {"geo": int(v["$geo"])}
		var out := {}
		for k in v:
			out[k] = resolve(v[k])
		return out
	if v is Array:
		var out2 := []
		for x in v:
			out2.append(resolve(x))
		return out2
	return v


func module(name: String) -> Variant:
	return resolve(data.modules[name])


## The baked material ids' Godot instances, for per-frame uniform changes.
func mats_of(ref: Variant) -> Array:
	if ref is Dictionary and ref.has("mat"):
		return mat_instances[int(ref.mat)]
	return []

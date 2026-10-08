class_name WorldMesh
extends RefCounted
## The voxel world, a port of the web Stage's buildWorld: exposed faces only, in chunks of
## 16 columns along x, with per-vertex ambient occlusion and per-face edge flags for the
## bevel in shaders/world.gdshader. CUSTOM0 carries three.js's aInfo: texture layer, AO,
## open-edge bits, cap flag.

const CHUNK := 16
const VARIANTS := 4
const AO_CURVE := [0.32, 0.58, 0.8, 1.0]
## Material id to its index in the texture array's material order (stone, brick, wood,
## brass, dark, crystal, leaf, marble); thorns and empty cells are not blocks.
const MAT_INDEX := {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 9: 7}
const MAT_ORDER := ["stone", "brick", "wood", "brass", "dark", "crystal", "leaf", "marble"]

## n, u, v, o, flip for +x, -x, +y, -y, +z, -z.
const FACES := [
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), true],
	[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0), false],
	[Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), true],
	[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 0), false],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), false],
	[Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 0), true],
]


static func _i32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## The web build's hash3 (src/core/math.ts), including its double-precision multiply.
static func hash3(x: int, y: int, z: int) -> float:
	var h := _i32(x * 374761393 + y * 668265263 + z * 2147483647)
	var t := _i32(h ^ ((h & 0xFFFFFFFF) >> 13))
	var p := int(float(t) * 1274126177.0)
	var lo := p & 0xFFFFFFFF
	var r := (_i32(lo) ^ (lo >> 16)) & 0xFFFFFFFF
	return float(r) / 4294967296.0


## Which materials take the palette's top cap.
static func capable(mi: int, cap: String) -> bool:
	if cap == "none":
		return false
	var name: String = MAT_ORDER[mi]
	if name == "brass" or name == "crystal":
		return false
	if name == "leaf":
		return cap == "snow" or cap == "leaves"
	if name == "wood":
		return cap != "grass"
	if name == "brick":
		return cap != "carpet"
	return true


## One ArrayMesh per chunk that has faces.
static func build(lv: Level, cap: String) -> Array[ArrayMesh]:
	var w := lv.w
	var h := lv.h
	var d := lv.d
	var cells := lv.cells
	# Solid lookup with a one-cell border so neighbour tests need no bounds checks.
	var pw := w + 2
	var ph := h + 2
	var pd := d + 2
	var solid := PackedByteArray()
	solid.resize(pw * ph * pd)
	for z in d:
		for y in h:
			var row := w * (y + h * z)
			var prow := 1 + pw * ((y + 1) + ph * (z + 1))
			for x in w:
				var m := cells[row + x]
				if m != Level.MAT_EMPTY and m != Level.MAT_THORN:
					solid[prow + x] = 1
	var sx := 1
	var sy := pw
	var sz := pw * ph
	var out: Array[ArrayMesh] = []
	for cx in range(0, w, CHUNK):
		var pos := PackedVector3Array()
		var nor := PackedVector3Array()
		var uv := PackedVector2Array()
		var info := PackedFloat32Array()
		var idx := PackedInt32Array()
		var xe := mini(w, cx + CHUNK)
		for z in d:
			for y in h:
				for x in range(cx, xe):
					var m := cells[x + w * (y + h * z)]
					if m == Level.MAT_EMPTY or m == Level.MAT_THORN:
						continue
					var mi: int = MAT_INDEX.get(m, 0)
					var variant := int(floor(hash3(x, y, z) * VARIANTS)) % VARIANTS
					var layer := float(mi * VARIANTS + variant)
					var p0 := (x + 1) * sx + (y + 1) * sy + (z + 1) * sz
					var top_open := solid[p0 + sy] == 0
					var capped := 1.0 if top_open and capable(mi, cap) else 0.0
					for f in 6:
						var F: Array = FACES[f]
						var fn: Vector3i = F[0]
						var fu: Vector3i = F[1]
						var fv: Vector3i = F[2]
						var fo: Vector3i = F[3]
						var flip: bool = F[4]
						var nidx := p0 + fn.x * sx + fn.y * sy + fn.z * sz
						if solid[nidx] == 1:
							continue
						if fn.y == -1 and y == 0:
							continue
						var base := pos.size()
						var du := fu.x * sx + fu.y * sy + fu.z * sz
						var dv := fv.x * sx + fv.y * sy + fv.z * sz
						var ao := [0, 0, 0, 0]
						for k in 4:
							var cu := 1 if (k == 1 or k == 2) else 0
							var cv := 1 if k >= 2 else 0
							pos.append(Vector3(x + fo.x + cu * fu.x + cv * fv.x, y + fo.y + cu * fu.y + cv * fv.y, z + fo.z + cu * fu.z + cv * fv.z))
							nor.append(Vector3(fn))
							uv.append(Vector2(cu, cv))
							var su := 1 if cu == 1 else -1
							var sv := 1 if cv == 1 else -1
							var s1 := solid[nidx + su * du]
							var s2 := solid[nidx + sv * dv]
							var cr := solid[nidx + su * du + sv * dv]
							ao[k] = 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + cr)
						var bits := 0
						if solid[p0 - du] == 0:
							bits |= 1
						if solid[p0 + du] == 0:
							bits |= 2
						if solid[p0 - dv] == 0:
							bits |= 4
						if solid[p0 + dv] == 0:
							bits |= 8
						var cap_flag := 0.0 if fn.y == -1 else capped
						for k in 4:
							info.append(layer)
							info.append(AO_CURVE[ao[k]])
							info.append(float(bits))
							info.append(cap_flag)
						var alt: bool = ao[0] + ao[2] < ao[1] + ao[3]
						var a0 := 1 if alt else 0
						var a1 := 2 if alt else 1
						var a2 := 3 if alt else 2
						var a3 := 0 if alt else 3
						# The web build's triangles with the winding reversed for Godot.
						if flip:
							idx.append_array([base + a0, base + a1, base + a2, base + a0, base + a2, base + a3])
						else:
							idx.append_array([base + a0, base + a2, base + a1, base + a0, base + a3, base + a2])
		if idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nor
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_CUSTOM0] = info
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.append(mesh)
	return out


## The block material for a palette, from the uniforms the bake recorded.
static func material(factory: StageMaterials, u: Dictionary) -> ShaderMaterial:
	var m := factory.lit("world")
	m.set_shader_parameter("detail_arr", factory.detail)
	m.set_shader_parameter("normal_arr", factory.normal_arr)
	for pair in [["uCol1", "col1"], ["uCol2", "col2"], ["uGrout", "grout"], ["uEmis", "emis"]]:
		var a := PackedVector3Array()
		for c in u[pair[0]]:
			a.append(StageMaterials.v3(c.c))
		m.set_shader_parameter(pair[1], a)
	var props := PackedVector4Array()
	for p in u.uProps:
		props.append(Vector4(float(p.v4[0]), float(p.v4[1]), float(p.v4[2]), float(p.v4[3])))
	m.set_shader_parameter("props", props)
	var mac := PackedFloat32Array()
	for v in u.uMacro:
		mac.append(float(v))
	m.set_shader_parameter("macro", mac)
	m.set_shader_parameter("cap1", StageMaterials.v3(u.uCap1.c))
	m.set_shader_parameter("cap2", StageMaterials.v3(u.uCap2.c))
	m.set_shader_parameter("cap_grout", StageMaterials.v3(u.uCapGrout.c))
	m.set_shader_parameter("cap_layer", float(u.uCapLayer))
	m.set_shader_parameter("cap_on", float(u.uCapOn))
	var cs: Array = u.uCapStyle.v4
	m.set_shader_parameter("cap_style", Vector4(float(cs[0]), float(cs[1]), float(cs[2]), float(cs[3])))
	m.set_shader_parameter("glow_pulse", float(u.uGlowPulse))
	m.set_shader_parameter("macro_layer", float(u.uMacroLayer))
	return m

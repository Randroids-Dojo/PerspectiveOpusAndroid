class_name StageMaterials
extends RefCounted
## Turns the web Stage's materials (as baked by tools/bake_stage.ts) into Godot shader
## materials that reproduce them: lit materials run the three.js lighting port in
## shaders/pbr.gdshaderinc, unlit ones shaders/basic.gdshaderinc, and the web build's
## own shader materials have a shader each.

const SHADERS := "res://src/render3d/shaders/"

## three.js constants.
const NORMAL_BLENDING := 1
const ADDITIVE_BLENDING := 2
const DOUBLE_SIDE := 2
const GREATER_DEPTH := 6

var globals: StageGlobals
var dfg_lut: ImageTexture
var env_map: Texture2D
var env_cube := Vector3(1.0 / 384.0, 1.0 / 512.0, 7.0)
var detail: TextureLayered
var normal_arr: TextureLayered
var sprites: Texture2D
var clouds: Texture2D
var moon: Texture2D
var _shaders := {}


func _init(g: StageGlobals) -> void:
	globals = g
	var f := FileAccess.open("res://assets/data/stage/dfg.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var size := int(d.size)
	var rg := PackedFloat32Array()
	for v in d.rg:
		rg.append(float(v))
	dfg_lut = ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGF, rg.to_byte_array()))
	detail = load("res://assets/stage/detail.png")
	normal_arr = load("res://assets/stage/normal.png")
	sprites = load("res://assets/stage/sprites.png")
	clouds = load("res://assets/stage/clouds.png")
	moon = load("res://assets/stage/moon.png")


func shader(name: String) -> Shader:
	if not _shaders.has(name):
		_shaders[name] = load(SHADERS + name + ".gdshader")
	return _shaders[name]


## Points lit materials at a palette's PMREM environment.
func set_palette_env(palette_id: String) -> void:
	env_map = load("res://assets/stage/env_%s.hdr" % palette_id)
	var h := float(env_map.get_height())
	var max_mip := log(h) / log(2.0) - 2.0
	env_cube = Vector3(1.0 / (3.0 * maxf(pow(2.0, max_mip), 112.0)), 1.0 / h, max_mip)


static func v3(a: Variant) -> Vector3:
	if a == null:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A lit material with the common bindings.
func lit(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	m.set_shader_parameter("stage_globals", globals.texture)
	m.set_shader_parameter("env_map", env_map)
	m.set_shader_parameter("env_cube", env_cube)
	m.set_shader_parameter("dfg_lut", dfg_lut)
	return m


func unlit(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	m.set_shader_parameter("stage_globals", globals.texture)
	return m


## Which std variant a baked MeshStandardMaterial / MeshPhysicalMaterial needs.
static func std_variant(d: Dictionary) -> String:
	var key := String(d.get("key", ""))
	match key:
		"opus:chw:pdiffuse", "opus:chw:pmetal":
			return "prop_wind"
		"opus:chw:pcloth":
			return "prop_cloth"
		"opus:ch:pgloss":
			return "prop"
		"opus:ch:pgolddim":
			return "std_patched"
		"opus:ch:tuft":
			return "tuft"
		"opus:ch:thorn", "opus:ch:cog":
			return "hot"
		"opus:ch:drumhead":
			return "drumhead"
		"opus:ch:gate":
			return "gate"
	if d.type == "MeshPhysicalMaterial":
		if float(d.get("clearcoat", 0.0)) > 0.0:
			return "lacquer"
		if float(d.get("sheen", 0.0)) > 0.0:
			return "scarf"
		if float(d.get("iridescence", 0.0)) > 0.0:
			return "discord"
	return "std_ds" if int(d.side) == DOUBLE_SIDE else "std"


## Builds the Godot material for a baked material. `texs` resolves texture names,
## `level` is false for the backdrop scene (which has no fog).
func make(d: Dictionary, receive: bool, priority: int, level: bool, texs: Callable) -> ShaderMaterial:
	var m: ShaderMaterial
	var t := String(d.type)
	if t == "MeshStandardMaterial" or t == "MeshPhysicalMaterial":
		m = lit(std_variant(d))
		m.set_shader_parameter("color", v3(d.get("color")))
		m.set_shader_parameter("roughness", float(d.get("roughness", 1.0)))
		m.set_shader_parameter("metalness", float(d.get("metalness", 0.0)))
		m.set_shader_parameter("emissive", v3(d.get("emissive")) * float(d.get("emissiveIntensity", 1.0)))
		m.set_shader_parameter("use_fog", level and bool(d.get("fog", true)))
		m.set_shader_parameter("receive_shadow", receive)
		if d.has("clearcoat"):
			m.set_shader_parameter("clearcoat", float(d.clearcoat))
			m.set_shader_parameter("clearcoat_roughness", float(d.get("clearcoatRoughness", 0.0)))
		if float(d.get("sheen", 0.0)) > 0.0:
			m.set_shader_parameter("sheen_color", v3(d.get("sheenColor")) * float(d.sheen))
			m.set_shader_parameter("sheen_roughness", float(d.get("sheenRoughness", 1.0)))
		if float(d.get("iridescence", 0.0)) > 0.0:
			m.set_shader_parameter("iridescence", float(d.iridescence))
			m.set_shader_parameter("iridescence_ior", float(d.get("iridescenceIOR", 1.3)))
			var rng: Array = d.get("iridescenceThicknessRange", [100, 400])
			m.set_shader_parameter("iridescence_thickness", float(rng[1]))
	elif t == "MeshBasicMaterial":
		var key := String(d.get("key", ""))
		var name := "basic"
		if key == "opus::pglow":
			name = "glow"
		elif int(d.get("depthFunc", 3)) == GREATER_DEPTH:
			name = "xray"
		elif bool(d.get("polygonOffset", false)):
			name = "blob"
		elif bool(d.transparent) and int(d.blending) == ADDITIVE_BLENDING:
			name = "basic_add_ds" if int(d.side) == DOUBLE_SIDE else "basic_add"
		elif bool(d.transparent):
			name = "basic_alpha"
		elif int(d.side) == DOUBLE_SIDE:
			name = "basic_ds"
		m = unlit(name)
		m.set_shader_parameter("color", v3(d.get("color", [1, 1, 1])))
		m.set_shader_parameter("opacity", float(d.get("opacity", 1.0)))
		m.set_shader_parameter("use_fog", level and bool(d.get("fog", true)))
		m.set_shader_parameter("use_vcolor", bool(d.get("vertexColors", false)))
		if d.has("map"):
			var info: Dictionary = texs.call(String(d.map))
			if bool(info.srgb):
				m.set_shader_parameter("map_srgb", info.tex)
				m.set_shader_parameter("srgb", true)
			else:
				m.set_shader_parameter("map_lin", info.tex)
	else:
		m = shader_material(d, texs)
	if m != null:
		m.render_priority = clampi(priority, -128, 127)
	return m


## The web build's own ShaderMaterials.
func shader_material(d: Dictionary, texs: Callable) -> ShaderMaterial:
	var u: Dictionary = d.get("uniforms", {})
	var m: ShaderMaterial
	match String(d.get("shader", "")):
		"flat":
			m = unlit("bg_flat")
			m.set_shader_parameter("mist", uv3(u, "uMist"))
			m.set_shader_parameter("mist_top", float(u.uMistTop))
			m.set_shader_parameter("mist_bottom", float(u.uMistBottom))
			m.set_shader_parameter("mist_rise", float(u.uMistRise))
			m.set_shader_parameter("sun_dir", uv3(u, "uSunDir"))
			m.set_shader_parameter("sun_glow", uv3(u, "uSunGlow"))
		"cloud":
			m = unlit("bg_cloud")
			m.set_shader_parameter("tex", clouds)
			m.set_shader_parameter("lit", uv3(u, "uLit"))
			m.set_shader_parameter("shade", uv3(u, "uShade"))
			m.set_shader_parameter("opacity", float(u.uOpacity))
		"bank":
			m = unlit("bg_bank")
			m.set_shader_parameter("tex", clouds)
			m.set_shader_parameter("color", uv3(u, "uColor"))
			m.set_shader_parameter("lit", uv3(u, "uLit"))
			m.set_shader_parameter("opacity", float(u.uOpacity))
		"star":
			m = unlit("bg_star")
			m.set_shader_parameter("color", uv3(u, "uColor"))
		"water":
			m = unlit("bg_water")
			for k in ["deep", "sky", "horizon", "sun_dir", "sun_color", "fog"]:
				m.set_shader_parameter(k, uv3(u, "u" + _camel(k)))
			m.set_shader_parameter("fog_dist", float(u.uFogDist))
		"shaft":
			m = unlit("bg_shaft")
			m.set_shader_parameter("color", uv3(u, "uColor"))
			m.set_shader_parameter("seed", float(u.uSeed))
		"veil":
			m = unlit("veil")
			m.set_shader_parameter("color", uv3(u, "uColor"))
			m.set_shader_parameter("glow", float(u.uGlow))
		"ghost":
			m = unlit("ghost")
			m.set_shader_parameter("color", uv3(u, "uColor"))
			m.set_shader_parameter("opacity", float(u.uOpacity))
		_:
			return null
	return m


static func uv3(u: Dictionary, k: String) -> Vector3:
	var v: Variant = u.get(k)
	if v == null:
		return Vector3.ZERO
	if v.has("c"):
		return v3(v.c)
	if v.has("v3"):
		return v3(v.v3)
	return Vector3.ZERO


static func _camel(s: String) -> String:
	var parts := s.split("_")
	var out := ""
	for p in parts:
		out += p.capitalize().replace(" ", "")
	return out

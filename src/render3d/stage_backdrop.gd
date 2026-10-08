class_name StageBackdrop
extends RefCounted
## Everything behind the level, drawn first with its own camera into its own viewport: the
## sky dome (here Godot's sky, running the web build's SKY_FRAG), clouds, stars, the sun,
## moon, clock face or hall windows, layered silhouettes, mist banks, water and light
## shafts. A port of the web Stage's backdrop.ts; the geometry is baked.

var water_y := -999.0
var _follow: Node3D
var _water: Node3D
var _spinners: Array = []
var _shafts: Array = []
var _hands: Array = []
var _time_mats: Array = []
var _sky_mat: ShaderMaterial
var _star_mats: Array = []


## Builds the backdrop under `parent` (the backdrop viewport's world) and sets the sky on `env`.
func build(bake: StageBake, parent: Node, env: Environment, factory: StageMaterials) -> void:
	var root := bake.build(int(bake.data.roots.backdrop), parent, false)
	root.name = "Backdrop"
	var s: Dictionary = bake.module("backdrop")
	water_y = float(s.waterY)
	_follow = s.follow
	_water = s.water
	_spinners = s.spinners
	_shafts = s.shafts
	_hands = s.hands
	_time_mats.clear()
	_star_mats.clear()
	for k in ["cloudMat", "starMat", "waterMat", "bankMat"]:
		_time_mats.append_array(bake.mats_of(s[k]))
	_star_mats = bake.mats_of(s.starMat)
	for sh in _shafts:
		var mi := sh as GeometryInstance3D
		if mi.material_override:
			_time_mats.append(mi.material_override)
	# The sky dome: the web build's sky material on Godot's sky.
	var sky_def: Dictionary = bake.data.mats[int(s.skyMat.mat)]
	var u: Dictionary = sky_def.uniforms
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = factory.shader("bg_sky")
	_sky_mat.set_shader_parameter("top", StageMaterials.uv3(u, "uTop"))
	_sky_mat.set_shader_parameter("mid", StageMaterials.uv3(u, "uMid"))
	_sky_mat.set_shader_parameter("horizon", StageMaterials.uv3(u, "uHorizon"))
	_sky_mat.set_shader_parameter("bottom", StageMaterials.uv3(u, "uBottom"))
	_sky_mat.set_shader_parameter("sun_dir", StageMaterials.uv3(u, "uSunDir"))
	_sky_mat.set_shader_parameter("sun_color", StageMaterials.uv3(u, "uSunColor"))
	_sky_mat.set_shader_parameter("sun_size", float(u.uSunSize))
	_sky_mat.set_shader_parameter("disc", float(u.uDisc))
	_sky_mat.set_shader_parameter("glow", float(u.uGlow))
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky


## Star point sizes are in backdrop pixels; keep them the web build's size at its resolution.
func set_point_scale(k: float) -> void:
	for m in _star_mats:
		m.set_shader_parameter("point_scale", k)


func update(cam: Camera3D, time: float) -> void:
	_follow.position = cam.global_position
	for m in _time_mats:
		m.set_shader_parameter("time", time)
	if _water.visible:
		_water.position.x = cam.global_position.x
		_water.position.z = cam.global_position.z
	for sp in _spinners:
		(sp.mesh as Node3D).rotation.z = time * float(sp.speed)
	if _hands.size() == 2:
		(_hands[0] as Node3D).rotation.z = -time * 0.02
		(_hands[1] as Node3D).rotation.z = -time * 0.24

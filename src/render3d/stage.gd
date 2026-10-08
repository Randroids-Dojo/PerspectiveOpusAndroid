extends Node3D
## The Stage: the lit 3D world, a theatrical diorama. A port of the web build's
## src/render3d/stage.ts, drawing the scene that tools/bake_stage.ts baked from it.
##
## Two cameras share one frame, as in the web build: the backdrop (sky, silhouettes,
## water) renders with a normal lens into a smaller viewport, then the level renders with
## the shared stage camera from View.stage_pose over that backdrop. At swing 0 the stage
## camera is almost orthographic and lines up with the page exactly. Both viewports are
## linear HDR; a bloom chain of small viewports and one composite pass (ACES, grade,
## vignette, grain) put the result on a canvas layer under the page.
##
## Viewports are nested so that each renders after the ones it reads (Godot draws child
## viewports first): bloom up 0 > up 1 > ... > down 0 > scene > backdrop.

const TAN_MAX := 0.36397023426620234 # tan(20 degrees)
const MAX_LEVELS := 5
const BUDGET := {"high": 1.6e6, "medium": 1.0e6, "low": 0.8e6}

var _globals := StageGlobals.new()
var _mats: StageMaterials
var _bake: StageBake
var _lv: Level
var _palette := {}
var _look := {}
var _applied := ""
var _quality := "medium"
var _view: View
var _phys := Vector2i(1688, 780)
var _res_scale := 1.0
var _dts: Array[float] = []
var _calm := 0
var _clock := 0.0
var _visible := true

var _layer := CanvasLayer.new()
var _composite := ColorRect.new()
var _comp_mat := ShaderMaterial.new()
var _down: Array[SubViewport] = []
var _down_mats: Array[ShaderMaterial] = []
var _up: Array[SubViewport] = []
var _up_mats: Array[ShaderMaterial] = []
var _levels := 4
var _first_div := 4
var _vp := SubViewport.new()
var _bg_vp := SubViewport.new()
var _env := Environment.new()
var _bg_env := Environment.new()
var _scene_sky := ShaderMaterial.new()
var _camera := Camera3D.new()
var _bg_camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _spot := SpotLight3D.new()
var _sun_dir := Vector3(0, 1, 0)
var _sim: Node3D
var _bg_root: Node3D

var _backdrop := StageBackdrop.new()
var _quaver := StageQuaver.new()
var _entities := StageEntities.new()
var _props := StageProps.new()
var _effects: StageEffects


func _ready() -> void:
	_mats = StageMaterials.new(_globals)
	_build_pipeline()


func _build_pipeline() -> void:
	# The composite sits under the page (layer 1) and the UI.
	_layer.layer = -1
	add_child(_layer)
	_composite.set_anchors_preset(Control.PRESET_FULL_RECT)
	_composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comp_mat.shader = _mats.shader("post_composite")
	_composite.material = _comp_mat
	_layer.add_child(_composite)

	var outer: Node = self
	for i in MAX_LEVELS - 1:
		var up := _pass_viewport("post_up")
		_up.append(up)
		_up_mats.append(up.get_child(0).material)
	# Up 0 outermost, then up 1 ... up (MAX - 2), then down (MAX - 1) ... down 0.
	for up in _up:
		outer.add_child(up)
		outer = up
	for i in MAX_LEVELS:
		var down := _pass_viewport("post_prefilter" if i == 0 else "post_down")
		_down.append(down)
		_down_mats.append(down.get_child(0).material)
	for i in range(MAX_LEVELS - 1, -1, -1):
		outer.add_child(_down[i])
		outer = _down[i]

	_vp.name = "StageScene"
	_vp.own_world_3d = true
	_vp.use_hdr_2d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.positional_shadow_atlas_size = 0
	outer.add_child(_vp)
	_bg_vp.name = "StageBackdrop"
	_bg_vp.own_world_3d = true
	_bg_vp.use_hdr_2d = true
	_bg_vp.transparent_bg = false
	_bg_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bg_vp.positional_shadow_atlas_size = 0
	_vp.add_child(_bg_vp)

	# Godot adds nothing of its own: no ambient, reflections, fog, glow or tone mapping.
	for e in [_env, _bg_env]:
		e.background_mode = Environment.BG_SKY
		e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		e.tonemap_exposure = 1.0
		e.glow_enabled = false
		e.fog_enabled = false
	_scene_sky.shader = _mats.shader("scene_bg")
	_scene_sky.set_shader_parameter("bg", _bg_vp.get_texture())
	var sky := Sky.new()
	sky.sky_material = _scene_sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = _env
	_vp.add_child(we)
	var bwe := WorldEnvironment.new()
	bwe.environment = _bg_env
	_bg_vp.add_child(bwe)

	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	# The side view's lens is a quarter of a degree, below Camera3D's 1 degree minimum, so
	# the stage camera is a frustum: the same symmetric perspective, sized at the near plane.
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_vp.add_child(_camera)
	_camera.current = true
	_bg_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_bg_camera.fov = 40.0
	_bg_camera.near = 0.5
	_bg_camera.far = 6000.0
	_bg_vp.add_child(_bg_camera)
	_bg_camera.current = true

	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_blend_splits = false
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.0
	_sun.shadow_blur = 1.0
	_vp.add_child(_sun)
	_spot.shadow_enabled = false
	_spot.spot_range = 200.0
	_spot.spot_attenuation = 0.0
	_spot.spot_angle = 26.0
	_spot.light_energy = 1.0
	_vp.add_child(_spot)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	_comp_mat.set_shader_parameter("scene", _vp.get_texture())


func _pass_viewport(shader_name: String) -> SubViewport:
	var v := SubViewport.new()
	v.disable_3d = true
	v.use_hdr_2d = true
	v.transparent_bg = false
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = _mats.shader(shader_name)
	r.material = m
	v.add_child(r)
	return v


# ---------------------------------------------------------------- contract

func resize(view: View) -> void:
	_view = view
	_phys = Vector2i(maxi(1, roundi(view.w * view.dpr)), maxi(1, roundi(view.h * view.dpr)))
	_apply_size()


func load_level(game: Sim, palette: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	_lv = game.level
	var pal_id := String(palette.id)
	var lid := _lv.id
	if not StageBake.exists(lid, pal_id):
		push_warning("Stage: no bake for %s in %s; using its own palette" % [lid, pal_id])
		pal_id = String(_lv.info.palette)
	_palette = palette
	if _sim:
		_sim.queue_free()
		_sim = null
	if _bg_root:
		_bg_root.queue_free()
		_bg_root = null
	_mats.set_palette_env(pal_id)
	_bake = StageBake.open(lid, pal_id, _mats)
	_look = _bake.data.look

	# The mirrored world node with flora, thorns, props, decor and Quaver from the bake.
	_sim = _bake.build(int(_bake.data.roots.world), _vp, true)
	_sim.name = "World"
	var world_mat := WorldMesh.material(_mats, _bake.data.world)
	var chunks := Node3D.new()
	chunks.name = "Blocks"
	_sim.add_child(chunks)
	_sim.move_child(chunks, 0)
	for m in WorldMesh.build(_lv, String(palette.top)):
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = world_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		chunks.add_child(mi)
	_effects = StageEffects.new()
	_effects.name = "Effects"
	_sim.add_child(_effects)
	_effects.setup(_mats)
	_effects.load_palette(palette, _look)

	_bg_root = Node3D.new()
	_bg_root.name = "BackdropRoot"
	_bg_vp.add_child(_bg_root)
	_backdrop.build(_bake, _bg_root, _bg_env, _mats)
	_quaver.setup(_bake, _mats)
	_entities.setup(_bake, _lv)
	_props.setup(_bake)

	# Light rig.
	var L: Dictionary = _bake.data.lights
	_globals.set3(8, StageMaterials.v3(L.hemi.sky) * float(L.hemi.intensity))
	_globals.set3(9, StageMaterials.v3(L.hemi.ground) * float(L.hemi.intensity))
	var sc := StageMaterials.v3(L.sun.color)
	_sun.light_color = Color(sc.x, sc.y, sc.z).linear_to_srgb()
	_sun.light_energy = float(L.sun.intensity)
	_sun_dir = StageMaterials.v3(L.sun.dir).normalized()
	_sun.global_basis = Basis.looking_at(-_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.FORWARD)
	var spc := StageMaterials.v3(L.spot.color) * float(L.spot.intensity)
	var spot_angle := float(L.spot.angle)
	_globals.set3(12, spc, cos(spot_angle * (1.0 - float(L.spot.penumbra))))
	_globals.set_v(13, Vector4(float(L.spot.decay), 0, 0, 0))
	_spot_cos = cos(spot_angle)
	_globals.set3(6, StageMaterials.v3(L.fog))
	var sh: Dictionary = _bake.data.shared
	_globals.set3(2, StageMaterials.v3(sh.uHFog.v3), float(_backdrop.water_y))
	_globals.set3(3, StageMaterials.v3(sh.uHFogColor.c))
	_globals.set3(4, StageMaterials.v3(sh.uWaterColor.c))
	_env_intensity = float(L.envIntensity)

	_quaver.reset()
	_bake.bin = PackedByteArray()
	_applied = ""
	_load_ms = (Time.get_ticks_usec() - t0) / 1000.0


var _spot_cos := 0.9
var _env_intensity := 0.55
var _load_ms := 0.0


func set_world_visible(v: bool) -> void:
	if v == _visible:
		return
	_visible = v
	_layer.visible = v
	_update_modes()


func render(game: Sim, view: View, frame: Dictionary) -> void:
	if _bake == null:
		return
	_view = view
	_dev_args()
	_dev_frame()
	var q := String(_dev.get("stage-quality", frame.quality))
	_apply_quality(q)
	_adapt_resolution(frame)
	_clock += float(frame.game_dt)

	# The stage camera, exactly as the shared view describes it.
	var pose := view.stage_pose()
	var t := 1.0 if view.reduce_motion else view.swing
	var shake := view.shake * t * 0.12
	var sx := (randf() - 0.5) * shake if shake > 0.0 else 0.0
	var sy := (randf() - 0.5) * shake if shake > 0.0 else 0.0
	var pos: Vector3 = pose.position
	var tgt: Vector3 = pose.target
	var dist: float = pose.dist
	# Nothing in the level sits more than a few units in front of the focus; a tight near
	# plane keeps the shadow cascade (fitted from near to its max distance) on the level.
	var near := maxf(float(pose.near), dist - 25.0)
	var far: float = pose.far
	var tan_half := tan(deg_to_rad(float(pose.fov_deg)) / 2.0)
	_camera.set_frustum(2.0 * near * tan_half, Vector2.ZERO, near, far)
	_camera.position = Vector3(pos.x + sx, pos.y + sy, -pos.z)
	_camera.look_at(Vector3(tgt.x + sx, tgt.y + sy, -tgt.z))
	_globals.set_v(7, Vector4(dist + float(_look.fogStart), dist + float(_look.fogEnd), _env_intensity, 0))
	_sun.directional_shadow_max_distance = minf(dist + 20.0, float(pose.far))

	# The backdrop camera looks the same way but never narrower than a normal lens.
	var d_bg := dist * tan_half / TAN_MAX
	var dir := (pos - tgt).normalized()
	var focus := Vector3(tgt.x, tgt.y, -tgt.z)
	_bg_camera.position = Vector3(tgt.x + dir.x * d_bg, tgt.y + dir.y * d_bg, -(tgt.z + dir.z * d_bg))
	_bg_camera.look_at(focus)
	_backdrop.update(_bg_camera, _clock)

	# Animate the world.
	var halos := _effects.halos
	halos.begin()
	_quaver.update(game, frame, _sim)
	var feet := _quaver.feet
	_globals.set3(5, feet)
	_entities.update(game, frame, halos, feet, _clock)
	_props.update(_clock, halos)
	_effects.handle(frame.events, game, feet)
	_effects.update(float(frame.game_dt), game, tgt, _clock)
	halos.end()

	# Warm key on Quaver from above the audience.
	var spot_pos := Vector3(feet.x - 2.2, feet.y + 6.5, -(feet.z - 4.5))
	var spot_tgt := Vector3(feet.x, feet.y + 0.3, -feet.z)
	_spot.position = spot_pos
	if spot_pos.distance_to(spot_tgt) > 0.01:
		_spot.look_at(spot_tgt)
	_globals.set3(10, spot_pos, 1.0 if _spot.visible else 0.0)
	_globals.set3(11, (spot_tgt - spot_pos).normalized(), _spot_cos)

	_update_cutout(game, feet)
	_globals.set_v(0, Vector4(_clock, 1.0, _globals.get_v(0).z, _globals.get_v(0).w))
	_globals.flush()
	_comp_mat.set_shader_parameter("time", float(frame.now))


## Screen-space hole around Quaver for geometry between the camera and them.
func _update_cutout(game: Sim, f: Vector3) -> void:
	var c := Vector3(f.x, f.y + 0.45, -f.z)
	var up := Vector3(f.x, f.y + 1.45, -f.z)
	var depth := -(_camera.global_transform.affine_inverse() * c).z
	var pc := _camera.unproject_position(c)
	var pu := _camera.unproject_position(up)
	var radius := maxf(8.0, pc.distance_to(pu) * 1.25)
	_globals.set_v(0, Vector4(_clock, 1.0, 0.0 if game.player.dead > 0.0 else 1.0, radius))
	_globals.set_v(1, Vector4(pc.x, pc.y, depth, f.y))


# ---------------------------------------------------------------- quality and resolution

func _apply_quality(q: String) -> void:
	if q == _applied:
		return
	_applied = q
	_quality = q
	_sun.shadow_enabled = q != "low"
	RenderingServer.directional_shadow_atlas_set_size(4096 if q == "high" else 2048, true)
	_spot.visible = q == "high"
	_props.set_quality(q)
	_effects.set_quality(q)
	_levels = 5 if q == "high" else (4 if q == "medium" else 0)
	_first_div = 2 if q == "high" else 4
	_vp.msaa_3d = Viewport.MSAA_4X if q == "high" else Viewport.MSAA_2X
	var full := q != "low"
	_comp_mat.set_shader_parameter("full", full)
	_comp_mat.set_shader_parameter("has_bloom", full and _levels > 0)
	var look := _look
	if full:
		var gr: Dictionary = look.grade
		_comp_mat.set_shader_parameter("bloom", float(look.bloom) * (1.0 if q == "high" else 0.85))
		_comp_mat.set_shader_parameter("exposure", float(look.exposure))
		_comp_mat.set_shader_parameter("lift", StageMaterials.v3(gr.lift))
		_comp_mat.set_shader_parameter("gamma", StageMaterials.v3(gr.gamma))
		_comp_mat.set_shader_parameter("gain", StageMaterials.v3(gr.gain))
		_comp_mat.set_shader_parameter("sat", float(gr.sat))
		_comp_mat.set_shader_parameter("contrast", float(gr.contrast))
		_comp_mat.set_shader_parameter("vignette", float(look.vignette))
		_comp_mat.set_shader_parameter("grain", float(look.grain))
	else:
		_comp_mat.set_shader_parameter("exposure", float(look.exposure) * 1.05)
	_down_mats[0].set_shader_parameter("threshold", float(look.bloomThreshold))
	_scene_sky.set_shader_parameter("blur", full)
	_apply_size()


func _apply_size() -> void:
	var budget: float = BUDGET.get(_quality, 1.0e6)
	var area := float(_phys.x * _phys.y)
	var s := clampf(minf(1.0, sqrt(budget / maxf(1.0, area))) * _res_scale, 0.25, 1.0)
	var size := Vector2i(maxi(1, roundi(_phys.x * s)), maxi(1, roundi(_phys.y * s)))
	_vp.size = size
	var full := _quality != "low"
	# The web build renders the backdrop at half resolution and softens it in; at low it
	# draws it straight into the frame.
	var bg := Vector2i(maxi(1, roundi(size.x / 2.0)), maxi(1, roundi(size.y / 2.0))) if full else size
	_bg_vp.size = bg
	_scene_sky.set_shader_parameter("texel", Vector2(1.0 / bg.x, 1.0 / bg.y))
	_backdrop.set_point_scale(1.0)
	_comp_mat.set_shader_parameter("res", Vector2(size))
	# Bloom levels: first at size / first_div, then halving.
	var mw := maxi(1, roundi(float(size.x) / _first_div))
	var mh := maxi(1, roundi(float(size.y) / _first_div))
	for i in MAX_LEVELS:
		_down[i].size = Vector2i(mw, mh)
		if i < MAX_LEVELS - 1:
			_up[i].size = Vector2i(mw, mh)
		mw = maxi(1, roundi(mw / 2.0))
		mh = maxi(1, roundi(mh / 2.0))
	_wire_bloom(size)
	_update_modes()


func _wire_bloom(size: Vector2i) -> void:
	if _levels <= 0:
		return
	_down_mats[0].set_shader_parameter("src", _vp.get_texture())
	_down_mats[0].set_shader_parameter("texel", Vector2(1.0 / size.x, 1.0 / size.y))
	for i in range(1, _levels):
		var src := _down[i - 1]
		_down_mats[i].set_shader_parameter("src", src.get_texture())
		_down_mats[i].set_shader_parameter("texel", Vector2(1.0 / src.size.x, 1.0 / src.size.y))
	# up[k] = down[k] + tent(up[k + 1]) (the last level's up is its down).
	for k in range(_levels - 2, -1, -1):
		var src_vp: SubViewport = _down[k + 1] if k == _levels - 2 else _up[k + 1]
		_up_mats[k].set_shader_parameter("src", src_vp.get_texture())
		_up_mats[k].set_shader_parameter("base", _down[k].get_texture())
		_up_mats[k].set_shader_parameter("texel", Vector2(0.5 / src_vp.size.x, 0.5 / src_vp.size.y))
		_up_mats[k].set_shader_parameter("weight", 1.0)
	var final_vp: SubViewport = _up[0] if _levels > 1 else _down[0]
	_comp_mat.set_shader_parameter("bloom_tex", final_vp.get_texture())


func _update_modes() -> void:
	var on := SubViewport.UPDATE_ALWAYS if _visible else SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = on
	_bg_vp.render_target_update_mode = on
	for i in MAX_LEVELS:
		_down[i].render_target_update_mode = on if i < _levels else SubViewport.UPDATE_DISABLED
		if i < MAX_LEVELS - 1:
			_up[i].render_target_update_mode = on if i < _levels - 1 else SubViewport.UPDATE_DISABLED


## If frames stay slow, lower the resolution in steps; raise it again once there is headroom.
func _adapt_resolution(frame: Dictionary) -> void:
	var dt: float = frame.dt
	if bool(frame.paused) or dt <= 0.0 or dt > 0.25:
		return
	_dts.append(dt)
	if _dts.size() < 90:
		return
	var sorted := _dts.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2]
	_dts.clear()
	var next := _res_scale
	if med > 1.0 / 48.0:
		next = maxf(0.6, _res_scale - 0.1)
		_calm = 0
	elif med < 1.0 / 58.0 and _res_scale < 1.0:
		_calm += 1
		if _calm >= 3:
			next = minf(1.0, _res_scale + 0.05)
			_calm = 0
	if next != _res_scale:
		_res_scale = next
		_apply_size()


## Development: --stage-dump=path.exr saves the linear scene and backdrop viewports at
## --frames (for checking values against the web build), --stage-quality forces a tier.
var _dev := {}
var _dev_frames := 0


func _dev_args() -> void:
	if not _dev.is_empty():
		return
	_dev["_"] = true
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0].begins_with("stage-") or kv[0] == "frames":
			_dev[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _dev_frame() -> void:
	_dev_frames += 1
	if _dev.has("stage-perf"):
		_perf_frame()
	if _dev.has("stage-dump") and _dev_frames == int(_dev.get("frames", "90")) - 1:
		var path := String(_dev["stage-dump"])
		_vp.get_texture().get_image().save_exr(path)
		_bg_vp.get_texture().get_image().save_exr(path.replace(".exr", "_bg.exr"))
		print("STAGE DUMP ", path)


## --stage-perf logs frame times and the stage viewports' GPU times every two seconds.
var _perf_dts: Array[float] = []
var _perf_last := 0


func _perf_frame() -> void:
	if _perf_last == 0:
		_perf_last = Time.get_ticks_usec()
		for v in [_vp, _bg_vp]:
			RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
		return
	var now := Time.get_ticks_usec()
	_perf_dts.append((now - _perf_last) / 1000.0)
	_perf_last = now
	if _perf_dts.size() < 120:
		return
	var sorted := _perf_dts.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for d in sorted:
		total += d
	var gpu := func(v: Viewport) -> float: return RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
	print("STAGE PERF fps %.1f  frame p50 %.2f ms p95 %.2f ms  gpu scene %.2f ms backdrop %.2f ms root %.2f ms  scale %.2f  scene %dx%d  %s  draws %d" % [
		1000.0 * n / total, sorted[n / 2], sorted[int(n * 0.95)], gpu.call(_vp), gpu.call(_bg_vp), gpu.call(get_tree().root),
		_res_scale, _vp.size.x, _vp.size.y, _quality, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_perf_dts.clear()


## For the profiling overlay and tests.
func stats() -> Dictionary:
	return {"scale": _res_scale, "size": _vp.size, "quality": _quality, "load_ms": _load_ms}

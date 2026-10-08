class_name View
extends RefCounted
## The shared camera, a port of the web build's src/game/view.ts. Both renderers draw
## from this one state, which is what makes the switch seamless: at swing = 0 the stage
## camera looks straight down the depth axis with an almost orthographic lens, centred
## on the page camera at the page's scale, so the two pictures line up exactly while
## the ink wipe runs.
##
## blend: 0 = page, 1 = stage.
##   0 .. WIPE_END   the ink wipe: the page opens from the player outwards
##   WIPE_END .. 1   the swing: the stage camera turns from side view to three-quarter view

const WIPE_END := 0.4
const TRANSITION_SECONDS := 0.78
const REDUCED_TRANSITION_SECONDS := 0.32

const STAGE_YAW := -0.4
const STAGE_PITCH := 0.34
const STAGE_FOV_DEG := 40.0
const STAGE_MIN_FOV_DEG := 0.25
const STAGE_ZOOM := 0.86

## Screen size in UI pixels (the canvas_items stretch space).
var w := 844.0
var h := 390.0
## Physical pixels per UI pixel.
var dpr := 1.0
## UI pixels per world unit on the page.
var ppu := 30.0
## Page camera centre in world units.
var c2 := Vector2.ZERO
## Free stage camera focus (x, y, z in simulation space, z away from the viewer).
var f3 := Vector3.ZERO
var blend := 1.0
var swing := 1.0
var wipe := 1.0
## Where the wipe is centred, in UI pixels.
var wipe_origin := Vector2.ZERO
var time_scale := 1.0
var heading := "to3d"
var since_switch := 9.0
var shake := 0.0
var reduce_motion := false
## Cutscene offsets for the stage camera: yaw, pitch, extra distance.
var orbit := Vector3.ZERO
## When set (has_focus), both cameras frame `focus` instead of following the player.
var has_focus := false
var focus := Vector3.ZERO


static func pixels_per_unit(sw: float, sh: float) -> float:
	if sh > sw:
		return minf(sw / 11.0, sh / 18.0)
	return minf(sh / 12.5, sw / 16.0)


func resize(sw: float, sh: float, pixel_ratio: float) -> void:
	w = sw
	h = sh
	dpr = pixel_ratio
	ppu = pixels_per_unit(sw, sh)


func _page_target(game: Sim) -> Vector2:
	if has_focus:
		return Vector2(focus.x, focus.y)
	var pl := game.player
	var lv := game.level
	var half_w := w / ppu / 2.0
	var half_h := h / ppu / 2.0
	var x := pl.pos.x + pl.facing * 1.4
	var y := pl.pos.y + 1.6
	var min_x := half_w - 1.0
	var max_x := lv.w - half_w + 1.0
	x = lv.w / 2.0 if min_x > max_x else clampf(x, min_x, max_x)
	y = maxf(y, half_h - 2.2)
	return Vector2(x, y)


func _stage_target(game: Sim) -> Vector3:
	if has_focus:
		return focus
	var pl := game.player
	return Vector3(pl.pos.x + pl.facing * 1.1, pl.pos.y + 1.3, pl.pos.z)


func snap(game: Sim) -> void:
	c2 = _page_target(game)
	f3 = _stage_target(game)
	blend = 1.0 if game.mode == "3d" else 0.0
	_split_blend()


func _split_blend() -> void:
	if reduce_motion:
		swing = 1.0
		wipe = blend
		return
	wipe = clampf(blend / WIPE_END, 0.0, 1.0)
	swing = clampf((blend - WIPE_END) / (1.0 - WIPE_END), 0.0, 1.0)


static func _damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


static func _smoothstep(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func ease_in_out(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 4.0 * c * c * c if c < 0.5 else 1.0 - pow(-2.0 * c + 2.0, 3.0) / 2.0


## Advances the cameras and the switch timeline by real (unscaled) time.
func update(game: Sim, real_dt: float) -> void:
	var target := 1.0 if game.mode == "3d" else 0.0
	var dur := REDUCED_TRANSITION_SECONDS if reduce_motion else TRANSITION_SECONDS
	var prev_heading := heading
	heading = "to3d" if target == 1.0 else "to2d"
	if prev_heading != heading:
		since_switch = 0.0
	since_switch += real_dt
	blend = clampf(blend + signf(target - blend) * (real_dt / dur), 0.0, 1.0)
	_split_blend()

	var p := blend if target == 1.0 else 1.0 - blend
	var moving := blend != target
	var win := _smoothstep(minf(p, 1.0 - p) / 0.14) if moving else 0.0
	time_scale = 1.0 if reduce_motion else 1.0 - 0.66 * win

	if game.player.dead <= 0:
		var t2 := _page_target(game)
		var v_rate := 5.0 if game.player.grounded else 2.6
		c2.x = _damp(c2.x, t2.x, 4.2, real_dt)
		c2.y = _damp(c2.y, t2.y, v_rate, real_dt)
		var half_h := h / ppu / 2.0
		var py := game.player.pos.y
		if not has_focus:
			if py < c2.y - half_h + 1.2:
				c2.y = py - 1.2 + half_h
			if py > c2.y + half_h - 2.4:
				c2.y = py + 2.4 - half_h
		var t3 := _stage_target(game)
		f3.x = _damp(f3.x, t3.x, 3.6, real_dt)
		f3.y = _damp(f3.y, t3.y, 4.0 if game.player.grounded else 2.2, real_dt)
		f3.z = _damp(f3.z, t3.z, 3.6, real_dt)

	wipe_origin = world_to_page(game.player.pos.x, game.player.pos.y + 0.45)
	shake = maxf(0.0, shake - real_dt * 2.5)


## Page projection: world units to UI pixels.
func world_to_page(x: float, y: float) -> Vector2:
	return Vector2((x - c2.x) * ppu + w / 2.0, h / 2.0 - (y - c2.y) * ppu)


## The stage camera for the current swing, in simulation space (z away from the viewer).
## Returns {position: Vector3, target: Vector3, fov_deg, near, far, dist}.
func stage_pose() -> Dictionary:
	var t := 1.0 if reduce_motion else ease_in_out(swing)
	var fo := Vector3(lerpf(c2.x, f3.x, t), lerpf(c2.y, f3.y, t), f3.z)
	var visible_h := (h / ppu) * lerpf(1.0, STAGE_ZOOM, t)
	var tan_min := tan(deg_to_rad(STAGE_MIN_FOV_DEG) / 2.0)
	var tan_max := tan(deg_to_rad(STAGE_FOV_DEG) / 2.0)
	var tan_half := lerpf(tan_min, tan_max, t)
	var fov_deg := rad_to_deg(2.0 * atan(tan_half))
	var dist := visible_h / 2.0 / tan_half + orbit.z * t
	var yaw := STAGE_YAW * t + orbit.x * t
	var pitch := STAGE_PITCH * t + orbit.y * t
	var position := Vector3(
		fo.x + sin(yaw) * cos(pitch) * dist,
		fo.y + sin(pitch) * dist,
		fo.z - cos(yaw) * cos(pitch) * dist
	)
	return {"position": position, "target": fo, "fov_deg": fov_deg, "near": maxf(0.1, dist - 80.0), "far": dist + 220.0, "dist": dist}


## Projects a world point through the stage camera to UI pixels.
func world_to_stage(x: float, y: float, z: float) -> Vector2:
	var pose := stage_pose()
	var p: Vector3 = pose.position
	var t: Vector3 = pose.target
	var f := (t - p).normalized()
	var r := Vector3(f.z, 0, -f.x).normalized()
	var u := f.cross(r)
	var dv := Vector3(x, y, z) - p
	var cx := dv.dot(r)
	var cy := dv.dot(u)
	var cz := dv.dot(f)
	var fl := h / 2.0 / tan(deg_to_rad(float(pose.fov_deg)) / 2.0)
	return Vector2(w / 2.0 + (cx / cz) * fl, h / 2.0 - (cy / cz) * fl)


## Screen position of a world point in whichever world is showing.
func world_to_screen(x: float, y: float, z: float) -> Vector2:
	if wipe < 1.0:
		return world_to_page(x, y)
	return world_to_stage(x, y, z)

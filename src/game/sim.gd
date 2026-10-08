class_name Sim
extends RefCounted
## The deterministic game simulation, a line-for-line port of the web build's
## src/game/sim.ts. It knows nothing about rendering. tests/parity.gd replays the web
## build's recorded solutions through it and checks the positions match.
##
## Two rule sets share one world. On the Stage (3d) the player moves in x and z and
## collides with real voxels. On the Score (2d) depth collapses: a column is solid if
## any voxel in it is, so things that line up on the page connect; the player keeps a
## depth and moves to whatever they stand on. Switching while behind scenery leaves
## the player "embedded": 3D collision at their own depth until they step clear.

const HW := 0.3
const PH := 0.86
const HD := 0.3

const GRAVITY := 40.0
const FALL_MUL := 1.28
const APEX_MUL := 0.62
const APEX_BAND := 2.4
const JUMP_V := 14.7
const JUMP_CUT := 0.5
const MAX_FALL := 21.0
const RUN := 6.1
const ACCEL_GROUND := 62.0
const ACCEL_AIR := 38.0
const DECEL_GROUND := 75.0
const COYOTE := 0.1
const BUFFER := 0.13
const KILL_Y := -5.0
const STEP_EVERY := 0.66
const DEATH_TIME := 0.95

const EPS := 1e-4
const DT_MAX := 1.0 / 60.0
const BIG := 1e4

## Collision geometries.
const GEO_3D := 0
const GEO_PROJ := 1

## Body kinds. Support kinds use KIND_WORLD for voxels and walls.
const KIND_WORLD := 0
const KIND_PLATFORM := 1
const KIND_GATE := 2
const KIND_DRUM := 3


class Body:
	var kind: int
	var id: int
	var min: V3
	var max: V3
	var delta := V3.new()
	var vel := V3.new()
	var solid := true


class PlatformState:
	var clock: float
	var body: Body


class DiscordState:
	var pos: V3
	var prev: V3
	var dir := V3.new(1, 0, 0)


class Player:
	var pos: V3
	var prev: V3
	var vel := V3.new()
	var facing := 1.0
	var heading := 0.0
	var grounded := false
	var coyote := 0.0
	var buffer := 0.0
	var jump_cut := false
	var since_jump := 9.0
	var since_land := 9.0
	var last_impact := 0.0
	## Support: kind (-1 when none) and id.
	var support_kind := -1
	var support_id := 0
	var support_mat := Level.MAT_STONE
	var embedded := false
	var dead := 0.0
	var step_acc := 0.0
	var walk := 0.0
	var carry := V3.new()


var level: Level
var mode := "3d"
var time := 0.0
var player: Player
var bodies: Array[Body] = []
var platforms: Array[PlatformState] = []
var gate_bodies: Array[Body] = []
var drum_bodies: Array[Body] = []
var discords: Array[DiscordState] = []
var groups: Array[bool] = []
var gate_vis: Array[float] = []
var drum_hit: Array[float] = []
var key_vis: Array[float] = []
var key_down: Array[bool] = []
var notes_taken: Array[bool] = []
var note_taken_at: Array[float] = []
var checkpoint_on := -1
var checkpoint_at: Array[float] = []
var respawn_pos: V3
var respawn_groups: Array[bool] = []
var deaths := 0
var switches := 0
var finished := false
var finished_at := 0.0
var active_sign = null
var events: Array = []
var play_time := 0.0

## Scratch buffer for solid boxes: 9 floats each (x0 y0 z0 x1 y1 z1 kind id mat).
var _boxes := PackedFloat64Array()
var _nbox := 0


func _init(lv: Level, start_mode: String = "3d") -> void:
	level = lv
	mode = start_mode
	var s := lv.spawn
	player = Player.new()
	player.pos = s.copy()
	player.prev = s.copy()
	var max_group := 0
	for k in lv.keys:
		max_group = maxi(max_group, k.group)
	for g in lv.gates:
		max_group = maxi(max_group, g.group)
	for p in lv.platforms:
		max_group = maxi(max_group, maxi(p.group, 0))
	for i in max_group + 1:
		groups.append(lv.groups_on.has(i))
	for p in lv.platforms:
		var body := Body.new()
		body.kind = KIND_PLATFORM
		body.id = p.id
		var p0: V3 = p.path[0]
		body.min = p0.copy()
		body.max = V3.new(p0.x + p.size.x, p0.y + p.size.y, p0.z + p.size.z)
		var st := PlatformState.new()
		st.clock = p.phase
		st.body = body
		platforms.append(st)
		bodies.append(body)
		_place_platform(st)
		body.delta = V3.new()
	for g in lv.gates:
		var solid: bool = groups[g.group] == g.solidWhenOn
		var gb := Body.new()
		gb.kind = KIND_GATE
		gb.id = g.id
		gb.min = g.min.copy()
		gb.max = g.max.copy()
		gb.solid = solid
		gate_bodies.append(gb)
		bodies.append(gb)
		gate_vis.append(1.0 if solid else 0.0)
	for dr in lv.drums:
		var db := Body.new()
		db.kind = KIND_DRUM
		db.id = dr.id
		db.min = V3.new(dr.pos.x + 0.06, dr.pos.y, dr.pos.z + 0.06)
		db.max = V3.new(dr.pos.x + 0.94, dr.pos.y + 0.72, dr.pos.z + 0.94)
		drum_bodies.append(db)
		bodies.append(db)
		drum_hit.append(9.0)
	for i in lv.keys.size():
		key_vis.append(0.0)
		key_down.append(false)
	for dd in lv.discords:
		var ds := DiscordState.new()
		var q: V3 = dd.path[0]
		ds.pos = q.copy()
		ds.prev = q.copy()
		discords.append(ds)
	_update_discords(0.0)
	for ds in discords:
		ds.prev = ds.pos.copy()
	for n in lv.notes:
		notes_taken.append(false)
		note_taken_at.append(-1.0)
	for c in lv.checkpoints:
		checkpoint_at.append(-1.0)
	respawn_pos = s.copy()
	respawn_groups = groups.duplicate()
	_settle()


func notes_count() -> int:
	var n := 0
	for t in notes_taken:
		if t:
			n += 1
	return n


func _settle() -> void:
	var i := 0
	while i < 240 and not player.grounded:
		_physics(1.0 / 120.0, 0.0, 0.0, false, false)
		i += 1
	player.prev = player.pos.copy()
	player.since_land = 9.0
	events.clear()


## Switches the rules between the page and the stage. Never moves the player.
func toggle_mode() -> void:
	if player.dead > 0 or finished:
		return
	mode = "2d" if mode == "3d" else "3d"
	switches += 1
	player.vel.z = 0.0
	if mode == "2d":
		player.embedded = _overlaps_any(GEO_PROJ, player.pos, null)
	else:
		player.embedded = false
	events.append({"t": "switch", "mode": mode, "embedded": player.embedded})


func step(dt: float, move_x: float, move_z: float, jump_held: bool, jump_pressed: bool, switch_pressed: bool) -> void:
	dt = minf(dt, DT_MAX)
	time += dt
	if not finished:
		play_time += dt
	var pl := player
	pl.prev = pl.pos.copy()
	for d in discords:
		d.prev = d.pos.copy()
	if switch_pressed:
		toggle_mode()
	_update_groups_visuals(dt)
	_update_platforms(dt)
	_update_discords(dt)
	for i in drum_hit.size():
		drum_hit[i] += dt
	if pl.dead > 0:
		pl.dead -= dt
		if pl.dead <= 0:
			_do_respawn()
		return
	if finished:
		var ex := level.exit_pos
		pl.vel.x = clampf((ex.x - pl.pos.x) * 4.0, -2.0, 2.0)
		pl.vel.z = clampf((ex.z - pl.pos.z) * 4.0, -2.0, 2.0)
		pl.pos.x += pl.vel.x * dt
		pl.pos.z += pl.vel.z * dt
		if absf(pl.vel.x) > 0.05:
			pl.facing = signf(pl.vel.x)
		pl.walk += _hypot2(pl.vel.x, pl.vel.z) * dt
		return
	_carry_and_push()
	_physics(dt, move_x, move_z, jump_held, jump_pressed)
	_interact()


# ------------------------------------------------------------------ moving things

func _update_groups_visuals(dt: float) -> void:
	var pl := player
	for i in gate_bodies.size():
		var g: Dictionary = level.gates[i]
		var body := gate_bodies[i]
		var want: bool = groups[g.group] == g.solidWhenOn
		if want and not body.solid:
			if not _overlap3(pl.pos, body):
				body.solid = true
		elif not want and body.solid:
			body.solid = false
		var target := 1.0 if body.solid else (0.35 if want else 0.0)
		gate_vis[i] += clampf(target - gate_vis[i], -dt * 5.0, dt * 5.0)
	for i in key_vis.size():
		var t := 1.0 if key_down[i] else 0.0
		key_vis[i] += clampf(t - key_vis[i], -dt * 9.0, dt * 14.0)


func _place_platform(st: PlatformState) -> void:
	var def: Dictionary = level.platforms[st.body.id]
	var p := path_position(def.path, def.speed, def.pause, def.loop, st.clock)
	var b := st.body
	b.delta = V3.new(p.x - b.min.x, p.y - b.min.y, p.z - b.min.z)
	b.min = V3.new(p.x, p.y, p.z)
	b.max = V3.new(p.x + def.size.x, p.y + def.size.y, p.z + def.size.z)


func _update_platforms(dt: float) -> void:
	for st in platforms:
		var def: Dictionary = level.platforms[st.body.id]
		var active: bool = def.group < 0 or groups[def.group]
		if active:
			st.clock += dt
		_place_platform(st)
		var b := st.body
		b.vel = V3.new(b.delta.x / dt, b.delta.y / dt, b.delta.z / dt) if dt > 0 else V3.new()


func _update_discords(_dt: float) -> void:
	for i in discords.size():
		var def: Dictionary = level.discords[i]
		var d := discords[i]
		var p := path_position(def.path, def.speed, 0.35, false, time + def.phase)
		var dx := p.x - d.pos.x
		var dz := p.z - d.pos.z
		if absf(dx) + absf(dz) > 1e-6:
			d.dir = V3.new(signf(dx), 0, signf(dz))
		d.pos = p


func _carry_and_push() -> void:
	var pl := player
	if pl.support_kind == KIND_PLATFORM:
		var b := platforms[pl.support_id].body
		var d := b.delta
		if d.x != 0 or d.y != 0 or d.z != 0:
			var geo := _geo()
			if d.y > 0:
				_move_axis(geo, 1, d.y, b, null)
			_move_axis(geo, 0, d.x, b, null)
			if mode == "3d" or pl.embedded:
				_move_axis(geo, 2, d.z, b, null)
			else:
				pl.pos.z += d.z
			if d.y < 0:
				_move_axis(geo, 1, d.y, b, null)
	for st in platforms:
		var b := st.body
		if pl.support_kind == KIND_PLATFORM and pl.support_id == b.id:
			continue
		if not _overlap3(pl.pos, b):
			continue
		var geo := _geo()
		if b.delta.x != 0:
			_move_axis(geo, 0, b.delta.x, b, null)
		if b.delta.z != 0 and (mode == "3d" or pl.embedded):
			_move_axis(geo, 2, b.delta.z, b, null)
		if b.delta.y > 0 and pl.pos.y > b.min.y:
			pl.pos.y = b.max.y
			pl.vel.y = maxf(pl.vel.y, 0.0)


# ------------------------------------------------------------------ player physics

func _geo() -> int:
	if mode == "3d":
		return GEO_3D
	return GEO_3D if player.embedded else GEO_PROJ


func _physics(dt: float, move_x: float, move_z: float, jump_held: bool, jump_pressed: bool) -> void:
	var pl := player
	if mode == "2d":
		pl.embedded = _overlaps_any(GEO_PROJ, pl.pos, null)
	var geo := _geo()

	var mx := clampf(move_x, -1.0, 1.0)
	var mz := clampf(move_z, -1.0, 1.0) if mode == "3d" else 0.0
	var mag := _hypot2(mx, mz)
	if mag > 1:
		mx /= mag
		mz /= mag
	var tx := mx * RUN
	var tz := mz * RUN
	var accel := (ACCEL_GROUND if mag > 0.05 else DECEL_GROUND) if pl.grounded else ACCEL_AIR
	pl.vel.x = _approach(pl.vel.x, tx, accel * dt)
	pl.vel.z = _approach(pl.vel.z, tz, accel * dt) if mode == "3d" else 0.0
	if absf(mx) > 0.2:
		pl.facing = signf(mx)
	if mode == "3d" and _hypot2(pl.vel.x, pl.vel.z) > 0.4:
		pl.heading = atan2(pl.vel.z, pl.vel.x)
	elif mode == "2d":
		pl.heading = 0.0 if pl.facing > 0 else PI

	pl.since_jump += dt
	pl.since_land += dt
	if jump_pressed:
		pl.buffer = BUFFER
	else:
		pl.buffer = maxf(0.0, pl.buffer - dt)
	if pl.grounded:
		pl.coyote = COYOTE
	else:
		pl.coyote = maxf(0.0, pl.coyote - dt)
	if pl.buffer > 0 and pl.coyote > 0:
		if pl.support_kind == KIND_PLATFORM:
			var bv := platforms[pl.support_id].body.vel
			pl.carry = V3.new(bv.x, 0, bv.z)
		pl.vel.y = JUMP_V
		pl.grounded = false
		pl.coyote = 0.0
		pl.buffer = 0.0
		pl.jump_cut = false
		pl.since_jump = 0.0
		pl.support_kind = -1
		events.append({"t": "jump", "mode": mode})
	if not jump_held and pl.vel.y > 0 and not pl.jump_cut and pl.since_jump > 0.07 and pl.since_jump < 0.6:
		pl.vel.y *= JUMP_CUT
		pl.jump_cut = true

	var g := GRAVITY
	if pl.vel.y < 0:
		g *= FALL_MUL
	elif jump_held and absf(pl.vel.y) < APEX_BAND:
		g *= APEX_MUL
	pl.vel.y = maxf(pl.vel.y - g * dt, -MAX_FALL)

	var was_grounded := pl.grounded
	var fall_speed := -pl.vel.y
	var prev_kind := pl.support_kind
	var prev_id := pl.support_id

	var hit_x := _move_axis(geo, 0, (pl.vel.x + pl.carry.x) * dt, null, null)
	if hit_x:
		pl.vel.x = 0.0
		pl.carry.x = 0.0
	if mode == "3d" or pl.embedded:
		var hit_z := _move_axis(geo, 2, (pl.vel.z + pl.carry.z) * dt, null, null)
		if hit_z:
			pl.vel.z = 0.0
			pl.carry.z = 0.0
	var supports: Array = []
	var hit_y := _move_axis(geo, 1, pl.vel.y * dt, null, supports)
	if hit_y:
		if pl.vel.y > 0:
			pl.vel.y = 0.0
			events.append({"t": "bonk"})
		else:
			pl.vel.y = 0.0
	pl.grounded = hit_y and supports.size() > 0

	if pl.grounded:
		pl.carry = V3.new()
	elif prev_kind == KIND_PLATFORM:
		var bv := platforms[prev_id].body.vel
		pl.carry = V3.new(bv.x, 0, bv.z)
		if bv.y > 0:
			pl.vel.y += bv.y * 0.5

	if pl.grounded:
		var chosen = _choose_support(supports, geo)
		if chosen != null:
			pl.support_kind = chosen.kind
			pl.support_id = chosen.id
			pl.support_mat = chosen.mat
		else:
			pl.support_kind = -1
			pl.support_mat = Level.MAT_STONE
		if not was_grounded:
			pl.since_land = 0.0
			pl.last_impact = fall_speed
			events.append({"t": "land", "impact": fall_speed, "mode": mode, "surface": pl.support_mat})
		if chosen != null and chosen.kind == KIND_DRUM:
			var def: Dictionary = level.drums[chosen.id]
			pl.vel.y = sqrt(2.0 * GRAVITY * def.power)
			pl.grounded = false
			pl.coyote = 0.0
			pl.jump_cut = true
			pl.since_jump = 0.0
			pl.support_kind = -1
			drum_hit[chosen.id] = 0.0
			events.append({"t": "bounce", "id": chosen.id})
		var speed := _hypot2(pl.vel.x, pl.vel.z)
		pl.step_acc += speed * dt
		if pl.step_acc > STEP_EVERY:
			pl.step_acc -= STEP_EVERY
			events.append({"t": "step", "mode": mode, "surface": pl.support_mat})
	else:
		pl.support_kind = -1
		pl.step_acc = STEP_EVERY * 0.7
	pl.walk += _hypot2(pl.pos.x - pl.prev.x, pl.pos.z - pl.prev.z)
	_update_keys()


## Picks what the player stands on; on the page it also decides the player's depth.
func _choose_support(supports: Array, geo: int):
	var pl := player
	if supports.is_empty():
		return null
	var z_lo := pl.pos.z - HD
	var z_hi := pl.pos.z + HD
	if geo == GEO_3D:
		for s in supports:
			if s.kind == KIND_DRUM:
				return s
		for s in supports:
			if s.kind == KIND_PLATFORM:
				return s
		return supports[0]
	var drums_only: Array = []
	for s in supports:
		if s.kind == KIND_DRUM:
			drums_only.append(s)
	var chosen = _nearest_by_depth(drums_only, pl.pos.z)
	if chosen == null:
		var here: Array = []
		for s in supports:
			if s.z1 > z_lo + EPS and s.z0 < z_hi - EPS:
				here.append(s)
		for s in here:
			if s.kind == KIND_PLATFORM:
				chosen = s
				break
		if chosen == null and not here.is_empty():
			chosen = here[0]
		if chosen == null:
			chosen = _nearest_by_depth(supports, pl.pos.z)
	if chosen == null:
		return null
	if not (chosen.z1 > z_lo + EPS and chosen.z0 < z_hi - EPS):
		var span: float = chosen.z1 - chosen.z0
		var nz: float
		if span >= HD * 2:
			nz = clampf(pl.pos.z, chosen.z0 + HD, chosen.z1 - HD)
		else:
			nz = (chosen.z0 + chosen.z1) / 2.0
		pl.pos.z = nz
	return chosen


func _update_keys() -> void:
	var pl := player
	var lv := level
	for i in lv.keys.size():
		var k: Dictionary = lv.keys[i]
		var kp: V3 = k.pos
		var on := false
		if pl.grounded and absf(pl.pos.y - kp.y) < 0.02:
			var x_over: bool = pl.pos.x + HW > kp.x + 0.08 and pl.pos.x - HW < kp.x + k.width - 0.08
			if x_over:
				if _geo() == GEO_3D:
					on = pl.pos.z + HD > kp.z + 0.08 and pl.pos.z - HD < kp.z + 0.92
				else:
					on = true
					var cx := floori(clampf(pl.pos.x, kp.x, kp.x + k.width - 0.01))
					if lv.solid_at(cx, int(kp.y) - 1, int(kp.z)):
						pl.pos.z = kp.z + 0.5
		if on and not key_down[i]:
			groups[k.group] = not groups[k.group]
			events.append({"t": "key", "id": i, "group": k.group, "on": groups[k.group]})
			events.append({"t": "gate", "group": k.group, "on": groups[k.group]})
		key_down[i] = on


# ------------------------------------------------------------------ interactions

func _interact() -> void:
	var pl := player
	var lv := level
	var flat := mode == "2d"
	var pcx := pl.pos.x
	var pcy := pl.pos.y + PH / 2.0
	var pcz := pl.pos.z

	for i in lv.notes.size():
		if notes_taken[i]:
			continue
		var n: V3 = lv.notes[i].pos
		var dx := absf(n.x - pcx) - HW
		var dy := absf(n.y - pcy) - PH / 2.0
		var dz := -1.0 if flat else absf(n.z - pcz) - HD
		if dx < 0.38 and dy < 0.38 and dz < 0.38:
			notes_taken[i] = true
			note_taken_at[i] = time
			events.append({"t": "note", "id": i, "count": notes_count(), "total": lv.notes.size()})

	for i in lv.checkpoints.size():
		var c: V3 = lv.checkpoints[i].pos
		var near := absf(c.x - pl.pos.x) < 0.75 and pl.pos.y >= c.y - 0.2 and pl.pos.y < c.y + 2 and (flat or absf(c.z - pl.pos.z) < 0.9)
		if near and checkpoint_on != i:
			var forward := checkpoint_on < 0 or i > checkpoint_on or checkpoint_at[i] < 0
			if forward:
				checkpoint_on = i
				checkpoint_at[i] = time
				respawn_pos = c.copy()
				respawn_groups = groups.duplicate()
				events.append({"t": "checkpoint", "id": i})

	var ex := lv.exit_pos
	if absf(ex.x - pl.pos.x) < 0.7 and pl.pos.y >= ex.y - 0.3 and pl.pos.y < ex.y + 2.2 and (flat or absf(ex.z - pl.pos.z) < 1.0):
		finished = true
		finished_at = time
		pl.vel.y = 0.0
		events.append({"t": "exit"})
		return

	var kill_y := lv.water - 0.75 if lv.has_water() else KILL_Y
	if pl.pos.y < kill_y:
		_die("fall")
		return
	if _touches_thorns():
		_die("thorn")
		return
	for d in discords:
		var dx := absf(d.pos.x - pcx) - HW
		var dy := absf(d.pos.y - pcy) - PH / 2.0
		var dz := -1.0 if flat else absf(d.pos.z - pcz) - HD
		if dx < 0.3 and dy < 0.3 and dz < 0.3:
			_die("discord")
			return

	active_sign = null
	for s in lv.signs:
		if s.mode != "" and s.mode != mode:
			continue
		var sp: V3 = s.pos
		if absf(sp.x - pl.pos.x) < s.radius and pl.pos.y > sp.y - 1.5 and pl.pos.y < sp.y + 3 and (flat or absf(sp.z - pl.pos.z) < s.radius + 2):
			active_sign = s
			break


func _touches_thorns() -> bool:
	var pl := player
	var lv := level
	var inset := 0.16
	var x0 := floori(pl.pos.x - HW + inset)
	var x1 := floori(pl.pos.x + HW - inset)
	var y0 := floori(pl.pos.y + inset)
	var y1 := floori(pl.pos.y + PH - inset)
	var geo := _geo()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x < 0 or y < 0 or x >= lv.w or y >= lv.h:
				continue
			if geo == GEO_PROJ:
				if lv.thorn_col[x + lv.w * y] != 0:
					return true
			else:
				var z0 := floori(pl.pos.z - HD + inset)
				var z1 := floori(pl.pos.z + HD - inset)
				for z in range(z0, z1 + 1):
					if z >= 0 and z < lv.d and lv.cells[x + lv.w * (y + lv.h * z)] == Level.MAT_THORN:
						return true
	return false


func _die(cause: String) -> void:
	var pl := player
	pl.dead = DEATH_TIME
	pl.vel = V3.new()
	deaths += 1
	events.append({"t": "death", "cause": cause, "pos": pl.pos.copy()})


## Sends the player back to the last metronome without counting a death.
func return_to_checkpoint() -> void:
	if finished:
		return
	_do_respawn()


func _do_respawn() -> void:
	var pl := player
	pl.dead = 0.0
	pl.pos = respawn_pos.copy()
	pl.prev = respawn_pos.copy()
	pl.vel = V3.new()
	pl.carry = V3.new()
	pl.grounded = false
	pl.support_kind = -1
	pl.buffer = 0.0
	pl.coyote = 0.0
	groups = respawn_groups.duplicate()
	for i in gate_bodies.size():
		var g: Dictionary = level.gates[i]
		var want: bool = groups[g.group] == g.solidWhenOn
		gate_bodies[i].solid = want and not _overlap3(pl.pos, gate_bodies[i])
	if mode == "2d":
		pl.embedded = _overlaps_any(GEO_PROJ, pl.pos, null)
	var i := 0
	while i < 30 and not pl.grounded:
		_physics(1.0 / 120.0, 0.0, 0.0, false, false)
		i += 1
	pl.prev = pl.pos.copy()
	pl.since_land = 9.0
	var kept: Array = []
	for e in events:
		if e.t != "land" and e.t != "step":
			kept.append(e)
	events = kept
	events.append({"t": "respawn"})


# ------------------------------------------------------------------ collision core

func _overlaps_any(geo: int, pos: V3, ignore: Body) -> bool:
	var bx0 := pos.x - HW
	var by0 := pos.y
	var bz0 := pos.z - HD
	var bx1 := pos.x + HW
	var by1 := pos.y + PH
	var bz1 := pos.z + HD
	_collect(geo, bx0, by0, bz0, bx1, by1, bz1, ignore)
	for i in _nbox:
		var o := i * 9
		if _overlap(bx0, by0, bz0, bx1, by1, bz1, _boxes[o], _boxes[o + 1], _boxes[o + 2], _boxes[o + 3], _boxes[o + 4], _boxes[o + 5], geo):
			return true
	return false


## Moves the player along one axis (0 x, 1 y, 2 z) and stops at the first solid face.
## Solids already overlapped before the move are ignored so nothing can trap the player.
func _move_axis(geo: int, axis: int, d: float, ignore: Body, supports) -> bool:
	if d == 0:
		return false
	var pl := player
	var px0 := pl.pos.x - HW
	var py0 := pl.pos.y
	var pz0 := pl.pos.z - HD
	var px1 := pl.pos.x + HW
	var py1 := pl.pos.y + PH
	var pz1 := pl.pos.z + HD
	pl.pos.set_axis(axis, pl.pos.axis(axis) + d)
	var qx0 := pl.pos.x - HW
	var qy0 := pl.pos.y
	var qz0 := pl.pos.z - HD
	var qx1 := pl.pos.x + HW
	var qy1 := pl.pos.y + PH
	var qz1 := pl.pos.z + HD
	_collect(geo, minf(px0, qx0), minf(py0, qy0), minf(pz0, qz0), maxf(px1, qx1), maxf(py1, qy1), maxf(pz1, qz1), ignore)
	var limit := INF if d > 0 else -INF
	var hit := false
	var hits: Array = []
	for i in _nbox:
		var o := i * 9
		var b0 := _boxes[o]
		var b1 := _boxes[o + 1]
		var b2 := _boxes[o + 2]
		var b3 := _boxes[o + 3]
		var b4 := _boxes[o + 4]
		var b5 := _boxes[o + 5]
		if not _overlap(qx0, qy0, qz0, qx1, qy1, qz1, b0, b1, b2, b3, b4, b5, geo):
			continue
		if _overlap(px0, py0, pz0, px1, py1, pz1, b0, b1, b2, b3, b4, b5, geo):
			continue
		hit = true
		if d > 0:
			var face := b0 if axis == 0 else (b1 if axis == 1 else b2)
			if face < limit:
				limit = face
		else:
			var face := b3 if axis == 0 else (b4 if axis == 1 else b5)
			if face > limit:
				limit = face
			if axis == 1 and supports != null:
				hits.append({"kind": int(_boxes[o + 6]), "id": int(_boxes[o + 7]), "mat": int(_boxes[o + 8]), "top": b4, "z0": b2, "z1": b5})
	if not hit:
		return false
	if axis == 0:
		pl.pos.x = limit - HW - EPS if d > 0 else limit + HW + EPS
	elif axis == 2:
		pl.pos.z = limit - HD - EPS if d > 0 else limit + HD + EPS
	else:
		pl.pos.y = limit - PH - EPS if d > 0 else limit + EPS
	if supports != null and d <= 0:
		for s in hits:
			if absf(s.top - limit) < 1e-3:
				supports.append(s)
	return true


func _push_box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, kind: int, bid: int, mat: int) -> void:
	var o := _nbox * 9
	if _boxes.size() < o + 9:
		_boxes.resize(o + 9 + 90)
	_boxes[o] = x0
	_boxes[o + 1] = y0
	_boxes[o + 2] = z0
	_boxes[o + 3] = x1
	_boxes[o + 4] = y1
	_boxes[o + 5] = z1
	_boxes[o + 6] = kind
	_boxes[o + 7] = bid
	_boxes[o + 8] = mat
	_nbox += 1


## Collects every solid box near the given box: voxel cells (or columns) and bodies.
func _collect(geo: int, bx0: float, by0: float, bz0: float, bx1: float, by1: float, bz1: float, ignore: Body) -> void:
	_nbox = 0
	var lv := level
	var x0 := maxi(0, floori(bx0 + EPS))
	var x1 := mini(lv.w - 1, floori(bx1 - EPS))
	var y0 := maxi(0, floori(by0 + EPS))
	var y1 := mini(lv.h - 1, floori(by1 - EPS))
	if geo == GEO_PROJ:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var fz := lv.front[x + lv.w * y]
				if fz == Level.NO_DEPTH:
					continue
				for z in range(fz, lv.d):
					var m := lv.cells[x + lv.w * (y + lv.h * z)]
					if not Level.is_solid_mat(m):
						continue
					_push_box(x, y, z, x + 1, y + 1, z + 1, KIND_WORLD, 0, m)
	else:
		var z0 := maxi(0, floori(bz0 + EPS))
		var z1 := mini(lv.d - 1, floori(bz1 - EPS))
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var m := lv.cells[x + lv.w * (y + lv.h * z)]
					if not Level.is_solid_mat(m):
						continue
					_push_box(x, y, z, x + 1, y + 1, z + 1, KIND_WORLD, 0, m)
	if bx0 < 0:
		_push_box(-BIG, -BIG, -BIG, 0, BIG, BIG, KIND_WORLD, -1, Level.MAT_STONE)
	if bx1 > lv.w:
		_push_box(lv.w, -BIG, -BIG, BIG, BIG, BIG, KIND_WORLD, -1, Level.MAT_STONE)
	if geo == GEO_3D:
		if bz0 < 0:
			_push_box(-BIG, -BIG, -BIG, BIG, BIG, 0, KIND_WORLD, -1, Level.MAT_STONE)
		if bz1 > lv.d:
			_push_box(-BIG, -BIG, lv.d, BIG, BIG, BIG, KIND_WORLD, -1, Level.MAT_STONE)
	for b in bodies:
		if not b.solid or b == ignore:
			continue
		if b.max.x <= bx0 or b.min.x >= bx1 or b.max.y <= by0 or b.min.y >= by1:
			continue
		if geo == GEO_3D and (b.max.z <= bz0 or b.min.z >= bz1):
			continue
		var mat := Level.MAT_BRASS if b.kind == KIND_DRUM or b.kind == KIND_GATE else Level.MAT_WOOD
		_push_box(b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z, b.kind, b.id, mat)


# ------------------------------------------------------------------ helpers

static func _overlap(ax0: float, ay0: float, az0: float, ax1: float, ay1: float, az1: float, bx0: float, by0: float, bz0: float, bx1: float, by1: float, bz1: float, geo: int) -> bool:
	if ax1 <= bx0 + EPS or ax0 >= bx1 - EPS:
		return false
	if ay1 <= by0 + EPS or ay0 >= by1 - EPS:
		return false
	if geo == GEO_PROJ:
		return true
	return az1 > bz0 + EPS and az0 < bz1 - EPS


func _overlap3(p: V3, b: Body) -> bool:
	return _overlap(p.x - HW, p.y, p.z - HD, p.x + HW, p.y + PH, p.z + HD, b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z, GEO_3D)


static func _nearest_by_depth(list: Array, z: float):
	var best = null
	var best_d := INF
	for s in list:
		var d: float = s.z0 - z if z < s.z0 else (z - s.z1 if z > s.z1 else 0.0)
		if d < best_d - 1e-6 or (absf(d - best_d) < 1e-6 and best != null and s.z0 < best.z0):
			best = s
			best_d = d
	return best


static func _approach(v: float, target: float, step_size: float) -> float:
	return minf(v + step_size, target) if v < target else maxf(v - step_size, target)


## Math.hypot exactly as V8 computes it (scaled, Kahan-compensated), so results
## match the web build to the last bit.
static func _hypot2(a: float, b: float) -> float:
	return hypot3(a, b, 0.0)


static func hypot3(a: float, b: float, c: float) -> float:
	var aa := absf(a)
	var ab := absf(b)
	var ac := absf(c)
	var m := maxf(aa, maxf(ab, ac))
	if m == 0.0:
		return 0.0
	var sum := 0.0
	var comp := 0.0
	for v in [aa, ab, ac]:
		var n: float = v / m
		var summand := n * n - comp
		var prelim := sum + summand
		comp = (prelim - sum) - summand
		sum = prelim
	return sqrt(sum) * m


## Position along a waypoint path at time t, with a pause at every waypoint.
static func path_position(path: Array, speed: float, pause: float, loop: bool, t: float) -> V3:
	if path.size() == 1:
		return path[0].copy()
	var legs: Array = []
	for i in path.size() - 1:
		legs.append([path[i], path[i + 1]])
	if loop:
		legs.append([path[path.size() - 1], path[0]])
	else:
		for i in range(path.size() - 1, 0, -1):
			legs.append([path[i], path[i - 1]])
	var durs: Array[float] = []
	var cycle := 0.0
	for leg in legs:
		var a: V3 = leg[0]
		var b: V3 = leg[1]
		var dur := hypot3(b.x - a.x, b.y - a.y, b.z - a.z) / speed
		durs.append(dur)
	for dur in durs:
		cycle = cycle + dur + pause
	var u := fmod(fmod(t, cycle) + cycle, cycle)
	for i in legs.size():
		if u < pause:
			return legs[i][0].copy()
		u -= pause
		if u < durs[i]:
			var k := u / durs[i] if durs[i] > 0 else 1.0
			var e := k * k * (3.0 - 2.0 * k)
			var a: V3 = legs[i][0]
			var b: V3 = legs[i][1]
			return V3.new(a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e, a.z + (b.z - a.z) * e)
		u -= durs[i]
	return path[0].copy()

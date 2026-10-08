extends Node3D
## Placeholder Stage: plain boxes. The real renderer replaces this file.

var _camera := Camera3D.new()
var _world := Node3D.new()
var _player := MeshInstance3D.new()


func _ready() -> void:
	# The simulation's depth axis points away from the viewer; Godot's points towards it.
	# The world is mirrored in z so it can be built in simulation coordinates.
	_world.scale = Vector3(1, 1, -1)
	add_child(_world)
	add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.95, 0.88, 0.75)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.8)
	add_child(env)
	var pm := BoxMesh.new()
	pm.size = Vector3(0.6, 0.86, 0.6)
	_player.mesh = pm
	_world.add_child(_player)


func resize(_view: View) -> void:
	pass


func load_level(game: Sim, _palette: Dictionary) -> void:
	for c in _world.get_children():
		if c != _player:
			c.queue_free()
	var lv := game.level
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	var xs: Array[Transform3D] = []
	for z in lv.d:
		for y in lv.h:
			for x in lv.w:
				if Level.is_solid_mat(lv.cells[x + lv.w * (y + lv.h * z)]):
					xs.append(Transform3D(Basis(), Vector3(x + 0.5, y + 0.5, z + 0.5)))
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	_world.add_child(mi)


func set_world_visible(v: bool) -> void:
	visible = v


func render(game: Sim, view: View, frame: Dictionary) -> void:
	var pose := view.stage_pose()
	var pos: Vector3 = pose.position
	var tgt: Vector3 = pose.target
	_camera.fov = pose.fov_deg
	_camera.near = pose.near
	_camera.far = pose.far
	_camera.position = Vector3(pos.x, pos.y, -pos.z)
	_camera.look_at(Vector3(tgt.x, tgt.y, -tgt.z))
	var a: float = frame.alpha
	var p := game.player
	_player.position = Vector3(lerpf(p.prev.x, p.pos.x, a), lerpf(p.prev.y, p.pos.y, a) + 0.43, lerpf(p.prev.z, p.pos.z, a))

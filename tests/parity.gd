extends SceneTree
## Replays the web build's recorded movement solutions through the native
## simulation and checks every snapshot matches.
##   godot --headless --path . --script tests/parity.gd

const TOL := 1e-9


func _init() -> void:
	var ok := true
	for id in ["overture", "adagio", "scherzo", "nocturne", "toccata", "finale"]:
		ok = _check(id) and ok
	print("PARITY %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _check(id: String) -> bool:
	var f := FileAccess.open("res://tests/data/%s.json" % id, FileAccess.READ)
	var rec: Dictionary = JSON.parse_string(f.get_as_text())
	var sim := Sim.new(Level.load_id(id), "3d")
	var snaps: Array = rec.snaps
	var si := 0
	var worst := 0.0
	var t0 := Time.get_ticks_msec()
	var inputs: Array = rec.inputs
	if not _match(sim, snaps[si], id):
		return false
	si += 1
	for i in inputs.size():
		var inp: Array = inputs[i]
		var flags := int(inp[2])
		sim.step(1.0 / 120.0, float(inp[0]), float(inp[1]), flags & 1 != 0, flags & 2 != 0, flags & 4 != 0)
		sim.events.clear()
		while si < snaps.size() and int(snaps[si][0]) == i + 1:
			var s: Array = snaps[si]
			var p := sim.player.pos
			worst = maxf(worst, maxf(absf(p.x - s[1]), maxf(absf(p.y - s[2]), absf(p.z - s[3]))))
			if not _match(sim, s, id):
				return false
			si += 1
	var good: bool = sim.finished == bool(rec.finished) and sim.notes_count() == int(rec.notes) and sim.deaths == int(rec.deaths)
	print("%s: %d steps, worst drift %s, finished %s, notes %d, deaths %d, %d ms %s" % [id, inputs.size(), String.num_scientific(worst), sim.finished, sim.notes_count(), sim.deaths, Time.get_ticks_msec() - t0, "ok" if good else "MISMATCH"])
	return good


func _match(sim: Sim, s: Array, id: String) -> bool:
	var p := sim.player.pos
	var m := 1 if sim.mode == "3d" else 0
	var bad := absf(p.x - s[1]) > TOL or absf(p.y - s[2]) > TOL or absf(p.z - s[3]) > TOL or m != int(s[4]) or sim.notes_count() != int(s[5]) or sim.deaths != int(s[6])
	if bad:
		print("%s: diverged at step %d: native (%.6f, %.6f, %.6f) mode %d notes %d deaths %d, web (%.6f, %.6f, %.6f) mode %d notes %d deaths %d" % [id, s[0], p.x, p.y, p.z, m, sim.notes_count(), sim.deaths, s[1], s[2], s[3], s[4], s[5], s[6]])
	return not bad

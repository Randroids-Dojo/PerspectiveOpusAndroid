class_name StageProps
extends RefCounted
## The dressing that animates by itself: decor's swinging lanterns and bells, turning
## gears and flickering lights (decor.ts), the thorns' throbbing heat and berries
## (flora.ts Thorns), and the tuft counts per quality (flora.ts Flora).

var _anims: Array = []
var _lights: Array = []
var _berry_mats: Array = []
var _berry_emissive := Vector3.ZERO
var _hot_mats: Array = []
var _hot_base := Vector3.ZERO
var _clockwork := false
var _tufts: Array = []
var _full: Array = []


func setup(bake: StageBake) -> void:
	var decor: Dictionary = bake.module("decor")
	_anims = decor.anims
	_lights = decor.lights
	var thorns: Dictionary = bake.module("thorns")
	_berry_mats = bake.mats_of(thorns.berryMat)
	if thorns.berryMat is Dictionary:
		var d: Dictionary = bake.data.mats[int(thorns.berryMat.mat)]
		_berry_emissive = StageMaterials.v3(d.get("emissive"))
	_hot_base = thorns.hotBase if thorns.hotBase is Vector3 else Vector3.ZERO
	_clockwork = bool(thorns.clockwork)
	_hot_mats.clear()
	for i in bake.data.mats.size():
		var k := String(bake.data.mats[i].get("key", ""))
		if k == "opus:ch:thorn" or k == "opus:ch:cog":
			_hot_mats.append_array(bake.mat_instances[i])
	var flora: Dictionary = bake.module("flora")
	_tufts = flora.tufts
	_full = flora.full


func set_quality(q: String) -> void:
	for i in _tufts.size():
		var mmi := _tufts[i] as MultiMeshInstance3D
		mmi.visible = q != "low"
		mmi.multimesh.visible_instance_count = int(_full[i]) if q == "high" else ceili(float(_full[i]) * 0.45)


func update(time: float, halos: StageEffects.Halos) -> void:
	for a in _anims:
		var obj: Node3D = a.obj
		if a.kind == "spin":
			obj.rotation.z = time * float(a.speed)
		elif a.kind == "swing":
			obj.rotation.z = sin(time * float(a.speed) + float(a.phase)) * float(a.amp)
	for l in _lights:
		var f := 0.85 + 0.15 * sin(time * 9.0 + float(l.x) * 3.0) * sin(time * 6.3 + float(l.z) * 5.0) if float(l.flicker) != 0.0 else 1.0
		halos.add(l.x, l.y, l.z, l.size, l.color, float(l.intensity) * f)
	if not _berry_mats.is_empty():
		var e := _berry_emissive * (1.8 + sin(time * 2.2) * 0.6)
		for m in _berry_mats:
			m.set_shader_parameter("emissive", e)
	if not _hot_mats.is_empty():
		# Brambles throb slowly; clockwork flickers like a forge.
		var k := 0.85 + 0.1 * sin(time * 7.3) + 0.06 * sin(time * 17.1) if _clockwork else 0.8 + 0.25 * sin(time * 2.2)
		for m in _hot_mats:
			m.set_shader_parameter("hot_color", _hot_base * k)

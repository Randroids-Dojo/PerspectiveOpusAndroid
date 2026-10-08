class_name PageCache
extends RefCounted
## Recorded geometry for live things, keyed by what it depends on (usually the thing and
## the boil frame). An entry not used for a couple of frames is dropped, so a boil
## drawing lives only as long as its boil frame.

var _map := {}
var _used := {}
var _frame := 0


func next_frame() -> void:
	_frame += 1
	if _frame % 30 == 0:
		var dead: Array = []
		for key in _used:
			if _used[key] < _frame - 2:
				dead.append(key)
		for key in dead:
			_map.erase(key)
			_used.erase(key)


func lookup(key: String) -> Variant:
	var v: Variant = _map.get(key)
	if v != null:
		_used[key] = _frame
	return v


func store(key: String, v: Variant) -> void:
	_map[key] = v
	_used[key] = _frame


func clear() -> void:
	_map.clear()
	_used.clear()

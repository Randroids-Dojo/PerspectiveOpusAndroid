class_name OpusSave
extends RefCounted
## Progress and settings in user://save.json, the same shape and rules as the web
## build's src/core/save.ts (localStorage "opus:v1:save"):
##   {v: 1, movements: {id: {done, notes: [bool], bestTime, fewestDeaths}},
##    settings: {master, music, sfx, reduceMotion, quality, startIn, showTimer},
##    seenEnding, last}
## The native build adds one setting, `haptics`, which the web build would ignore.

const PATH := "user://save.json"
const DEFAULT_SETTINGS := {
	"master": 0.85,
	"music": 0.8,
	"sfx": 0.9,
	"reduceMotion": false,
	"quality": "auto",
	"startIn": "3d",
	"showTimer": false,
	"haptics": true,
}

var data: Dictionary
var path := PATH
## False for throwaway saves (screenshots); progress then lasts for this run only.
var writable := true


static func fresh() -> Dictionary:
	return {"v": 1, "movements": {}, "settings": DEFAULT_SETTINGS.duplicate(), "seenEnding": false, "last": 0}


static func load_from(p: String) -> OpusSave:
	var s := OpusSave.new()
	s.path = p
	s.data = fresh()
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary and int(parsed.get("v", 0)) == 1:
			s.data = parsed
			var st: Dictionary = DEFAULT_SETTINGS.duplicate()
			var saved = parsed.get("settings", {})
			if saved is Dictionary:
				st.merge(saved, true)
			s.data.settings = st
			if not (s.data.get("movements") is Dictionary):
				s.data.movements = {}
			s.data.seenEnding = bool(s.data.get("seenEnding", false))
			s.data.last = int(s.data.get("last", 0))
	return s


var settings: Dictionary:
	get:
		return data.settings


var movements: Dictionary:
	get:
		return data.movements


func write() -> void:
	if not writable:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return  # Storage unavailable: progress lasts for this run only.
	f.store_string(JSON.stringify(data))


## The record for a movement, created on first play and padded to `notes` entries.
func record(id: String, notes: int) -> Dictionary:
	var r = data.movements.get(id)
	if not (r is Dictionary):
		var list: Array = []
		list.resize(notes)
		list.fill(false)
		r = {"done": false, "notes": list, "bestTime": null, "fewestDeaths": null}
		data.movements[id] = r
	var n: Array = r.get("notes", [])
	while n.size() < notes:
		n.append(false)
	r.notes = n
	return r


func found(id: String) -> int:
	var r = data.movements.get(id)
	if not (r is Dictionary):
		return 0
	var n := 0
	for t in r.get("notes", []):
		if t:
			n += 1
	return n


func is_done(id: String) -> bool:
	var r = data.movements.get(id)
	return r is Dictionary and bool(r.get("done", false))


func note_found(id: String, i: int) -> bool:
	var r = data.movements.get(id)
	if not (r is Dictionary):
		return false
	var n: Array = r.get("notes", [])
	return i < n.size() and bool(n[i])


func best_time(id: String):
	var r = data.movements.get(id)
	if not (r is Dictionary):
		return null
	return r.get("bestTime")


func total_notes(ids: Array) -> int:
	var n := 0
	for id in ids:
		n += found(id)
	return n


## Anything played at all: a movement finished or a note found.
func started() -> bool:
	for id in data.movements:
		if is_done(id) or found(id) > 0:
			return true
	return false


## The first movement not yet performed (ids.size() when all are).
func next_movement(ids: Array) -> int:
	for i in ids.size():
		if not is_done(ids[i]):
			return i
	return ids.size()


func unlocked(ids: Array, i: int) -> bool:
	return i == 0 or is_done(ids[i - 1])

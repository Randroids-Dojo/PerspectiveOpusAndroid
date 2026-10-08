class_name V3
extends RefCounted
## A 64-bit vector. Godot's Vector3 is 32-bit, but the simulation must match the
## web build (JavaScript doubles) step for step, so physics state uses this instead.

var x: float
var y: float
var z: float


func _init(ax: float = 0.0, ay: float = 0.0, az: float = 0.0) -> void:
	x = ax
	y = ay
	z = az


func copy() -> V3:
	return V3.new(x, y, z)


func axis(a: int) -> float:
	return x if a == 0 else (y if a == 1 else z)


func set_axis(a: int, v: float) -> void:
	if a == 0:
		x = v
	elif a == 1:
		y = v
	else:
		z = v


func to_vec3() -> Vector3:
	return Vector3(x, y, z)


static func from_dict(d: Dictionary) -> V3:
	return V3.new(float(d.x), float(d.y), float(d.z))

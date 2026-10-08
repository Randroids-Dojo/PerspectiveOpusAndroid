class_name StageGlobals
extends RefCounted
## The per-frame state every stage material reads (the web Stage's SHARED uniforms plus
## the light rig), kept in a 16 x 1 float texture that is rewritten once a frame. One
## texture bound to every material is cheaper than setting a dozen uniforms on each.
##
## Layout (one vec4 per texel, read by shaders/globals.gdshaderinc):
##   0  time, wind, cutout on, cutout radius (px)
##   1  cutout centre (px, FRAGCOORD space), Quaver's view depth, Quaver's feet height
##   2  height fog top, bottom, strength, water line (or -999)
##   3  height fog colour
##   4  water colour
##   5  Quaver's feet (simulation space)
##   6  fog colour
##   7  fog near, fog far, environment intensity
##   8  hemisphere sky colour x intensity
##   9  hemisphere ground colour x intensity
##   10 spot position (world), spot on
##   11 spot direction (world, light to target), cos(angle)
##   12 spot colour x intensity, cos(angle x (1 - penumbra))
##   13 spot decay

const SIZE := 16

var texture: ImageTexture
var _img: Image
var _data := PackedFloat32Array()


func _init() -> void:
	_data.resize(SIZE * 4)
	_img = Image.create_from_data(SIZE, 1, false, Image.FORMAT_RGBAF, _data.to_byte_array())
	texture = ImageTexture.create_from_image(_img)
	set_v(2, Vector4(1, -3, 1, -999))


func set_v(i: int, v: Vector4) -> void:
	_data[i * 4] = v.x
	_data[i * 4 + 1] = v.y
	_data[i * 4 + 2] = v.z
	_data[i * 4 + 3] = v.w


func set3(i: int, v: Vector3, w: float = 0.0) -> void:
	set_v(i, Vector4(v.x, v.y, v.z, w))


func get_v(i: int) -> Vector4:
	return Vector4(_data[i * 4], _data[i * 4 + 1], _data[i * 4 + 2], _data[i * 4 + 3])


## Uploads this frame's values.
func flush() -> void:
	_img.set_data(SIZE, 1, false, Image.FORMAT_RGBAF, _data.to_byte_array())
	texture.update(_img)

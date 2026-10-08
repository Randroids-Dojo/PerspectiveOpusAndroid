class_name PageRand
extends RefCounted
## Deterministic hashing for the page, bit for bit the web build's src/render2d/rand.ts:
## every stroke is seeded, so the drawing never jitters at random and lands exactly
## where the web build puts it. Values are kept as unsigned 32-bit ints in 64-bit ints.

const M32 := 0xFFFFFFFF
const INV32 := 1.0 / 4294967296.0


## Math.imul for values already in [0, 2^32): the low 32 bits of the product.
static func imul(a: int, b: int) -> int:
	return (a * b) & M32


## Integer hash of up to four values, in [0, 1).
static func hash01(a: int, b: int = 0, c: int = 0, d: int = 0) -> float:
	var h: int = ((a & M32) * 0x9e3779b1) ^ (((b + 0x632be5ab) & M32) * 0x85ebca77)
	h &= M32
	h ^= ((((c + 0x1b873593) & M32) * 0xc2b2ae3d) ^ (((d + 0x68e31da4) & M32) * 0x27d4eb2f)) & M32
	h ^= h >> 15
	h = (h * 0x2c1b3c6d) & M32
	h ^= h >> 12
	h = (h * 0x297a2d39) & M32
	h ^= h >> 15
	return float(h) * INV32


## Signed hash in [-1, 1).
static func hs(a: int, b: int = 0, c: int = 0, d: int = 0) -> float:
	return hash01(a, b, c, d) * 2.0 - 1.0


## Smooth 1D value noise in [-1, 1].
static func noise1(x: float, seed: int) -> float:
	var i := floori(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	return hs(i, seed) * (1.0 - u) + hs(i + 1, seed) * u


## JavaScript's `x | 0` for a number: truncation towards zero, wrapped to 32 bits.
static func i32(x: float) -> int:
	return int(x) & M32


## A small seeded generator for sequences of strokes (rng() in the web build).
class Gen:
	var a: int

	## `raw` starts from the seed as is (the decor's own generator); otherwise it is mixed
	## with a constant as rng() does.
	func _init(seed: int, raw: bool = false) -> void:
		a = (seed & 0xFFFFFFFF) if raw else ((seed & 0xFFFFFFFF) ^ 0x5bd1e995)

	func next() -> float:
		a = (a + 0x6d2b79f5) & 0xFFFFFFFF
		var t: int = ((a ^ (a >> 15)) * (1 | a)) & 0xFFFFFFFF
		t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

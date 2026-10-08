class_name PageTones
extends RefCounted
## Colours derived from a palette for the page (the web build's tones.ts and color.ts).
## Depth is read by tone: layer 0 (front) is the darkest, densest ink; the back layer is
## a pale wash close to the paper. On the Nocturne the same ramp runs from silver to indigo.

const MATS := ["stone", "brick", "wood", "brass", "dark", "crystal", "leaf", "thorn", "marble"]
## How much of the material colour survives into the wash.
const MAT_W := {"stone": 0.34, "brick": 0.5, "wood": 0.5, "brass": 0.62, "dark": 0.3, "crystal": 0.6, "leaf": 0.55, "thorn": 0.4, "marble": 0.3}


class Layer:
	## 0 at the front, 1 at the back.
	var k: float
	var tone: Color
	var ink: Color
	## Outline weight in drawing pixels at the reference scale.
	var outline_w: float
	## Fill per material index (Level.MAT_*); index 0 holds stone.
	var fill: Array[Color] = []
	var light: Color
	var dark: Color
	var density: float
	var top: Color


var pal: Dictionary
var id: String
var inv: bool
var paper: Color
var paper_shade: Color
var ink: Color
var ink_far: Color
var rubric: Color
var gold: Color
var gold_light: Color
var gold_dark: Color
## Shadows and hatching (darker than the paper on both kinds of page).
var shade: Color
var layers: Array[Layer] = []
var groups: Array[Color] = []
var body: Color
var eye: Color


# ---------------------------------------------------------------- colour helpers

static func rgb(hex: String) -> Color:
	return Color.html(hex)


static func mix(a: Color, b: Color, t: float) -> Color:
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0)


static func scale(c: Color, f: float) -> Color:
	return Color(minf(1.0, c.r * f), minf(1.0, c.g * f), minf(1.0, c.b * f), 1.0)


static func saturate(c: Color, s: float) -> Color:
	var l := (c.r + c.g + c.b) / 3.0
	return Color(clampf(l + (c.r - l) * s, 0, 1), clampf(l + (c.g - l) * s, 0, 1), clampf(l + (c.b - l) * s, 0, 1), 1.0)


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


## "rgb(r,g,b)" as written by the web build's backdrop manifest.
static func parse_css(s: String) -> Color:
	var inner := s.substr(s.find("(") + 1).trim_suffix(")")
	var parts := inner.split(",")
	return Color8(int(parts[0]), int(parts[1]), int(parts[2]))


# ---------------------------------------------------------------- build

func _init(palette: Dictionary, depth: int) -> void:
	pal = palette
	id = String(palette.id)
	inv = bool(palette.inverted)
	paper = rgb(palette.paper)
	paper_shade = rgb(palette.paperShade)
	ink = rgb(palette.ink)
	ink_far = rgb(palette.inkFar)
	rubric = rgb(palette.rubric)
	gold = rgb(palette.gold)
	var near := rgb(palette.washNear)
	var far := rgb(palette.washFar)
	shade = scale(paper_shade, 0.55) if inv else ink
	var near_d := mix(near, ink, 0.3 if inv else 0.36)
	for z in depth:
		var k: float = float(z) / float(depth - 1) if depth > 1 else 0.0
		var kk := pow(k, 0.85)
		var tone := mix(near_d, far, kk)
		var L := Layer.new()
		L.fill.resize(10)
		for m in MATS:
			var base := rgb(palette.mats[m].color)
			if inv:
				base = mix(base, rgb("#c7cde6"), 0.35)
			var w: float = MAT_W[m] * (0.42 + 0.45 * kk)
			var c := mix(tone, saturate(base, 1.08), w)
			c = mix(c, paper, 0.02 + 0.36 * kk)
			if not inv:
				c = saturate(c, 1.16 - 0.1 * kk)
			L.fill[Level.MAT_NAMES.find(m)] = c
		L.fill[0] = L.fill[Level.MAT_STONE]
		var ink_c := mix(ink, ink_far, pow(k, 0.7))
		var fill_mid: Color = L.fill[Level.MAT_STONE]
		L.dark = mix(fill_mid, scale(paper, 0.7), 0.55) if inv else mix(fill_mid, ink, 0.55)
		L.light = mix(fill_mid, Color.WHITE, 0.45) if inv else mix(fill_mid, mix(paper, rgb("#fffaf0"), 0.4), 0.5 + 0.1 * (1.0 - k))
		L.top = mix(mix(rgb(palette.topColor), tone, 0.18 + 0.5 * kk), paper, 0.25 * kk)
		L.k = k
		L.tone = tone
		L.ink = ink_c
		L.outline_w = 2.5 - 1.5 * kk
		L.density = 1.0 - 0.55 * kk
		layers.append(L)
	for hex in [palette.rubric, "#2f5fa8", "#2f8a6a", "#7a4aa8", "#c9862a", "#2a8aa8"]:
		var c := rgb(hex)
		groups.append(mix(c, Color.WHITE, 0.25) if inv else c)
	gold_light = mix(gold, rgb("#fff4cf"), 0.55)
	gold_dark = mix(gold, rgb("#3a2a10") if inv else ink, 0.45)
	body = rgb("#0b0d1c") if inv else ink
	eye = rgb("#fffaf0")


func mat_color(m: String, second: bool = false) -> Color:
	return rgb(pal.mats[m].color2 if second else pal.mats[m].color)


## Layer tone for things between layers (moving entities).
func tone_at(z: float) -> Layer:
	var i := clampi(roundi(z - 0.5), 0, layers.size() - 1)
	return layers[i]


## A colour pushed towards the layer's tone, the way the page fades things further back.
func depth_tint(c: Color, z: float, amount: float = 1.0) -> Color:
	var L := tone_at(z)
	var kk := pow(L.k, 0.78)
	return mix(mix(c, L.tone, 0.08 + 0.4 * kk * amount), paper, 0.22 * kk * amount)

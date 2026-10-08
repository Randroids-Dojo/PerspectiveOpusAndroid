class_name PageWipe
extends RefCounted
## The switch (wipe.ts): the page dissolves from the player outwards like a drop of ink
## eating through paper. The hole's edge is an organic blot with a dark wet rim, fingers
## of ink running along the fibres, satellite droplets ahead of the front and torn paper
## hairs poking into the opening. The shape is a pure function of the wipe amount, the
## origin and a slow time term, so the switch can reverse at any instant without a jump.
##
## The blot's radius per angle is computed here exactly as the web build does; the page's
## display shader (SHADER) then cuts the hole and lays the halo, the layered wet rim and
## the film inside the opening per pixel from that table. Tendrils and satellites are inked
## onto the page; hairs and spray are drawn over the stage.

const N := 256
const LO := [[3.0, 0.42, 0.7, 0.35], [5.0, 0.3, 2.1, -0.25], [8.0, 0.18, 4.4, 0.5], [2.0, 0.1, 1.3, 0.15]]
const HI := [[17.0, 0.45, 0.3], [29.0, 0.3, 5.1], [47.0, 0.17, 2.6], [71.0, 0.08, 1.9]]
const MAX_HOLES := 34

const SHADER := """
shader_type canvas_item;

uniform bool active = false;
uniform vec2 size = vec2(1.0);
uniform vec2 origin = vec2(0.0);
uniform float rs[256];
uniform float halo = 30.0;
uniform float rim_w = 9.0;
uniform float film = 0.0;
uniform vec4 ink : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ink_deep : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 wet : source_color = vec4(0.0, 0.0, 0.0, 0.05);
uniform int hole_count = 0;
uniform vec3 holes[34];

float radius_at(float a) {
	float f = a / 6.28318530718 * 256.0;
	float i0 = floor(f);
	float t = f - i0;
	int a0 = int(mod(i0, 256.0));
	int a1 = int(mod(i0 + 1.0, 256.0));
	return mix(rs[a0], rs[a1], t);
}

vec4 over(vec4 dst, vec3 c, float a) {
	return vec4(mix(dst.rgb, c, a), dst.a);
}

void fragment() {
	vec4 page = texture(TEXTURE, UV);
	page.a = 1.0;
	if (!active) {
		COLOR = page;
	} else {
		vec2 p = UV * size;
		vec2 d = p - origin;
		float r = length(d);
		float a = atan(d.y, d.x);
		if (a < 0.0) { a += 6.28318530718; }
		float R = radius_at(a);
		float w1 = 1.0 + 0.6 * sin(a * 7.0 + 1.3) * 0.5 + 0.6 * sin(a * 13.0 + 0.4) * 0.3;
		float w2 = 1.0 + 0.3 * sin(a * 7.0 + 1.3) * 0.5 + 0.3 * sin(a * 13.0 + 0.4) * 0.3;
		vec4 c = page;
		// Wet paper just beyond the rim, then the rim built up in thin layers.
		float rh = max(0.0, R + halo * w1);
		c = over(c, wet.rgb, wet.a * clamp(rh - r + 0.5, 0.0, 1.0));
		for (int i = 0; i < 12; i++) {
			float u = float(i) / 11.0;
			float off = 2.3 - 2.0 * u;
			float al = u < 0.85 ? 0.035 + 0.11 * u * u : (u < 0.95 ? 0.45 : 0.92);
			vec3 col = u > 0.9 ? ink_deep.rgb : ink.rgb;
			float rr = max(0.0, R + rim_w * off * w2);
			c = over(c, col, al * clamp(rr - r + 0.5, 0.0, 1.0));
		}
		// The hole, and the satellites' little holes.
		float open = clamp(R - r + 0.5, 0.0, 1.0);
		for (int h = 0; h < hole_count; h++) {
			vec3 hh = holes[h];
			open = max(open, clamp(hh.z - length(p - hh.xy) + 0.5, 0.0, 1.0));
		}
		// Inside the blot a thin film of ink pools at the edge, laid over the stage.
		float fa = 0.0;
		if (film > 1.0) {
			for (int k = 0; k < 3; k++) {
				float inner = film * (1.0 - float(k) * 0.33);
				float ri = max(0.0, R - inner * (1.0 + 0.35 * sin(a * 9.0 + 0.7)));
				float inside = clamp(r - ri + 0.5, 0.0, 1.0) * clamp(R - r + 0.5, 0.0, 1.0);
				float pa = k == 2 ? 0.55 : 0.2;
				fa = fa + (1.0 - fa) * pa * inside;
			}
		}
		// What is left of the page, plus the film over the opening (premultiplied, then straight).
		vec3 rgb = c.rgb * (1.0 - open) + ink.rgb * fa * open;
		float alpha = (1.0 - open) + fa * open;
		COLOR = vec4(alpha > 0.0001 ? rgb / alpha : ink.rgb, alpha);
	}
}
"""

var rs := PackedFloat32Array()
var _xs := PackedFloat32Array()
var fingers: Array = []
var sats: Array = []
var hairs: Array = []
var tendrils: Array = []
var active := false
var ox := 0.0
var oy := 0.0
var wipe := 0.0
var far := 1.0
var k := 0.0
var R0 := 0.0
var halo := 30.0
var rim_w := 9.0
var film := 0.0
var dpr := 1.0
var holes := PackedVector3Array()


func _init() -> void:
	rs.resize(N)
	for i in 9:
		fingers.append(Vector3(PageRand.hash01(i, 1) * TAU, 0.04 + PageRand.hash01(i, 2) * 0.07, 0.45 + PageRand.hash01(i, 3) * 0.8))
	for i in 34:
		sats.append([PageRand.hash01(i, 11) * TAU, 0.12 + pow(PageRand.hash01(i, 12), 0.8) * 1.15, PageRand.hash01(i, 13), PageRand.hash01(i, 14) < 0.55])
		hairs.append([PageRand.hash01(i, 21) * TAU, 0.4 + PageRand.hash01(i, 22) * 0.6, PageRand.hs(i, 23), PageRand.hs(i, 24) * 0.6])
	for i in 26:
		tendrils.append([PageRand.hash01(i, 31) * TAU, 0.3 + PageRand.hash01(i, 32) * 0.7, PageRand.hs(i, 33)])


static func _smooth(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Radius of the blot edge at angle `a`.
func _edge_r(a: float, lo: float, hi: float, fing: float, scal: float, time: float) -> float:
	var l := 0.0
	for o in LO:
		l += o[1] * sin(o[0] * a + o[2] + o[3] * time)
	var h := 0.0
	for o in HI:
		h += o[1] * sin(o[0] * a + o[2] + time * 0.4)
	var sc := pow(absf(sin(a * 19.0 + 0.6 + time * 0.15)), 0.6) * 0.6 + pow(absf(sin(a * 31.0 + 2.2)), 0.6) * 0.4
	var f := 0.0
	for g in fingers:
		var d: float = a - g.x
		d -= roundf(d / TAU) * TAU
		var x: float = d / g.y
		if x > -3.0 and x < 3.0:
			f += g.z * exp(-x * x)
	return R0 * (1.0 + lo * l) + hi * h + fing * f + scal * (sc - 0.6)


## Works out the blot for this frame. Returns false when there is nothing to show.
func compute(W: float, H: float, origin: Vector2, amount: float, time: float, dpr_: float) -> bool:
	active = amount > 0.0 and amount < 1.0
	if not active:
		return false
	dpr = dpr_
	ox = origin.x
	oy = origin.y
	wipe = amount
	far = maxf(maxf(Vector2(ox, oy).length(), Vector2(W - ox, oy).length()), maxf(Vector2(ox, H - oy).length(), Vector2(W - ox, H - oy).length()))
	halo = 30.0 * dpr
	rim_w = 9.0 * dpr
	var hi_max := 9.0 * dpr
	var fing_max := 26.0 * dpr
	var scal_max := 9.0 * dpr
	var lo_end := 0.035
	var r0max := (far + halo + rim_w * 1.8 + hi_max + scal_max + 4.0 * dpr) / (1.0 - lo_end)
	var e := pow(wipe, 1.45)
	R0 = r0max * e
	k = _smooth(R0 / far)
	var lo := 0.17 + (lo_end - 0.17) * k
	var hi := minf(R0 * 0.09, hi_max)
	var fing := minf(R0 * 0.28, fing_max) * (1.0 - 0.85 * _smooth((wipe - 0.35) / 0.45))
	var scal := minf(R0 * 0.05, scal_max)
	for i in N:
		rs[i] = _edge_r(float(i) / N * TAU, lo, hi, fing, scal, time)
	film = minf(16.0 * dpr, R0 * 0.12) * (1.0 - 0.6 * _smooth((wipe - 0.7) / 0.3))
	# Satellite droplets' little holes.
	holes.clear()
	for sat in sats:
		var D: float = sat[1] * far
		var lead := 0.22 * D + 36.0 * dpr
		var g := _smooth((R0 - (D - lead)) / (lead * 0.6))
		if g <= 0.0:
			continue
		var ia := floori(fposmod(sat[0] / TAU * N, N))
		if rs[ia] > D + 12.0 * dpr:
			continue
		var size: float = (1.5 + sat[2] * 7.5) * dpr * (0.6 + 0.4 * minf(1.0, D / (far * 0.5))) * g
		if sat[3] and size > 3.5 * dpr and holes.size() < MAX_HOLES:
			holes.append(Vector3(ox + cos(sat[0]) * D, oy + sin(sat[0]) * D, size * 0.55))
	return true


func shader_params(m: ShaderMaterial, t: PageTones, W: float, H: float) -> void:
	m.set_shader_parameter("active", active)
	if not active:
		return
	m.set_shader_parameter("size", Vector2(W, H))
	m.set_shader_parameter("origin", Vector2(ox, oy))
	m.set_shader_parameter("rs", rs)
	m.set_shader_parameter("halo", halo)
	m.set_shader_parameter("rim_w", rim_w)
	m.set_shader_parameter("film", film)
	m.set_shader_parameter("ink", t.ink)
	m.set_shader_parameter("ink_deep", t.ink if t.inv else PageTones.mix(t.ink, Color.BLACK, 0.45))
	var wet := PageTones.mix(t.paper, t.ink, 0.25) if t.inv else PageTones.mix(t.shade, t.paper, 0.15)
	m.set_shader_parameter("wet", Color(wet.r, wet.g, wet.b, 0.08 if t.inv else 0.05))
	var arr := PackedVector3Array(holes)
	arr.resize(MAX_HOLES)
	m.set_shader_parameter("holes", arr)
	m.set_shader_parameter("hole_count", holes.size())


## Ink running out along the fibres from the rim, and satellite droplets ahead of the
## front (on the page, before the hole is cut).
func draw_page(pt: PagePainter, t: PageTones) -> void:
	if not active:
		return
	var w := maxf(0.7, 0.9 * dpr)
	var tc := PageTones.alpha(t.ink, 0.55)
	for td in tendrils:
		var i := floori(fposmod(td[0] / TAU * N, N))
		var a := float(i) / N * TAU
		var r0 := rs[i] + rim_w * 0.4
		var length: float = (6.0 + td[1] * 22.0) * dpr * (0.4 + 0.6 * (1.0 - k * 0.5))
		var c := cos(a)
		var s := sin(a)
		var mid_r := r0 + length * 0.5
		var wig: float = td[2] * length * 0.25
		var pa := PagePath.new()
		pa.move_to(ox + c * r0, oy + s * r0)
		pa.quad_to(ox + c * mid_r - s * wig, oy + s * mid_r + c * wig, ox + c * (r0 + length), oy + s * (r0 + length))
		pt.stroke(pa.subpath(0), w, tc)
	var sc := PageTones.alpha(t.ink, 0.9)
	for sat in sats:
		var D: float = sat[1] * far
		var lead := 0.22 * D + 36.0 * dpr
		var g := _smooth((R0 - (D - lead)) / (lead * 0.6))
		if g <= 0.0:
			continue
		var ia := floori(fposmod(sat[0] / TAU * N, N))
		if rs[ia] > D + 12.0 * dpr:
			continue
		var size: float = (1.5 + sat[2] * 7.5) * dpr * (0.6 + 0.4 * minf(1.0, D / (far * 0.5))) * g
		var x: float = ox + cos(sat[0]) * D
		var y: float = oy + sin(sat[0]) * D
		var P := PackedVector2Array()
		for j in 10:
			var a := float(j) / 10 * TAU
			var rr: float = size * (1.0 + 0.28 * sin(a * 3.0 + sat[2] * 9.0) + 0.12 * sin(a * 5.0 + sat[2] * 4.0))
			P.append(Vector2(x + cos(a) * rr, y + sin(a) * rr))
		pt.fill(P, sc)


## Paper hairs left standing across the edge, and a fine spray of ink thrown just inside
## the opening (over the stage).
func draw_over(pt: PagePainter, t: PageTones) -> void:
	if not active:
		return
	var hc := PageTones.alpha(PageTones.mix(t.paper, t.paper_shade, 0.35), 0.55)
	var w := maxf(0.5, 0.6 * dpr)
	for hr in hairs:
		var i := floori(fposmod(hr[0] / TAU * N, N))
		var a := float(i) / N * TAU
		var r := rs[i]
		if r < 6.0 * dpr:
			continue
		var length: float = (2.5 + hr[1] * 6.0) * dpr
		var c := cos(a + hr[3] * 0.08)
		var s := sin(a + hr[3] * 0.08)
		var r0 := r + 2.0 * dpr
		var r1 := r - length
		var pa := PagePath.new()
		pa.move_to(ox + c * r0, oy + s * r0)
		pa.quad_to(ox + c * (r0 + r1) * 0.5 - s * hr[2] * length * 0.4, oy + s * (r0 + r1) * 0.5 + c * hr[2] * length * 0.4, ox + c * r1, oy + s * r1)
		pt.stroke(pa.subpath(0), w, hc)
	if wipe < 0.85:
		var fade := 1.0 - wipe / 0.85
		var sc := PageTones.alpha(t.ink, 0.75 * fade)
		for j in 40:
			var a := PageRand.hash01(j, 41) * TAU
			var i := floori(fposmod(a / TAU * N, N))
			var r := rs[i] - (4.0 + PageRand.hash01(j, 42) * 26.0) * dpr
			if r < 4.0 * dpr:
				continue
			var s := (0.6 + PageRand.hash01(j, 43) * 1.6) * dpr
			pt.dot(ox + cos(a) * r, oy + sin(a) * r, s, sc)

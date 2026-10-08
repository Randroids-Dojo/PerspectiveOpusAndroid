// A menu card, like the web build's .card: a translucent panel over a blurred backdrop,
// a 1 px edge, an inner rule 7 px in, gilt dots in the corners and CSS box shadows
// (drawn only outside the card, as the browser does). `k` blends the Stage look (1)
// with the Score look (0).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 card_pos;
uniform vec2 card_size;
uniform vec4 card_color : source_color;
uniform vec4 edge_color : source_color;
uniform vec4 accent : source_color;
uniform float blur_lod = 0.0;
uniform float k = 1.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float erf_approx(float x) {
	float s = sign(x);
	float a = abs(x);
	float t = 1.0 + (0.278393 + (0.230389 + 0.078108 * a * a) * a) * a;
	t *= t;
	return s - s / (t * t);
}

// A box blurred by a gaussian of the given standard deviation (CSS blur radius / 2).
float box_shadow(vec2 p, vec2 lo, vec2 hi, float sigma) {
	vec2 a = (p - lo) / (sigma * 1.41421356);
	vec2 b = (p - hi) / (sigma * 1.41421356);
	return 0.25 * (erf_approx(a.x) - erf_approx(b.x)) * (erf_approx(a.y) - erf_approx(b.y));
}

vec4 over(vec4 base, vec4 top) {
	float a = top.a + base.a * (1.0 - top.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	vec3 rgb = (top.rgb * top.a + base.rgb * base.a * (1.0 - top.a)) / a;
	return vec4(rgb, a);
}

float band(float e, float e0, float e1, float fw) {
	return clamp((e - e0) / fw + 0.5, 0.0, 1.0) - clamp((e - e1) / fw + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 centre = card_pos + half_size;
	vec2 d = abs(lp - centre) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	float fw = max(fwidth(sd), 1e-4);
	float cov = clamp(0.5 - sd / fw, 0.0, 1.0);
	float e = -sd;

	vec4 inside;
	if (blur_lod > 0.0) {
		vec3 bg = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
		inside = vec4(mix(bg, card_color.rgb, card_color.a), 1.0);
	} else {
		inside = card_color;
	}
	// Stage only: a faint warm line just inside the edge.
	inside = over(inside, vec4(1.0, 0.902, 0.706, 0.06 * k * band(e, 1.0, 2.0, fw)));
	inside = over(inside, vec4(edge_color.rgb, edge_color.a * 0.45 * band(e, 8.0, 9.0, fw)));
	inside = over(inside, vec4(edge_color.rgb, edge_color.a * band(e, 0.0, 1.0, fw)));
	// Each dot is a radial gradient centred on its box's corner, so only the quarter
	// towards the middle of the card shows.
	vec2 q = abs(lp - centre) - (half_size - vec2(5.0));
	float r = length(q);
	float quarter = step(q.x, 0.0) * step(q.y, 0.0);
	inside = over(inside, vec4(accent.rgb, 0.8 * quarter * clamp(3.0 - r, 0.0, 1.0)));

	vec4 sh = vec4(0.0);
	float hard = clamp(0.5 - (length(max(abs(lp - centre - vec2(6.0, 8.0)) - half_size, 0.0))) / fw, 0.0, 1.0);
	sh = over(sh, vec4(0.165, 0.125, 0.106, 0.08 * (1.0 - k) * hard));
	sh = over(sh, vec4(0.235, 0.157, 0.078, 0.28 * (1.0 - k) * box_shadow(lp, card_pos + vec2(0.0, 18.0), card_pos + card_size + vec2(0.0, 18.0), 25.0)));
	sh = over(sh, vec4(0.0, 0.0, 0.0, 0.55 * k * box_shadow(lp, card_pos + vec2(0.0, 30.0), card_pos + card_size + vec2(0.0, 30.0), 40.0)));

	vec4 pa = vec4(sh.rgb * sh.a, sh.a);
	vec4 pb = vec4(inside.rgb * inside.a, inside.a);
	vec4 m = mix(pa, pb, cov);
	COLOR = m.a > 0.0 ? vec4(m.rgb / m.a, m.a) : vec4(0.0);
}

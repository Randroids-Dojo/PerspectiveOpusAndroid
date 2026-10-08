// The Stage's final pass (the web Stage's COMPOSITE): bloom, exposure, ACES (three.js's fit),
// sRGB, a per-palette lift/gamma/gain grade, saturation, contrast, a slightly oval vignette,
// film grain and a dither. At low quality only exposure, ACES and sRGB, like the web build's
// renderer tone mapping. Writes display values straight into the (sRGB) root canvas.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D scene : filter_linear, repeat_disable;
uniform sampler2D bloom_tex : filter_linear, repeat_disable;
uniform float bloom = 0.6;
uniform float exposure = 1.0;
uniform vec3 lift = vec3(0.0);
uniform vec3 gamma = vec3(1.0);
uniform vec3 gain = vec3(1.0);
uniform float sat = 1.0;
uniform float contrast = 1.0;
uniform float vignette = 0.3;
uniform float grain = 0.03;
uniform float time = 0.0;
uniform vec2 res = vec2(1.0);
uniform bool has_bloom = true;
uniform bool full = true;

vec3 rrt_odt_fit(vec3 v) {
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return a / b;
}

vec3 aces(vec3 color) {
	const mat3 IN = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
	const mat3 OUT = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
	color = IN * (color / 0.6);
	color = rrt_odt_fit(color);
	return clamp(OUT * color, 0.0, 1.0);
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(scene, uv).rgb;
	if (has_bloom) c += texture(bloom_tex, uv).rgb * bloom;
	c = aces(max(c, vec3(0.0)) * exposure);
	c = to_srgb(c);
	if (full) {
		// The web build's uv has y up; only the vignette and noise use it, both symmetric or random.
		c = gain * (c + lift * (1.0 - c));
		c = pow(max(c, vec3(0.0)), 1.0 / gamma);
		float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(vec3(l), c, sat);
		c = (c - 0.5) * contrast + 0.5;
		vec2 q = (uv - 0.5) * vec2(res.x / res.y, 1.0) * 0.9;
		float v = smoothstep(0.25, 1.05, length(q));
		c *= 1.0 - v * vignette;
		float gr = hash(uv * res + fract(time * 13.17) * 97.0) - 0.5;
		c += gr * grain * (0.4 + 0.6 * (1.0 - abs(l - 0.5) * 2.0));
		c += (hash(uv * res + 3.7) - 0.5) / 255.0;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

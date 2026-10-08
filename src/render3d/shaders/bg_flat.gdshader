// Backdrop silhouettes and lit windows (the web Stage's FLAT_VERT / FLAT_FRAG): flat colour
// from CUSTOM0 with a brush texture, mist rising towards the ground and a glow towards the sun.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 mist;
uniform float mist_top = 0.0;
uniform float mist_bottom = -10.0;
uniform float mist_rise = 0.04;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 sun_glow;

varying vec3 v_col;
varying float v_y;
varying float v_dist;
varying vec3 v_wp;

float bhash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bhash(i), bhash(i + vec2(1.0, 0.0)), f.x), mix(bhash(i + vec2(0.0, 1.0)), bhash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_col = CUSTOM0.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wp = wp;
	v_y = wp.y;
	v_dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
}

void fragment() {
	float rise = v_dist * mist_rise;
	float m = 1.0 - smoothstep(mist_bottom + rise * 0.5, mist_top + rise, v_y);
	float sc = 1.0 / (1.0 + v_dist * 0.012);
	float n = bnoise(v_wp.xy * 0.45 * sc) * 0.6 + bnoise(v_wp.xy * 1.7 * sc + 13.0) * 0.4;
	vec3 c = v_col * (0.92 + 0.16 * n);
	c = mix(c, mist, m);
	vec3 vd = normalize(v_wp - CAMERA_POSITION_WORLD);
	float gl = pow(max(dot(vd, sun_dir), 0.0), 5.0);
	c += sun_glow * gl * (0.35 + 0.65 * smoothstep(20.0, 400.0, v_dist));
	ALBEDO = c;
}

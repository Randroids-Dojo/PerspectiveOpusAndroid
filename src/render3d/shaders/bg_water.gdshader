// The backdrop water (WATER_VERT / WATER_FRAG): fresnel sky reflection, sun glints, haze.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 deep;
uniform vec3 sky;
uniform vec3 horizon;
uniform vec3 sun_dir;
uniform vec3 sun_color;
uniform vec3 fog;
uniform float time = 0.0;
uniform float fog_dist = 200.0;

varying vec3 v_w;

vec2 wave(vec2 p, float t) {
	vec2 gg = vec2(0.0);
	gg += vec2(cos(p.x * 0.9 + t * 0.7), 0.0) * 0.5;
	gg += vec2(0.0, cos(p.y * 1.3 - t * 0.9)) * 0.4;
	gg += vec2(cos((p.x + p.y) * 2.1 + t * 1.3)) * 0.18;
	gg += vec2(cos((p.x * 3.7 - p.y * 2.9) + t * 1.9), sin(p.y * 3.1 + t * 1.7)) * 0.1;
	return gg;
}

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 v = normalize(cam - v_w);
	float dist = length(cam - v_w);
	vec2 gg = wave(v_w.xz * 0.6, time) * 0.06;
	vec3 n = normalize(vec3(-gg.x, 1.0, -gg.y));
	float fres = pow(1.0 - max(dot(n, v), 0.0), 4.0);
	vec3 r = reflect(-v, n);
	vec3 sk = mix(horizon, sky, smoothstep(0.0, 0.4, r.y));
	vec3 c = mix(deep, sk, 0.25 + 0.7 * fres);
	float spec = pow(max(dot(r, sun_dir), 0.0), 260.0) * 2.5 + pow(max(dot(r, sun_dir), 0.0), 24.0) * 0.12;
	c += sun_color * spec;
	float f = 1.0 - exp(-dist / fog_dist);
	c = mix(c, fog, f * 0.9);
	ALBEDO = c;
}

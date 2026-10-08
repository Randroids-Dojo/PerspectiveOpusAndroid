// Ambient particles (AMB_VERT / AMB_FRAG): motes, mist, leaves, petals, fireflies, sparks,
// embers, wrapped in a box that follows the camera focus, animated entirely here.
// MultiMesh: INSTANCE_CUSTOM = aSeed.

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform float time = 0.0;
uniform vec3 box_min;
uniform vec3 box_size = vec3(44.0, 16.0, 28.0);
uniform vec3 vel;
uniform float wobble = 0.3;
uniform float size = 0.06;
uniform float spin = 0.0;
uniform float kind = 0.0;
uniform float cell = 0.0;
uniform vec3 col_a;
uniform vec3 col_b;
uniform float alpha = 1.0;

varying vec2 v_uv;
varying float v_a;
varying float v_tone;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float sp = 0.6 + seed.w * 0.8;
	vec3 drift = vel * time * sp;
	float ph = seed.w * 40.0;
	vec3 wob = vec3(sin(time * 0.7 + ph), sin(time * 0.9 + ph * 1.3) * 0.6, cos(time * 0.6 + ph * 0.7)) * wobble;
	vec3 p = seed.xyz * box_size + drift + wob;
	p = mod(p - box_min, box_size) + box_min;
	vec3 e = min(p - box_min, box_min + box_size - p) / (box_size * 0.12);
	float edge = clamp(min(e.x, min(e.y, e.z)), 0.0, 1.0);
	float tw = 1.0;
	if (kind > 0.5 && kind < 1.5) tw = smoothstep(0.2, 1.0, sin(time * (1.5 + seed.w * 2.0) + ph));
	if (kind > 1.5 && kind < 2.5) tw = 0.5 + 0.5 * sin(time * 3.0 + ph);
	if (kind > 2.5) tw = 0.7 + 0.3 * sin(time * 2.0 + ph);
	v_a = edge * tw;
	v_tone = fract(seed.w * 7.13);
	// The multimesh instance transform is the identity: MODEL_MATRIX is the mirrored world node.
	vec4 mv = VIEW_MATRIX * (MODEL_MATRIX * vec4(p, 1.0));
	float rot = spin * (time * (0.5 + seed.w) + ph);
	float c = cos(rot);
	float s = sin(rot);
	float sz = size * (0.6 + seed.w * 0.8);
	vec2 q = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y) * sz;
	if (spin > 0.0) q.x *= 0.55 + 0.45 * sin(time * 3.0 + ph);
	mv.xy += q;
	VERTEX = mv.xyz;
	v_uv = (vec2(mod(cell, 4.0), 3.0 - floor(cell / 4.0)) + UV) / 4.0;
}

void fragment() {
	vec4 t = texture(tex, v_uv);
	vec3 c = mix(col_a, col_b, v_tone) * t.rgb;
	float a = t.a * v_a * alpha;
	if (a < 0.004) discard;
	ALBEDO = c;
	ALPHA = a;
}

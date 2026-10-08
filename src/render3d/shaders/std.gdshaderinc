// three.js MeshStandardMaterial / MeshPhysicalMaterial as the web Stage configures them,
// with the shared patch (cutout, height fog, wind) and the stage's special cases:
//   VCOLOR      vertex colours (CUSTOM0.rgb), times the MultiMesh instance colour
//   TUFT        flora tufts: bend in the wind and away from Quaver, lit as the ground
//   HOT         thorns and cogs: glowing tips (CUSTOM0.a) and spinning cogs (CUSTOM1)
//   DRUMHEAD    the timpani skin ripples after a bounce
//   GATE        staff gates dissolve and glow from aWind.y (CUSTOM1.y)
// Every mesh here lives inside the Stage's mirrored world node (scale z = -1).

#include "res://src/render3d/shaders/pbr.gdshaderinc"

uniform vec3 color = vec3(1.0);
uniform float roughness = 1.0;
uniform float metalness = 0.0;
/// emissive * emissiveIntensity (linear).
uniform vec3 emissive = vec3(0.0);
uniform bool use_fog = true;

varying vec3 v_color;
varying float v_mirror;

#ifdef HOT
uniform vec3 hot_color = vec3(0.0);
varying float v_hot;
#endif

#ifdef DRUMHEAD
uniform float hit = 9.0;
#endif

#ifdef GATE
uniform float vis = 1.0;
uniform float glow = 1.0;
uniform vec4 sweep = vec4(0.0);
varying vec3 v_gate_p;
varying float v_gate_glow;
float gate_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
#endif

void vertex() {
	// three.js draws shadows with a plain depth material: no sway, spin or ripple there.
	bool in_shadow = PROJECTION_MATRIX[3][3] > 0.5;
	v_mirror = determinant(mat3(MODEL_MATRIX)) < 0.0 ? -1.0 : 1.0;
	v_color = vec3(1.0);
#ifdef VCOLOR
	v_color = CUSTOM0.rgb * COLOR.rgb;
#endif
#ifdef WIND
	if (!in_shadow) VERTEX += wind_offset(VERTEX, CUSTOM1.xy);
#endif
#ifdef TUFT
	if (!in_shadow) {
		// The instance transform in simulation space (the world node only mirrors z).
		mat4 im = MODEL_MATRIX;
		im[0].z = -im[0].z;
		im[1].z = -im[1].z;
		im[2].z = -im[2].z;
		im[3].z = -im[3].z;
		vec3 root = im[3].xyz;
		float hgt = clamp(VERTEX.y / 0.3, 0.0, 1.0);
		float k = hgt * hgt;
		float t = g_time();
		float ph = t * 1.9 + root.x * 0.7 + root.z * 0.45;
		float gust = 0.6 + 0.4 * sin(t * 0.41 + root.x * 0.07);
		vec3 off = vec3(sin(ph) * 0.05, 0.0, cos(ph * 0.8) * 0.03) * gust * g_wind();
		vec3 away = root - g_player();
		float d = length(away.xz);
		float push = (1.0 - smoothstep(0.15, 0.7, d)) * step(abs(away.y), 0.5);
		off.xz += normalize(away.xz + vec2(1e-4)) * push * 0.16;
		off.y -= push * 0.06;
		mat3 r = mat3(im[0].xyz, im[1].xyz, im[2].xyz);
		vec3 lo = transpose(r) * off / max(0.001, dot(r[0], r[0]));
		VERTEX += lo * k;
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
#endif
#ifdef HOT
	v_hot = CUSTOM0.a;
	if (!in_shadow) {
		vec4 spin = CUSTOM1;
		float sim_x = MODEL_MATRIX[3].x;
		float spin_dir = mod(floor(sim_x + 0.01), 2.0) < 0.5 ? 1.0 : -1.0;
		float a = g_time() * spin.z * spin_dir + spin.w + (spin_dir < 0.0 ? 0.31 : 0.0);
		float c = cos(a);
		float s = sin(a);
		mat2 m = mat2(vec2(c, s), vec2(-s, c));
		NORMAL.xy = m * NORMAL.xy;
		VERTEX.xy = spin.xy + m * (VERTEX.xy - spin.xy);
	}
#endif
#ifdef DRUMHEAD
	if (!in_shadow) {
		float rr = length(VERTEX.xy);
		float env = exp(-hit * 4.0) * (1.0 - rr / 0.43);
		VERTEX.z += (-0.05 * exp(-hit * 9.0) + sin(rr * 32.0 - hit * 38.0) * 0.018) * env;
	}
#endif
#ifdef GATE
	v_gate_p = VERTEX;
	v_gate_glow = CUSTOM1.y;
#endif
}

void fragment() {
	vec3 n = normalize(NORMAL);
#ifdef DOUBLE_SIDED
	// Godot decides the side from the screen winding, which the mirror reverses.
	n *= v_mirror;
#endif
#ifdef TUFT
	// Blades are lit like the ground on both sides: undo the side flip entirely.
	if (!FRONT_FACING) n = -n;
#endif
#ifdef FLAT_SHADED
	n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
#endif
	float view_z = -VERTEX.z;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bool in_shadow = PROJECTION_MATRIX[3][3] > 0.5;
#ifdef CUTOUT
	if (!in_shadow && cut_away(FRAGCOORD.xy, view_z, wpos.y)) discard;
#endif
	vec3 emis = emissive;
	float metal = metalness;
#ifdef GATE
	float gate_edge = 0.0;
	{
		float hn = gate_hash(floor(v_gate_p * 11.0));
		float s = clamp(dot(v_gate_p, sweep.xyz) + sweep.w, 0.0, 1.0);
		float kk = hn * 0.45 + s * 0.55;
		float thr = vis * 1.2 - 0.04;
		if (kk > thr && !in_shadow) discard;
		gate_edge = 1.0 - smoothstep(0.0, 0.06, thr - kk);
	}
	metal *= 1.0 - clamp(v_gate_glow - 0.5, 0.0, 1.0);
	emis = v_color * v_gate_glow * glow + vec3(1.0, 0.62, 0.22) * gate_edge * 2.0;
#endif
#ifdef HOT
	metal *= 1.0 - v_hot * v_hot;
	emis += hot_color * pow(v_hot, 3.0);
#endif
	vec3 albedo = color * v_color;
	PBR pm = pbr_setup(albedo, roughness, metal, n, n, VIEW);
	vec3 ind_d;
	vec3 ind_s;
	vec3 extra;
	pbr_indirect(pm, n, VIEW, VIEW_MATRIX, INV_VIEW_MATRIX, ind_d, ind_s, extra);
	float k;
	vec3 b;
#ifdef HFOG
	fog_terms(view_z, wpos.y, use_fog, true, k, b);
#else
	fog_terms(view_z, wpos.y, use_fog, false, k, b);
#endif
	PBR_STORE(pm, k, 1.0, wpos)
	vec3 c = ind_d + ind_s + emis;
	c *= pm.cc_scale;
	c += extra;
	EMISSION = c * k + b;
	ALBEDO = vec3(1.0);
	NORMAL = n;
}

// The voxel blocks: a port of the web Stage's WorldMaterial. Detail layers from a texture
// array tint between each material's two palette colours, convex edges are bevelled and
// worn in the shader from per-face edge flags, capped tops take the palette's grass,
// moss, leaves, snow or carpet, and per-vertex ambient occlusion darkens the corners.
// CUSTOM0 is aInfo: layer, AO, edge bits, cap flag. Positions are in simulation space.
shader_type spatial;
render_mode cull_back, ambient_light_disabled, fog_disabled;
#define CUTOUT
#define HFOG
#include "res://src/render3d/shaders/pbr.gdshaderinc"

const float VARIANTS = 4.0;

uniform sampler2DArray detail_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 col1[8];
uniform vec3 col2[8];
uniform vec3 grout[8];
uniform vec4 props[8];
uniform vec3 emis[8];
uniform vec3 cap1;
uniform vec3 cap2;
uniform vec3 cap_grout;
uniform float cap_layer;
uniform float cap_on;
uniform vec4 cap_style;
uniform float glow_pulse = 1.0;
uniform float macro[8];
uniform float macro_layer;

varying vec2 v_luv;
varying vec4 v_info;
varying vec3 v_sim;
varying vec3 v_obj_n;

void vertex() {
	v_luv = UV;
	v_info = CUSTOM0;
	v_sim = VERTEX;
	v_obj_n = NORMAL;
}

void fragment() {
	float view_z = -VERTEX.z;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bool in_shadow = PROJECTION_MATRIX[3][3] > 0.5;
	if (!in_shadow && cut_away(FRAGCOORD.xy, view_z, wpos.y)) discard;
	vec3 n0 = normalize(NORMAL);

	float layer = floor(v_info.x + 0.5);
	int mi = int(floor(layer / VARIANTS + 0.01));
	vec4 det = texture(detail_arr, vec3(v_luv, layer));
	vec4 pr = props[mi];
	vec2 muv = abs(v_obj_n.y) > 0.5 ? v_sim.xz : vec2(v_sim.x + v_sim.z, v_sim.y);
	float mac = texture(detail_arr, vec3(muv * 0.083, macro_layer)).b * 0.6 + texture(detail_arr, vec3(muv * 0.29 + 0.37, macro_layer)).b * 0.4;
	det.r = clamp(det.r + (mac - 0.5) * macro[mi] * 1.6, 0.0, 1.0);
	float bits = floor(v_info.z + 0.5);
	float w = pr.z;
	float k_nu = mod(bits, 2.0) * pow(1.0 - smoothstep(0.0, w, v_luv.x), 1.6);
	float k_pu = mod(floor(bits / 2.0), 2.0) * pow(1.0 - smoothstep(0.0, w, 1.0 - v_luv.x), 1.6);
	float k_nv = mod(floor(bits / 4.0), 2.0) * pow(1.0 - smoothstep(0.0, w, v_luv.y), 1.6);
	float k_pv = mod(floor(bits / 8.0), 2.0) * pow(1.0 - smoothstep(0.0, w, 1.0 - v_luv.y), 1.6);
	vec2 bevel = vec2(k_pu - k_nu, k_pv - k_nv);
	float wear = max(max(k_nu, k_pu), max(k_nv, k_pv));
	vec3 alb = mix(col1[mi], col2[mi], det.r) * (0.55 + 0.9 * det.g) * (1.0 + (mac - 0.5) * 0.35 * macro[mi]);
	alb = mix(alb, grout[mi], det.a);
	float chip = smoothstep(0.3, 0.8, wear + (det.b - 0.5) * 0.9);
	alb = mix(alb, alb * 1.22 + 0.015, chip * 0.55);
	float cap = 0.0;
	vec3 cap_n = vec3(0.0, 0.0, 1.0);
	if (cap_on > 0.5 && v_info.w > 0.5) {
		bool top = v_obj_n.y > 0.5;
		vec2 cuv = top ? v_sim.xz * 0.5 : vec2((v_sim.x + v_sim.z) * 0.5, v_sim.y * 0.5);
		vec4 cd = texture(detail_arr, vec3(cuv, cap_layer));
		cap_n = texture(normal_arr, vec3(cuv, cap_layer)).xyz * 2.0 - 1.0;
		if (top) {
			cap = 1.0;
		} else {
			float depth = cap_style.x * (0.45 + cd.b * 1.1);
			cap = 1.0 - smoothstep(depth - 0.02, depth + 0.02, 1.0 - v_luv.y);
		}
		float cm = clamp(cd.r + (mac - 0.5) * 1.4, 0.0, 1.0);
		vec3 cc = mix(cap1, cap2, cm) * (0.55 + 0.9 * cd.g) * (0.9 + mac * 0.2);
		cc = mix(cc, cap_grout, cd.a);
		alb = mix(alb, cc, cap);
	}
	float ao = v_info.y;

	float rough = clamp(pr.x + (det.b - 0.5) * 0.45, 0.05, 1.0);
	rough = mix(rough, cap_style.y, cap);
	float metal = pr.y * (1.0 - cap) * (1.0 - det.a * 0.8);

	vec3 tn = texture(normal_arr, vec3(v_luv, layer)).xyz * 2.0 - 1.0;
	tn.xy *= pr.w;
	tn = mix(tn, cap_n * vec3(1.4, 1.4, 1.0), cap);
	tn.xy += bevel * 1.1;
	// The face's u and v axes in view space (three.js passes them as varyings).
	vec3 tuo = abs(v_obj_n.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : (abs(v_obj_n.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
	vec3 tvo = abs(v_obj_n.y) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	mat3 nm = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX;
	vec3 n = normalize(normalize(nm * tuo) * tn.x + normalize(nm * tvo) * tn.y + n0 * max(tn.z, 0.2));

	vec3 em = emis[mi] * (0.2 + det.a * det.a * 1.8) * (1.0 - cap) * glow_pulse;

	PBR pm = pbr_setup(alb, rough, metal, n, n0, VIEW);
	vec3 ind_d;
	vec3 ind_s;
	vec3 extra;
	pbr_indirect(pm, n, VIEW, VIEW_MATRIX, INV_VIEW_MATRIX, ind_d, ind_s, extra);
	float k;
	vec3 b;
	fog_terms(view_z, wpos.y, true, true, k, b);
	PBR_STORE(pm, k, mix(0.72, 1.0, ao), wpos)
	EMISSION = (ind_d * ao + ind_s * mix(1.0, ao, 0.8) + em) * k + b;
	ALBEDO = vec3(1.0);
	NORMAL = n;
}

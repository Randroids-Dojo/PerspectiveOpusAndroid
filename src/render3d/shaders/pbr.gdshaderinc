// three.js r186 MeshStandardMaterial / MeshPhysicalMaterial lighting, as the web Stage
// uses it, plus the features its shared patch adds (occlusion cutout, height fog and
// waterline, wind). Direct light runs in light() from the varyings fragment() leaves;
// indirect light (hemisphere, PMREM environment) and emission are computed in fragment()
// and written to EMISSION. Godot's own ambient, reflections and fog are off, ALBEDO is 1
// and METALLIC 0, so the engine adds exactly EMISSION + DIFFUSE_LIGHT. Distance fog and
// the height fog are linear in the lit colour (c * K + B): EMISSION takes B and every
// term is multiplied by K, which reaches light() as a varying.
//
// Options a shader defines before including this:
//   CUTOUT HFOG WIND        the shared patch
//   DOUBLE_SIDED            normals follow the face, as three.js does
//   CLEARCOAT SHEEN IRIDESCENCE FLAT_SHADED
// Materials hand their state to light() with PBR_STORE (see below).

#include "res://src/render3d/shaders/globals.gdshaderinc"

uniform sampler2D env_map : filter_linear, repeat_disable;
uniform sampler2D dfg_lut : filter_linear, repeat_disable;
/// texel width, texel height, max mip of the PMREM atlas.
uniform vec3 env_cube = vec3(0.0026041667, 0.001953125, 7.0);
uniform bool receive_shadow = true;

const float RECIPROCAL_PI = 0.3183098861837907;
const float EPSILON = 1e-6;

float pow2(float x) { return x * x; }
float pow4(float x) { float x2 = x * x; return x2 * x2; }
float max3(vec3 v) { return max(max(v.x, v.y), v.z); }

vec3 F_Schlick(vec3 f0, float f90, float dotVH) {
	float fresnel = exp2((-5.55473 * dotVH - 6.98316) * dotVH);
	return f0 * (1.0 - fresnel) + (f90 * fresnel);
}

float F_Schlick1(float f0, float f90, float dotVH) {
	float fresnel = exp2((-5.55473 * dotVH - 6.98316) * dotVH);
	return f0 * (1.0 - fresnel) + (f90 * fresnel);
}

float V_GGX_SmithCorrelated(float alpha, float dotNL, float dotNV) {
	float a2 = pow2(alpha);
	float gv = dotNL * sqrt(a2 + (1.0 - a2) * pow2(dotNV));
	float gl = dotNV * sqrt(a2 + (1.0 - a2) * pow2(dotNL));
	return 0.5 / max(gv + gl, EPSILON);
}

float D_GGX(float alpha, float dotNH) {
	float a2 = pow2(alpha);
	float denom = pow2(dotNH) * (a2 - 1.0) + 1.0;
	return RECIPROCAL_PI * a2 / pow2(denom);
}

// ---------------------------------------------------------------- cube UV (PMREM) sampling

float cube_face(vec3 direction) {
	vec3 a = abs(direction);
	float face = -1.0;
	if (a.x > a.z) {
		if (a.x > a.y) face = direction.x > 0.0 ? 0.0 : 3.0;
		else face = direction.y > 0.0 ? 1.0 : 4.0;
	} else {
		if (a.z > a.y) face = direction.z > 0.0 ? 2.0 : 5.0;
		else face = direction.y > 0.0 ? 1.0 : 4.0;
	}
	return face;
}

vec2 cube_uv(vec3 direction, float face) {
	vec2 uv;
	if (face == 0.0) uv = vec2(direction.z, direction.y) / abs(direction.x);
	else if (face == 1.0) uv = vec2(-direction.x, -direction.z) / abs(direction.y);
	else if (face == 2.0) uv = vec2(-direction.x, direction.y) / abs(direction.z);
	else if (face == 3.0) uv = vec2(-direction.z, direction.y) / abs(direction.x);
	else if (face == 4.0) uv = vec2(-direction.x, direction.z) / abs(direction.y);
	else uv = vec2(direction.x, direction.y) / abs(direction.z);
	return 0.5 * (uv + 1.0);
}

vec3 bilinear_cube_uv(vec3 direction, float mip_int) {
	float face = cube_face(direction);
	float filter_int = max(4.0 - mip_int, 0.0);
	mip_int = max(mip_int, 4.0);
	float face_size = exp2(mip_int);
	vec2 uv = cube_uv(direction, face) * (face_size - 2.0) + 1.0;
	if (face > 2.0) {
		uv.y += face_size;
		face -= 3.0;
	}
	uv.x += face * face_size;
	uv.x += filter_int * 3.0 * 16.0;
	uv.y += 4.0 * (exp2(env_cube.z) - face_size);
	uv.x *= env_cube.x;
	uv.y *= env_cube.y;
	return textureLod(env_map, uv, 0.0).rgb;
}

float roughness_to_mip(float roughness) {
	float mip = 0.0;
	if (roughness >= 0.8) mip = (1.0 - roughness) * (-1.0 + 2.0) / (1.0 - 0.8) - 2.0;
	else if (roughness >= 0.4) mip = (0.8 - roughness) * (2.0 + 1.0) / (0.8 - 0.4) - 1.0;
	else if (roughness >= 0.305) mip = (0.4 - roughness) * (3.0 - 2.0) / (0.4 - 0.305) + 2.0;
	else if (roughness >= 0.21) mip = (0.305 - roughness) * (4.0 - 3.0) / (0.305 - 0.21) + 3.0;
	else mip = -2.0 * log2(1.16 * roughness);
	return mip;
}

vec3 texture_cube_uv(vec3 dir, float roughness) {
	float mip = clamp(roughness_to_mip(roughness), -2.0, env_cube.z);
	float mip_f = fract(mip);
	float mip_int = floor(mip);
	vec3 c0 = bilinear_cube_uv(dir, mip_int);
	if (mip_f == 0.0) return c0;
	return mix(c0, bilinear_cube_uv(dir, mip_int + 1.0), mip_f);
}

// The environment is sampled in three.js world axes: the same as Godot's here.
vec3 ibl_irradiance(vec3 n_view, mat4 inv_view) {
	vec3 wn = normalize((inv_view * vec4(n_view, 0.0)).xyz);
	return PI * texture_cube_uv(wn, 1.0) * g_env_intensity();
}

vec3 ibl_radiance(vec3 v_view, vec3 n_view, float roughness, mat4 inv_view) {
	vec3 r = reflect(-v_view, n_view);
	r = normalize(mix(r, n_view, pow4(roughness)));
	r = normalize((inv_view * vec4(r, 0.0)).xyz);
	return texture_cube_uv(r, roughness) * g_env_intensity();
}

vec2 dfg(float roughness, float dot_nv) {
	return texture(dfg_lut, vec2(roughness, dot_nv)).rg;
}

void multiscatter(vec2 fab, vec3 spec_color, float f90, inout vec3 single_scatter, inout vec3 multi_scatter) {
	vec3 fr = spec_color;
	vec3 fss_ess = fr * fab.x + f90 * fab.y;
	float ess = fab.x + fab.y;
	float ems = 1.0 - ess;
	vec3 favg = fr + (1.0 - fr) * 0.047619;
	vec3 fms = fss_ess * favg / (1.0 - ems * favg);
	single_scatter += fss_ess;
	multi_scatter += fms * ems;
}

#ifdef SHEEN
float D_Charlie(float roughness, float dot_nh) {
	float alpha = pow2(roughness);
	float inv_alpha = 1.0 / alpha;
	float cos2h = dot_nh * dot_nh;
	float sin2h = max(1.0 - cos2h, 0.0078125);
	return (2.0 + inv_alpha) * pow(sin2h, inv_alpha * 0.5) / (2.0 * PI);
}

float V_Neubelt(float dot_nv, float dot_nl) {
	return clamp(1.0 / (4.0 * (dot_nl + dot_nv - dot_nl * dot_nv)), 0.0, 1.0);
}

float ibl_sheen_brdf(vec3 n, vec3 v, float roughness) {
	float dot_nv = clamp(dot(n, v), 0.0, 1.0);
	float r2 = roughness * roughness;
	float r_inv = 1.0 / (roughness + 0.1);
	float a = -1.9362 + 1.0678 * roughness + 0.4573 * r2 - 0.8469 * r_inv;
	float b = -0.6014 + 0.5538 * roughness - 0.4670 * r2 - 0.1255 * r_inv;
	return clamp(exp(a * dot_nv + b), 0.0, 1.0);
}
#endif

#ifdef IRIDESCENCE
const mat3 XYZ_TO_REC709 = mat3(vec3(3.2404542, -0.9692660, 0.0556434), vec3(-1.5371385, 1.8760108, -0.2040259), vec3(-0.4985314, 0.0415560, 1.0572252));

vec3 fresnel0_to_ior(vec3 f0) {
	vec3 s = sqrt(f0);
	return (vec3(1.0) + s) / (vec3(1.0) - s);
}

vec3 ior_to_fresnel0v(vec3 t, float i) { vec3 q = (t - vec3(i)) / (t + vec3(i)); return q * q; }
float ior_to_fresnel0(float t, float i) { return pow2((t - i) / (t + i)); }

vec3 eval_sensitivity(float opd, vec3 shift) {
	float phase = 2.0 * PI * opd * 1.0e-9;
	vec3 val = vec3(5.4856e-13, 4.4201e-13, 5.2481e-13);
	vec3 pos = vec3(1.6810e+06, 1.7953e+06, 2.2084e+06);
	vec3 var = vec3(4.3278e+09, 9.3046e+09, 6.6121e+09);
	vec3 xyz = val * sqrt(2.0 * PI * var) * cos(pos * phase + shift) * exp(-pow2(phase) * var);
	xyz.x += 9.7470e-14 * sqrt(2.0 * PI * 4.5282e+09) * cos(2.2399e+06 * phase + shift[0]) * exp(-4.5282e+09 * pow2(phase));
	xyz /= 1.0685e-7;
	return XYZ_TO_REC709 * xyz;
}

vec3 eval_iridescence(float outside_ior, float eta2, float cos_theta1, float thickness, vec3 base_f0) {
	float iri_ior = mix(outside_ior, eta2, smoothstep(0.0, 0.03, thickness));
	float sin_theta2_sq = pow2(outside_ior / iri_ior) * (1.0 - pow2(cos_theta1));
	float cos_theta2_sq = 1.0 - sin_theta2_sq;
	if (cos_theta2_sq < 0.0) return vec3(1.0);
	float cos_theta2 = sqrt(cos_theta2_sq);
	float r0 = ior_to_fresnel0(iri_ior, outside_ior);
	float r12 = F_Schlick1(r0, 1.0, cos_theta1);
	float t121 = 1.0 - r12;
	float phi12 = 0.0;
	if (iri_ior < outside_ior) phi12 = PI;
	float phi21 = PI - phi12;
	vec3 base_ior = fresnel0_to_ior(clamp(base_f0, 0.0, 0.9999));
	vec3 r1 = ior_to_fresnel0v(base_ior, iri_ior);
	vec3 r23 = F_Schlick(r1, 1.0, cos_theta2);
	vec3 phi23 = vec3(0.0);
	if (base_ior.x < iri_ior) phi23.x = PI;
	if (base_ior.y < iri_ior) phi23.y = PI;
	if (base_ior.z < iri_ior) phi23.z = PI;
	float opd = 2.0 * iri_ior * thickness * cos_theta2;
	vec3 phi = vec3(phi21) + phi23;
	vec3 r123 = clamp(r12 * r23, 1e-5, 0.9999);
	vec3 sr123 = sqrt(r123);
	vec3 rs = pow2(t121) * r23 / (vec3(1.0) - r123);
	vec3 c0 = r12 + rs;
	vec3 iv = c0;
	vec3 cm = rs - t121;
	for (int m = 1; m <= 2; ++m) {
		cm *= sr123;
		vec3 sm = 2.0 * eval_sensitivity(float(m) * opd, float(m) * phi);
		iv += cm * sm;
	}
	return max(iv, vec3(0.0));
}

vec3 schlick_to_f0(vec3 f, float f90, float dot_vh) {
	float x = clamp(1.0 - dot_vh, 0.0, 1.0);
	float x2 = x * x;
	float x5 = clamp(x * x2 * x2, 0.0, 0.9999);
	return (f - vec3(f90) * x5) / (1.0 - x5);
}

uniform float iridescence = 0.0;
uniform float iridescence_ior = 1.3;
uniform float iridescence_thickness = 400.0;
#endif

#ifdef CLEARCOAT
uniform float clearcoat = 0.0;
uniform float clearcoat_roughness = 0.0;
#endif

#ifdef SHEEN
uniform vec3 sheen_color = vec3(0.0);
uniform float sheen_roughness = 1.0;
#endif

// ---------------------------------------------------------------- material state for light()

/// The physical material as lights_physical_fragment sets it up.
struct PBR {
	vec3 diffuse;     // diffuseColor (albedo)
	vec3 contrib;     // diffuseContribution = albedo * (1 - metalness)
	vec3 spec_blend;  // specularColorBlended
	float rough;
	vec3 ms;          // multiScatteringCompensation
	vec2 fab;         // DFG at (roughness, n.v)
	float metal;
	vec3 cc_n;
	float cc_rough;
	float cc_scale;   // 1 - clearcoat * Fcc
	float iri;
	vec3 iri_fresnel;
};

// Fragment-to-light varyings, packed (Godot only lets the stage functions write them, and
// they count against the varying budget).
varying vec4 f_contrib_rough;   // diffuseContribution, roughness
varying vec4 f_spec_k;          // specularColorBlended, fog multiplier
varying vec4 f_ms_ao;           // multiScatteringCompensation, direct diffuse AO (block AO)
varying vec3 f_world;           // world position (spot light)
#ifdef CLEARCOAT
varying vec4 f_cc;              // clearcoat normal, clearcoat roughness
varying float f_cc_scale;
#endif
#ifdef IRIDESCENCE
varying vec4 f_iri;             // iridescence fresnel, iridescence
#endif

#ifdef CLEARCOAT
#define PBR_STORE_CC(q) f_cc = vec4(q.cc_n, q.cc_rough); f_cc_scale = q.cc_scale;
#else
#define PBR_STORE_CC(q)
#endif
#ifdef IRIDESCENCE
#define PBR_STORE_IRI(q) f_iri = vec4(q.iri_fresnel, q.iri);
#else
#define PBR_STORE_IRI(q)
#endif
/// Hands the material to light(); `k` is the fog multiplier, `ao` the direct diffuse AO.
#define PBR_STORE(q, k, ao, wp) f_contrib_rough = vec4(q.contrib, q.rough); f_spec_k = vec4(q.spec_blend, k); f_ms_ao = vec4(q.ms, ao); f_world = wp; PBR_STORE_CC(q) PBR_STORE_IRI(q)

/// Sets up the physical material (lights_physical_fragment + the start of lights_fragment_begin).
/// `n` is the shading normal, `n0` the normal before maps (both view space), `v` the view direction.
PBR pbr_setup(vec3 albedo, float roughness_factor, float metalness_factor, vec3 n, vec3 n0, vec3 v) {
	PBR m;
	m.diffuse = albedo;
	m.contrib = albedo * (1.0 - metalness_factor);
	m.metal = metalness_factor;
	vec3 dxy = max(abs(dFdx(n0)), abs(dFdy(n0)));
	float geometry_roughness = max(max(dxy.x, dxy.y), dxy.z);
	float r = max(roughness_factor, 0.0525);
	r += geometry_roughness;
	m.rough = min(r, 1.0);
	m.spec_blend = mix(vec3(0.04), albedo, metalness_factor);
	m.cc_n = n0;
	m.cc_rough = 0.0;
	m.cc_scale = 1.0;
#ifdef CLEARCOAT
	m.cc_rough = min(max(clearcoat_roughness, 0.0525) + geometry_roughness, 1.0);
	float dot_nv_cc = clamp(dot(m.cc_n, v), 0.0, 1.0);
	m.cc_scale = 1.0 - clamp(clearcoat, 0.0, 1.0) * F_Schlick1(0.04, 1.0, dot_nv_cc);
#endif
	m.iri = 0.0;
	m.iri_fresnel = vec3(0.0);
#ifdef IRIDESCENCE
	m.iri = clamp(iridescence, 0.0, 1.0);
	if (iridescence_thickness == 0.0) m.iri = 0.0;
#endif
	float dot_nv = clamp(dot(n, v), 0.0, 1.0);
	m.fab = dfg(m.rough, dot_nv);
	float ess = m.fab.x + m.fab.y;
	m.ms = 1.0 + m.spec_blend * (1.0 / ess - 1.0);
	return m;
}

/// Hemisphere and environment light: returns indirect diffuse and indirect specular, and the
/// clearcoat and sheen terms folded in the way meshphysical composes them (`extra`).
void pbr_indirect(inout PBR m, vec3 n, vec3 v, mat4 view_m, mat4 inv_view, out vec3 ind_diffuse, out vec3 ind_spec, out vec3 extra) {
	extra = vec3(0.0);
	// Hemisphere light: three.js keeps its direction in view space.
	vec3 up = normalize((view_m * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float w = 0.5 * dot(n, up) + 0.5;
	vec3 irradiance = mix(g_hemi_ground(), g_hemi_sky(), w);
	vec3 spec_color = vec3(0.04);
	float f90 = 1.0;
#ifdef IRIDESCENCE
	vec3 iri_f0_dielectric = spec_color;
	vec3 iri_f0_metallic = m.diffuse;
	if (m.iri > 0.0) {
		float dot_nvi = clamp(dot(n, v), 0.0, 1.0);
		vec3 fd = eval_iridescence(1.0, iridescence_ior, dot_nvi, iridescence_thickness, spec_color);
		vec3 fm = eval_iridescence(1.0, iridescence_ior, dot_nvi, iridescence_thickness, m.diffuse);
		m.iri_fresnel = mix(fd, fm, m.metal);
		iri_f0_dielectric = schlick_to_f0(fd, 1.0, dot_nvi);
		iri_f0_metallic = schlick_to_f0(fm, 1.0, dot_nvi);
	}
#endif
	// RE_IndirectDiffuse_Physical (hemisphere).
	vec3 s1 = vec3(0.0);
	vec3 m1 = vec3(0.0);
#ifdef IRIDESCENCE
	multiscatter(m.fab, mix(spec_color, iri_f0_dielectric, m.iri), f90, s1, m1);
#else
	multiscatter(m.fab, spec_color, f90, s1, m1);
#endif
	vec3 diffuse = irradiance * RECIPROCAL_PI * m.contrib * (1.0 - s1 - m1);
#ifdef SHEEN
	float sheen_albedo = ibl_sheen_brdf(n, v, sheen_roughness);
	extra += irradiance * sheen_color * sheen_albedo * RECIPROCAL_PI;
	float sheen_comp = 1.0 - max3(sheen_color) * sheen_albedo;
	diffuse *= sheen_comp;
#endif
	ind_diffuse = diffuse;
	// RE_IndirectSpecular_Physical (environment).
	vec3 radiance = ibl_radiance(v, n, m.rough, inv_view);
	vec3 ibl_irr = ibl_irradiance(n, inv_view);
#ifdef CLEARCOAT
	{
		vec3 cc_radiance = ibl_radiance(v, m.cc_n, m.cc_rough, inv_view);
		float dot_nv_cc = clamp(dot(m.cc_n, v), 0.0, 1.0);
		vec2 cfab = dfg(m.cc_rough, dot_nv_cc);
		extra += cc_radiance * (vec3(0.04) * cfab.x + cfab.y) * clamp(clearcoat, 0.0, 1.0);
	}
#endif
#ifdef SHEEN
	extra += ibl_irr * sheen_color * ibl_sheen_brdf(n, v, sheen_roughness) * RECIPROCAL_PI;
#endif
	vec3 sd = vec3(0.0);
	vec3 md = vec3(0.0);
	vec3 sm = vec3(0.0);
	vec3 mm = vec3(0.0);
#ifdef IRIDESCENCE
	multiscatter(m.fab, mix(spec_color, iri_f0_dielectric, m.iri), f90, sd, md);
	multiscatter(m.fab, mix(m.diffuse, iri_f0_metallic, m.iri), f90, sm, mm);
#else
	multiscatter(m.fab, spec_color, f90, sd, md);
	multiscatter(m.fab, m.diffuse, f90, sm, mm);
#endif
	vec3 single_s = mix(sd, sm, m.metal);
	vec3 multi_s = mix(md, mm, m.metal);
	vec3 diff2 = m.contrib * (1.0 - (sd + md));
	vec3 cos_irr = ibl_irr * RECIPROCAL_PI;
	vec3 spec = radiance * single_s + multi_s * cos_irr;
	vec3 diff3 = diff2 * cos_irr;
#ifdef SHEEN
	float sheen_comp2 = 1.0 - max3(sheen_color) * ibl_sheen_brdf(n, v, sheen_roughness);
	spec *= sheen_comp2;
	diff3 *= sheen_comp2;
#endif
	ind_diffuse += diff3;
	ind_spec = spec;
}

// ---------------------------------------------------------------- fog (three.js Fog, then the patch's height fog and waterline)

/// Returns K and B so that the fogged colour is c * K + B. `view_z` is the view depth, `wy` world y.
void fog_terms(float view_z, float wy, bool use_fog, bool use_hfog, out float k, out vec3 b) {
	k = 1.0;
	b = vec3(0.0);
	if (use_fog) {
		float f = smoothstep(g_fog_near(), g_fog_far(), view_z);
		k *= 1.0 - f;
		b = b * (1.0 - f) + g_fog_color() * f;
	}
	if (use_hfog) {
		vec4 hf = g(2);
		float h = (1.0 - smoothstep(hf.y, hf.x, wy)) * hf.z;
		k *= 1.0 - h;
		b = b * (1.0 - h) + g(3).rgb * h;
		float water_y = hf.w;
		if (water_y > -900.0) {
			float under = (1.0 - smoothstep(water_y - 1.6, water_y + 0.02, wy)) * 0.85;
			k *= 1.0 - under;
			b = b * (1.0 - under) + g(4).rgb * under;
			float foam = (1.0 - smoothstep(0.0, 0.05, abs(wy - water_y - 0.02))) * 0.35;
			k *= 1.0 - foam;
			b = b * (1.0 - foam) + (g(3).rgb * 1.1 + 0.04) * foam;
		}
	}
}

/// The shared occlusion cutout: dithers away fragments between the camera and Quaver.
bool cut_away(vec2 frag, float view_z, float wy) {
	vec4 a = g(0);
	vec4 c = g(1);
	float nearer = c.z - view_z;
	if (a.z > 0.0 && nearer > 0.3 && wy > c.w + 0.14) {
		vec2 d = (frag - c.xy) / a.w;
		d.y *= 0.82;
		float r = length(d);
		float fade = (1.0 - smoothstep(0.5, 1.0, r)) * smoothstep(0.3, 1.1, nearer) * a.z;
		float dither = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
		if (dither < fade * 0.88) return true;
	}
	return false;
}

/// Wind sway (the patch's WIND_VERT) on a local position, from the aWind attribute.
vec3 wind_offset(vec3 p, vec2 a_wind) {
	float w = a_wind.x * g_wind();
	if (w <= 0.0) return vec3(0.0);
	float t = g_time();
	float ph = t * 1.6 + p.x * 0.45 + p.z * 0.3 + a_wind.y;
	float gust = 0.65 + 0.35 * sin(t * 0.37 + p.x * 0.05);
	return vec3(sin(ph) * 0.07 * w * gust, sin(ph * 1.3) * 0.012 * w, cos(ph * 0.83) * 0.05 * w * gust);
}

// ---------------------------------------------------------------- direct light

void light() {
	vec3 n = NORMAL;
	vec3 v = VIEW;
	vec3 l = LIGHT;
	vec3 lcol;
	if (LIGHT_IS_DIRECTIONAL) {
		lcol = LIGHT_COLOR / PI * (receive_shadow ? ATTENUATION : 1.0);
	} else {
		// The spot key: three.js cone and distance falloff (it casts no shadow).
		vec4 sp = g(10);
		vec4 sd = g(11);
		vec4 sc = g(12);
		vec4 se = g(13);
		vec3 to = f_world - sp.xyz;
		float dist = length(to);
		float angle_cos = dot(to / max(dist, 1e-5), sd.xyz);
		float spot = smoothstep(sd.w, sc.w, angle_cos);
		lcol = sc.rgb * spot / max(pow(dist, se.x), 0.01) * sp.w;
	}
	float dot_nl = clamp(dot(n, l), 0.0, 1.0);
	vec3 irradiance = dot_nl * lcol;
	vec3 out_light = vec3(0.0);
	vec3 h = normalize(l + v);
	float dot_nv = clamp(dot(n, v), 0.0, 1.0);
	float dot_nh = clamp(dot(n, h), 0.0, 1.0);
	float dot_vh = clamp(dot(v, h), 0.0, 1.0);
#ifdef CLEARCOAT
	{
		vec3 ccn = f_cc.xyz;
		float dot_nl_cc = clamp(dot(ccn, l), 0.0, 1.0);
		float alpha_cc = pow2(f_cc.w);
		float dnv = clamp(dot(ccn, v), 0.0, 1.0);
		float dnh = clamp(dot(ccn, h), 0.0, 1.0);
		vec3 fcc = F_Schlick(vec3(0.04), 1.0, dot_vh);
		vec3 cc = dot_nl_cc * lcol * fcc * (V_GGX_SmithCorrelated(alpha_cc, dot_nl_cc, dnv) * D_GGX(alpha_cc, dnh));
		out_light += cc * clamp(clearcoat, 0.0, 1.0);
	}
#endif
#ifdef SHEEN
	{
		float d = D_Charlie(sheen_roughness, dot_nh);
		float vv = V_Neubelt(dot_nv, dot_nl);
		out_light += irradiance * sheen_color * (d * vv);
		float albedo_v = ibl_sheen_brdf(n, v, sheen_roughness);
		float albedo_l = ibl_sheen_brdf(n, l, sheen_roughness);
		irradiance *= 1.0 - max3(sheen_color) * max(albedo_v, albedo_l);
	}
#endif
	float alpha = pow2(f_contrib_rough.w);
	vec3 f = F_Schlick(f_spec_k.rgb, 1.0, dot_vh);
#ifdef IRIDESCENCE
	f = mix(f, f_iri.rgb, f_iri.w);
#endif
	vec3 spec = f * (V_GGX_SmithCorrelated(alpha, dot_nl, dot_nv) * D_GGX(alpha, dot_nh));
	vec3 base = irradiance * spec * f_ms_ao.rgb;
	vec3 f_d = F_Schlick(vec3(0.04), 1.0, dot_vh);
	base += irradiance * RECIPROCAL_PI * f_contrib_rough.rgb * (1.0 - f_d) * f_ms_ao.w;
#ifdef CLEARCOAT
	base *= f_cc_scale;
#endif
	DIFFUSE_LIGHT += (base + out_light) * f_spec_k.w;
}

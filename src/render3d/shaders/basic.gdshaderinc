// three.js MeshBasicMaterial as the web Stage uses it: colour x map x vertex colour,
// unlit, with the scene's linear fog (materials in the backdrop scene have none).
//   FLICKER      the props' glow material: flickers by the phase in aWind.y (CUSTOM1.y)
//   TRANSPARENT  writes alpha (the variant file picks the blend mode)
//   OFFSET       pulls the surface a little towards the camera (polygon offset)

#include "res://src/render3d/shaders/globals.gdshaderinc"

uniform vec3 color = vec3(1.0);
uniform float opacity = 1.0;
uniform sampler2D map_lin : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D map_srgb : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool srgb = false;
uniform bool use_fog = true;
uniform bool use_vcolor = false;

varying vec3 v_color;
#ifdef FLICKER
varying float v_flick;
#endif

void vertex() {
	v_color = use_vcolor ? CUSTOM0.rgb : vec3(1.0);
#ifdef FLICKER
	float ph = CUSTOM1.y;
	float t = g_time();
	v_flick = ph > 0.0 ? 0.82 + 0.18 * sin(t * 11.0 + ph * 17.0) * sin(t * 7.3 + ph * 5.0) : 1.0;
#endif
#ifdef OFFSET
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mv.xyz += normalize(-mv.xyz) * 0.012 * max(1.0, length(mv.xyz) * 0.02);
	POSITION = PROJECTION_MATRIX * mv;
#endif
}

void fragment() {
	vec4 t = srgb ? texture(map_srgb, UV) : texture(map_lin, UV);
	vec3 c = color * t.rgb * v_color;
#ifdef FLICKER
	c *= v_flick;
#endif
	if (use_fog) {
		float f = smoothstep(g_fog_near(), g_fog_far(), -VERTEX.z);
		c = mix(c, g_fog_color(), f);
	}
	ALBEDO = c;
#ifdef TRANSPARENT
	ALPHA = opacity * t.a;
#endif
}

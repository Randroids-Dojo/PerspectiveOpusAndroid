// An open gate's dotted ghost (GHOST_FRAG): red-marked parts dot along their length, the rest upwards.
shader_type spatial;
render_mode unshaded, cull_back, blend_add, depth_draw_never, fog_disabled;

uniform float opacity = 0.5;
uniform vec3 color;

varying vec3 v_w;
varying vec3 v_c;

void vertex() {
	v_w = VERTEX;
	v_c = CUSTOM0.rgb;
}

void fragment() {
	float d = v_c.r > 0.5 ? fract((v_w.x + v_w.z) * 2.5) : fract(v_w.y * 3.0);
	if (d > 0.5) discard;
	ALBEDO = color * opacity;
}

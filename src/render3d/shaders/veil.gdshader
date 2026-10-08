// The veil of light inside the Fermata arch (VEIL_FRAG): rising streaks, brighter as Quaver nears.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform float time = 0.0;
uniform float glow = 0.5;
uniform vec3 color;

varying vec3 v_p;

void vertex() {
	v_p = VERTEX;
}

void fragment() {
	float x = v_p.x;
	float y = v_p.y;
	float streak = 0.5 + 0.5 * sin(x * 14.0 + sin(y * 2.0 + time * 1.3) * 2.0 + time * 0.7);
	streak *= 0.6 + 0.4 * sin(x * 31.0 - time * 2.1);
	float rise = 0.5 + 0.5 * sin(y * 6.0 - time * 2.4 + x * 3.0);
	float edge = smoothstep(0.0, 0.35, 0.82 - abs(x)) * smoothstep(0.0, 0.5, y);
	float a = edge * (0.25 + 0.55 * streak * rise) * glow;
	ALBEDO = color * a;
}

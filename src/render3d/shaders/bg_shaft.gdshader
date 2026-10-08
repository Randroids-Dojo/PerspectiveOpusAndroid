// Light shafts in the backdrop (SHAFT_FRAG): soft additive beams that flicker slowly.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform vec3 color;
uniform float time = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.0, 0.35, uv.x) * smoothstep(1.0, 0.65, uv.x);
	float len = smoothstep(0.0, 0.5, uv.y) * smoothstep(1.0, 0.85, uv.y);
	float flick = 0.75 + 0.25 * sin(time * 0.6 + seed * 6.0 + uv.x * 5.0);
	ALBEDO = color * edge * len * flick;
}

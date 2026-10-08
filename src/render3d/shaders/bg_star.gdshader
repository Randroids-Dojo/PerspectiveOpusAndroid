// Stars (STAR_VERT / STAR_FRAG): twinkling points on the sky, fixed to the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled, skip_vertex_transform;

uniform vec3 color = vec3(0.737, 0.807, 1.0);
uniform float time = 0.0;
/// Point sizes are in backdrop pixels; scaled with the backdrop resolution.
uniform float point_scale = 1.0;

varying float v_a;

void vertex() {
	float seed = CUSTOM0.x;
	vec4 mv = VIEW_MATRIX * vec4(VERTEX + CAMERA_POSITION_WORLD, 1.0);
	float tw = 0.6 + 0.4 * sin(time * (1.0 + seed * 3.0) + seed * 40.0);
	v_a = tw * (0.4 + seed * 0.6) * smoothstep(0.02, 0.15, normalize(VERTEX).y);
	POINT_SIZE = (1.2 + seed * 2.2) * point_scale;
	VERTEX = mv.xyz;
}

void fragment() {
	vec2 p = POINT_COORD - 0.5;
	float a = smoothstep(0.5, 0.1, length(p)) * v_a;
	ALBEDO = color * 2.0;
	ALPHA = a;
}

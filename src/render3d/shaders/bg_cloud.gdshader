// Painted clouds (CLOUD_VERT / CLOUD_FRAG): camera-facing cards on the sky, drifting.
// MultiMesh: INSTANCE_CUSTOM = aCloud (offset from the camera, atlas cell), COLOR.xy = size.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled, skip_vertex_transform;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec3 lit;
uniform vec3 shade;
uniform float opacity = 0.9;
uniform float time = 0.0;

varying vec2 v_uv;
varying float v_fade;

void vertex() {
	vec4 cl = INSTANCE_CUSTOM;
	float cell = cl.w;
	v_uv = (UV + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	vec3 c = cl.xyz;
	float drift = mod(time * 2.0 + c.x * 7.0, 400.0) - 200.0;
	vec3 wp = c + vec3(drift, 0.0, 0.0);
	vec4 mv = VIEW_MATRIX * vec4(wp + CAMERA_POSITION_WORLD, 1.0);
	mv.xy += VERTEX.xy * COLOR.xy;
	v_fade = smoothstep(0.0, 120.0, c.y) * (1.0 - smoothstep(150.0, 200.0, abs(drift)));
	VERTEX = mv.xyz;
}

void fragment() {
	vec4 t = texture(tex, v_uv);
	ALBEDO = mix(shade, lit, t.r);
	ALPHA = t.a * opacity * v_fade;
}

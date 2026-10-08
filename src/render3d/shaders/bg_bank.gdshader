// Mist banks between the backdrop layers (BANK_VERT / BANK_FRAG).
// MultiMesh: INSTANCE_CUSTOM = aBank (position, atlas cell), COLOR.xy = size.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled, skip_vertex_transform;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec3 color;
uniform vec3 lit;
uniform float opacity = 0.5;
uniform float time = 0.0;

varying vec2 v_uv;
varying float v_shade;

void vertex() {
	vec4 b = INSTANCE_CUSTOM;
	float cell = b.w;
	v_uv = (UV + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	vec3 c = b.xyz + vec3(sin(time * 0.04 + b.x * 0.1) * 4.0, 0.0, 0.0);
	// The multimesh instance transform is the identity: MODEL_MATRIX is the mirrored layer node.
	vec4 mv = VIEW_MATRIX * (MODEL_MATRIX * vec4(c, 1.0));
	mv.xy += VERTEX.xy * COLOR.xy;
	v_shade = VERTEX.y + 0.5;
	VERTEX = mv.xyz;
}

void fragment() {
	vec4 t = texture(tex, v_uv);
	ALBEDO = mix(color, lit, t.r * 0.6 * v_shade);
	ALPHA = t.a * opacity;
}

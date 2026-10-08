// Particles and halos (BB_VERT / BB_FRAG): camera-facing sprites from the atlas.
// MultiMesh: the instance origin is the position, INSTANCE_CUSTOM = (size, rotation, cell),
// COLOR = tint and alpha. The variant files pick the blend mode.
#include "res://src/render3d/shaders/globals.gdshaderinc"

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;

varying vec2 v_uv;
varying vec4 v_c;

void vertex() {
	vec4 mv = VIEW_MATRIX * vec4((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, 1.0);
	float c = cos(INSTANCE_CUSTOM.y);
	float s = sin(INSTANCE_CUSTOM.y);
	vec2 q = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y) * INSTANCE_CUSTOM.x;
	mv.xy += q;
	VERTEX = mv.xyz;
	float cell = INSTANCE_CUSTOM.z;
	v_uv = (vec2(mod(cell, 4.0), 3.0 - floor(cell / 4.0)) + UV) / 4.0;
	v_c = COLOR;
}

void fragment() {
	vec4 t = texture(tex, v_uv);
	float a = v_c.a * t.a;
	if (a < 0.004) discard;
	ALBEDO = v_c.rgb * t.rgb;
	ALPHA = a;
}

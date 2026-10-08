// The title's "Opus": gold leaf on the Stage (the web build's background-clip: text
// gradient), plain rubric on the Score. `k` blends the two.
shader_type canvas_item;

uniform float top = 0.0;
uniform float height = 57.0;
uniform vec4 flat_color : source_color;
uniform float k = 1.0;

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

vec3 gold(float t) {
	vec3 c0 = vec3(1.0, 0.973, 0.878);
	vec3 c1 = vec3(0.949, 0.831, 0.549);
	vec3 c2 = vec3(0.851, 0.663, 0.282);
	vec3 c3 = vec3(0.984, 0.906, 0.69);
	if (t < 0.08) return c0;
	if (t < 0.40) return mix(c0, c1, (t - 0.08) / 0.32);
	if (t < 0.66) return mix(c1, c2, (t - 0.40) / 0.26);
	if (t < 0.92) return mix(c2, c3, (t - 0.66) / 0.26);
	return c3;
}

void fragment() {
	float t = clamp((ly - top) / height, 0.0, 1.0);
	COLOR.rgb = mix(flat_color.rgb, gold(t), k);
}

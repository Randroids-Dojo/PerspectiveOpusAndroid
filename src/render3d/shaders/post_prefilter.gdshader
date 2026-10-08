// Bloom prefilter (the web Stage's PREFILTER): soft-knee threshold, 4-tap average.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 texel;
uniform float threshold = 1.0;

vec3 pick(vec2 uv) {
	vec3 c = texture(src, uv).rgb;
	float br = max(c.r, max(c.g, c.b));
	float knee = threshold * 0.5;
	float soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
	soft = soft * soft / (4.0 * knee + 1e-4);
	float w = max(soft, br - threshold) / max(br, 1e-4);
	return min(c * w, vec3(30.0));
}

void fragment() {
	vec2 o = texel * 0.5;
	vec3 c = pick(UV + vec2(-o.x, -o.y)) + pick(UV + vec2(o.x, -o.y)) + pick(UV + vec2(-o.x, o.y)) + pick(UV + vec2(o.x, o.y));
	COLOR = vec4(c * 0.25, 1.0);
}

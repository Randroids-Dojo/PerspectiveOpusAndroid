// The level scene's background: the backdrop, rendered by its own camera into a smaller
// target, softened with the web Stage's BG_BLUR taps (or drawn as is at low quality).
shader_type sky;

uniform sampler2D bg : filter_linear, repeat_disable;
uniform vec2 texel = vec2(0.001);
uniform bool blur = true;

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0);
	} else {
	vec2 uv = SCREEN_UV;
	vec3 c;
	if (blur) {
		vec2 o = texel;
		c = texture(bg, uv).rgb * 0.4;
		c += texture(bg, uv + vec2(o.x, o.y * 0.5)).rgb * 0.15;
		c += texture(bg, uv + vec2(-o.x, -o.y * 0.5)).rgb * 0.15;
		c += texture(bg, uv + vec2(-o.x * 0.5, o.y)).rgb * 0.15;
		c += texture(bg, uv + vec2(o.x * 0.5, -o.y)).rgb * 0.15;
	} else {
		c = texture(bg, uv).rgb;
	}
	COLOR = c;
	}
}

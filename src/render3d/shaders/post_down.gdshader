// Bloom downsample (DOWN): centre-weighted 5 taps.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 texel;

void fragment() {
	vec2 o = texel;
	vec3 c = texture(src, UV).rgb * 4.0;
	c += texture(src, UV + vec2(-o.x, -o.y)).rgb;
	c += texture(src, UV + vec2(o.x, -o.y)).rgb;
	c += texture(src, UV + vec2(-o.x, o.y)).rgb;
	c += texture(src, UV + vec2(o.x, o.y)).rgb;
	COLOR = vec4(c / 8.0, 1.0);
}

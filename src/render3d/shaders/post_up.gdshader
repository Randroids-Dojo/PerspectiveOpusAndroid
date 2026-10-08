// Bloom upsample (UP): an 8-tap tent of the smaller level added onto this level's downsample
// (the web build blends it additively onto the same target).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear, repeat_disable;
uniform sampler2D base : filter_linear, repeat_disable;
uniform vec2 texel;
uniform float weight = 1.0;

void fragment() {
	vec2 o = texel;
	vec2 uv = UV;
	vec3 c = texture(src, uv + vec2(-o.x * 2.0, 0.0)).rgb;
	c += texture(src, uv + vec2(-o.x, o.y)).rgb * 2.0;
	c += texture(src, uv + vec2(0.0, o.y * 2.0)).rgb;
	c += texture(src, uv + vec2(o.x, o.y)).rgb * 2.0;
	c += texture(src, uv + vec2(o.x * 2.0, 0.0)).rgb;
	c += texture(src, uv + vec2(o.x, -o.y)).rgb * 2.0;
	c += texture(src, uv + vec2(0.0, -o.y * 2.0)).rgb;
	c += texture(src, uv + vec2(-o.x, -o.y)).rgb * 2.0;
	COLOR = vec4(texture(base, uv).rgb + c / 12.0 * weight, 1.0);
}

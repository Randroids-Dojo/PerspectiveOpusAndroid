// The backdrop's sky dome (the web Stage's SKY_FRAG): gradient, sun glow and horizon band,
// and the sun disc. Directions are three.js world axes, which Godot shares here.
shader_type sky;

uniform vec3 top;
uniform vec3 mid;
uniform vec3 horizon;
uniform vec3 bottom;
uniform vec3 sun_dir = vec3(0.0, 0.1, -1.0);
uniform vec3 sun_color;
uniform float sun_size = 0.02;
uniform float disc = 6.0;
uniform float glow = 1.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	vec3 c;
	if (e >= 0.0) {
		c = mix(horizon, mid, smoothstep(0.0, 0.22, e));
		c = mix(c, top, smoothstep(0.16, 0.75, e));
	} else {
		c = mix(horizon, bottom, smoothstep(0.0, 0.2, -e));
	}
	float s = max(dot(d, sun_dir), 0.0);
	float gl = pow(s, 6.0) * 0.35 + pow(s, 40.0) * 0.6 + pow(s, 400.0) * 1.2;
	float band = exp(-abs(e) * 14.0) * pow(max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), 0.0), 3.0);
	c += sun_color * (gl + band * 0.25) * glow;
	float r = acos(clamp(dot(d, sun_dir), -1.0, 1.0));
	float dsc = 1.0 - smoothstep(sun_size * 0.92, sun_size, r);
	c += sun_color * dsc * disc;
	COLOR = c;
}

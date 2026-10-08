// Per-frame stage state shared by every stage material, read from a small float texture
// the Stage rewrites each frame (one texel per vec4, see stage_globals.gd for the layout).
uniform sampler2D stage_globals : filter_nearest, repeat_disable;

vec4 g(int i) { return texelFetch(stage_globals, ivec2(i, 0), 0); }

float g_time() { return g(0).x; }
float g_wind() { return g(0).y; }
vec3 g_player() { return g(5).xyz; }
vec3 g_fog_color() { return g(6).rgb; }
float g_fog_near() { return g(7).x; }
float g_fog_far() { return g(7).y; }
float g_env_intensity() { return g(7).z; }
vec3 g_hemi_sky() { return g(8).rgb; }
vec3 g_hemi_ground() { return g(9).rgb; }

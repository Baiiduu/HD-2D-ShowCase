shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert_wrap;

#include "res://shaders/pixel.gdshaderinc"

varying vec3 wpos;
varying vec3 base_col;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	base_col = COLOR.rgb * (0.8 + 0.4 * INSTANCE_CUSTOM.r);
}

void fragment() {
	vec3 q = floor(wpos * 12.0);
	float n = hash12(q.xy + q.z * 7.13);
	vec3 col = base_col * (0.82 + 0.3 * n);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}

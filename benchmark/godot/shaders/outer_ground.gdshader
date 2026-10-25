shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/pixel.gdshaderinc"

uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 map_rect = vec4(-12.0, -10.4, 36.0, 10.4);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz / 1.6;
	vec3 g = px_sample(tex_grass, uv, vec2(64.0)).rgb;
	vec3 r = px_sample(tex_rock, vec2(uv.x + uv.y, -wpos.y / 1.6), vec2(64.0)).rgb;
	float v = fbm2(wpos.xz * 0.08);
	g *= mix(vec3(0.62, 0.7, 0.62), vec3(0.95, 0.9, 0.72), v);
	float steep = smoothstep(0.75, 0.55, wnorm.y);
	vec3 col = mix(g, r * 0.8, steep);
	// distance from the playable block: the meadow darkens and cools as it recedes
	vec2 c = (map_rect.xy + map_rect.zw) * 0.5;
	vec2 hs = (map_rect.zw - map_rect.xy) * 0.5;
	float dist = length(max(abs(wpos.xz - c) - hs, 0.0));
	col *= mix(0.85, 0.6, smoothstep(4.0, 80.0, dist));
	// soft occlusion at the foot of the map block
	col *= mix(0.55, 1.0, smoothstep(0.0, 2.5, dist));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
}

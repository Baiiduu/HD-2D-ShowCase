shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/pixel.gdshaderinc"

// A soft sheet of ground mist filling the lowland around the map block.
uniform vec3 mist_color : source_color = vec3(0.21, 0.205, 0.25);
uniform vec3 glow_color : source_color = vec3(0.34, 0.28, 0.3);
uniform float density = 0.9;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vp.xyz /= vp.w;
	float behind = max(length(vp.xyz) - length(VERTEX), 0.0);
	float n = fbm2(wpos.xz * 0.06 + vec2(TIME * 0.015, TIME * 0.008));
	float a = 1.0 - exp(-behind * density * (0.6 + 0.8 * n));
	float dist = length(VERTEX);
	vec3 c = mix(mist_color, glow_color, smoothstep(0.3, 0.8, n) * 0.5);
	// a little brighter where the mist faces the lit map
	c *= 1.0 + 0.25 * (1.0 - smoothstep(10.0, 60.0, dist));
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 0.97);
}

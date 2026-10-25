shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/pixel.gdshaderinc"
#include "res://shaders/spill.gdshaderinc"

uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(-7, -6);
uniform ivec2 map_size = ivec2(30, 13);
uniform sampler2D tex_water : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.04, 0.12, 0.14);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.27, 0.27);
uniform vec3 foam_color : source_color = vec3(0.7, 0.78, 0.78);
uniform float flow_speed = 0.32;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

ivec4 cell(ivec2 c) {
	ivec2 l = c - map_origin;
	if (l.x < 0 || l.y < 0 || l.x >= map_size.x || l.y >= map_size.y) return ivec4(-1);
	return ivec4(round(texelFetch(data_tex, l, 0) * 255.0));
}

void fragment() {
	vec2 cf = wpos.xz / 1.6;
	ivec2 own = ivec2(round(cf));
	ivec4 od = cell(own);
	vec2 local = wpos.xz - vec2(own) * 1.6; // -0.8 .. 0.8

	// distance to the nearest bank / to a waterfall plunge line
	float bank = 9.0;
	float plunge = 9.0;
	ivec2 dirs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		ivec4 nd = cell(own + dirs[i]);
		float d = 0.8 - dot(local, vec2(dirs[i]));
		if (nd.r < 0) continue;
		if ((nd.b & 4) == 0) {
			bank = min(bank, d);
		} else if (nd.g > od.g) {
			plunge = min(plunge, d);
		}
	}
	// also round the inside corners
	for (int i = 0; i < 4; i++) {
		ivec2 dg = ivec2(i < 2 ? 1 : -1, (i % 2 == 0) ? 1 : -1);
		ivec4 nd = cell(own + dg);
		if (nd.r >= 0 && (nd.b & 4) == 0) {
			vec2 corner = vec2(dg) * 0.8;
			bank = min(bank, length(local - corner));
		}
	}

	float t = TIME * flow_speed;
	vec2 uv1 = wpos.xz / 1.6 * vec2(1.0, 0.6) + vec2(0.0, -t);
	vec2 uv2 = wpos.xz / 1.6 * vec2(0.7, 0.4) + vec2(0.37, -t * 1.7);
	vec3 w1 = px_sample(tex_water, uv1, vec2(64.0)).rgb;
	vec3 w2 = px_sample(tex_water, uv2, vec2(64.0)).rgb;
	float ripple = px_lum(w1) * 0.6 + px_lum(w2) * 0.4;

	float shallow = 1.0 - smoothstep(0.0, 0.55, bank);
	vec3 col = mix(deep_color, shallow_color, shallow);
	col += (w1 * 0.6 + w2 * 0.4) * 0.11;

	// Foam: pixel-quantised, animated lace along the banks and below the waterfall.
	vec2 tq = floor(wpos.xz * 40.0) / 40.0;
	float n1 = vnoise(tq * vec2(5.0, 3.0) + vec2(0.0, -TIME * 1.3));
	float n2 = vnoise(tq * 9.0 + vec2(TIME * 0.4, -TIME * 2.1));
	float edge_w = 0.03 + 0.09 * n1;
	float foam = (1.0 - step(edge_w, bank)) * step(0.42, n2) * (0.6 + 0.4 * n1);
	foam = max(foam, step(0.74, n2) * (1.0 - smoothstep(0.08, 0.26, bank)) * 0.8);
	float churn = 1.0 - smoothstep(0.0, 1.1 + 0.4 * n1, plunge);
	foam = max(foam, smoothstep(0.35, 0.6, churn * (0.55 + 0.6 * n2)));
	foam = max(foam, step(0.84, ripple) * 0.35);
	foam = clamp(foam, 0.0, 1.0) * 0.8;

	vec2 b = px_bump(tex_water, uv1, vec2(64.0), max(length(dFdx(uv1)), length(dFdy(uv1))) * 64.0);
	vec2 b2 = px_bump(tex_water, uv2, vec2(64.0), max(length(dFdx(uv2)), length(dFdy(uv2))) * 64.0);
	vec3 n = normalize(vec3(-(b.x + b2.x) * 1.4, 1.0, -(b.y + b2.y) * 1.4));
	n = normalize(mix(n, vec3(0.0, 1.0, 0.0), foam));

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(col, foam_color, foam);
	ROUGHNESS = mix(0.04, 0.7, foam);
	SPECULAR = 0.6;
	EMISSION = foam * foam_color * 0.05 + mix(col, foam_color, foam) * emissive_spill(wpos, vec3(0.0, 1.0, 0.0));
}

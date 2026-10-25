shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/pixel.gdshaderinc"
#include "res://shaders/spill.gdshaderinc"

// Terrain grid: R = biome, G = level + 4, B = overlay bits, A = effective path flags (1 road, 2 dirt)
uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(-7, -6);
uniform ivec2 map_size = ivec2(30, 13);

uniform sampler2D tex_city : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_cyber : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_slate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D atlas_road : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 cyber_tint = vec3(0.3, 0.35, 0.46);

// Footprints of buildings for contact occlusion: (minx, minz, maxx, maxz), ao_rect_h = top y
uniform vec4 ao_rects[16];
uniform float ao_rect_h[16];
uniform int ao_rect_count = 0;

const ivec2 DG_TILE[16] = ivec2[16](
	ivec2(0, 3), ivec2(3, 3), ivec2(0, 0), ivec2(3, 2),
	ivec2(0, 2), ivec2(1, 2), ivec2(2, 3), ivec2(3, 1),
	ivec2(1, 3), ivec2(0, 1), ivec2(3, 0), ivec2(2, 0),
	ivec2(1, 0), ivec2(2, 2), ivec2(1, 1), ivec2(2, 1));

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

bool in_map(ivec2 c) {
	ivec2 l = c - map_origin;
	return l.x >= 0 && l.y >= 0 && l.x < map_size.x && l.y < map_size.y;
}

ivec4 cell(ivec2 c) {
	ivec2 l = clamp(c - map_origin, ivec2(0), map_size - 1);
	return ivec4(round(texelFetch(data_tex, l, 0) * 255.0));
}

float cell_top(ivec4 d) {
	float h = float(d.g - 4) * 0.8 + 0.02;
	if ((d.b & 16) != 0) h += 0.4;
	return h;
}

vec4 atlas_px(sampler2D at, int key, vec2 lf, vec2 gx, vec2 gy) {
	if (key == 0) return vec4(0.0);
	ivec2 tile = DG_TILE[key];
	vec2 p = lf * 64.0 - 0.5;
	vec2 fw = max(abs(gx) + abs(gy), vec2(1e-4));
	vec2 i = floor(p);
	vec2 f = clamp((fract(p) - 0.5) / fw + 0.5, 0.0, 1.0);
	vec2 q = clamp(i + f, vec2(0.0), vec2(63.0)) + 0.5;
	return textureGrad(at, (vec2(tile) * 64.0 + q) / 256.0, gx / 256.0, gy / 256.0);
}

float road_alpha_at(vec2 c) {
	ivec2 di = ivec2(floor(c));
	vec2 lf = c - floor(c);
	int k = (cell(di).a & 1) * 1 + (cell(di + ivec2(0, 1)).a & 1) * 2
		+ (cell(di + ivec2(1, 0)).a & 1) * 4 + (cell(di + ivec2(1, 1)).a & 1) * 8;
	if (k == 0) return 0.0;
	vec2 q = vec2(DG_TILE[k]) * 64.0 + clamp(floor(lf * 64.0), vec2(0.0), vec2(63.0)) + 0.5;
	return textureLod(atlas_road, q / 256.0, 0.0).a;
}

void fragment() {
	vec2 cf = wpos.xz / 1.6;
	vec2 uv = cf;                      // 64 texels per 1.6 m
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	float fwt = max(length(gx), length(gy)) * 64.0;

	vec3 c_city = px_sample_g(tex_city, uv, vec2(64.0), gx, gy).rgb;
	vec3 c_cyber = px_sample_g(tex_cyber, uv, vec2(64.0), gx, gy).rgb * cyber_tint;
	vec3 c_slate = px_sample_g(tex_slate, uv, vec2(64.0), gx, gy).rgb;
	vec3 c_grass = px_sample_g(tex_grass, uv, vec2(64.0), gx, gy).rgb;

	// Biome edges: texel-quantised organic jitter so grass creeps into the metal floor etc.
	vec2 tq = floor(wpos.xz * 40.0) / 40.0;
	vec2 jit = (vec2(fbm2(tq * 1.3), fbm2(tq * 1.3 + 41.0)) - 0.5) * 0.55
		+ (vec2(hash12(tq * 40.0), hash12(tq * 40.0 + 7.7)) - 0.5) * 0.12;
	ivec2 own = ivec2(round(cf));
	ivec4 od = cell(own);
	ivec4 bd = cell(ivec2(round(cf + jit)));
	int biome = bd.r;
	if (abs(cell_top(bd) - cell_top(od)) > 0.3) biome = od.r;

	vec3 base = c_grass;
	float rough = 0.92;
	float wet = 0.05;
	float metal = 0.0;
	vec2 bump = vec2(0.0);
	if (biome == 0) {
		base = c_city; rough = 0.62; wet = 0.85;
		bump = px_bump(tex_city, uv, vec2(64.0), fwt);
	} else if (biome == 1) {
		base = c_cyber; rough = 0.34; wet = 0.6; metal = 0.35;
		bump = px_bump(tex_cyber, uv, vec2(64.0), fwt) * 0.5;
	} else if (biome == 2) {
		base = mix(vec3(px_lum(c_slate)), c_slate, 0.7) * vec3(1.04, 1.0, 0.93); rough = 0.55; wet = 0.5;
		bump = px_bump(tex_slate, uv, vec2(64.0), fwt);
	} else {
		bump = px_bump(tex_grass, uv, vec2(64.0), fwt) * 0.7;
		// gentle colour variation in the meadow
		float v = fbm2(tq * 0.45);
		base *= mix(vec3(0.86, 0.9, 0.82), vec3(1.08, 1.04, 0.92), v);
		base = mix(vec3(px_lum(base)), base, 0.8);
	}

	// Dual-grid overlays: display cell corners sit on terrain cell centres.
	ivec2 di = ivec2(floor(cf));
	vec2 lf = cf - floor(cf);
	ivec4 nw = cell(di);
	ivec4 sw = cell(di + ivec2(0, 1));
	ivec4 ne = cell(di + ivec2(1, 0));
	ivec4 se = cell(di + ivec2(1, 1));
	int key_road = (nw.a & 1) * 1 + (sw.a & 1) * 2 + (ne.a & 1) * 4 + (se.a & 1) * 8;
	int key_dirt = ((nw.a >> 1) & 1) * 1 + ((sw.a >> 1) & 1) * 2 + ((ne.a >> 1) & 1) * 4 + ((se.a >> 1) & 1) * 8;
	vec2 agx = gx * 64.0;
	vec2 agy = gy * 64.0;
	vec4 dirt = atlas_px(atlas_dirt, key_dirt, lf, agx, agy);
	vec4 road = atlas_px(atlas_road, key_road, lf, agx, agy);
	base = mix(base, dirt.rgb * vec3(1.05, 0.95, 0.9), dirt.a);
	rough = mix(rough, 0.85, dirt.a);
	wet = mix(wet, 0.25, dirt.a);
	metal = mix(metal, 0.0, max(dirt.a, road.a));
	// raised cobbles: a 2-3 texel drop shadow on the moon-ward side of the road edge
	float ra_off = road_alpha_at(floor(cf * 64.0) / 64.0 + vec2(-0.53, 0.85) * (2.5 / 64.0));
	base *= 1.0 - 0.4 * max(ra_off - road.a, 0.0);
	base = mix(base, road.rgb, road.a);
	rough = mix(rough, 0.6, road.a);
	wet = mix(wet, 0.8, road.a);
	if (road.a > 0.5 || dirt.a > 0.5) {
		// bevel the overlay texels from the atlas luminance
		vec2 q = vec2(DG_TILE[road.a > 0.5 ? key_road : key_dirt]) * 64.0 + floor(lf * 64.0) + 0.5;
		float fade = 1.0 - smoothstep(0.7, 2.2, fwt);
		if (road.a > 0.5) {
			float l0 = px_lum(textureLod(atlas_road, (q - vec2(1.0, 0.0)) / 256.0, 0.0).rgb);
			float l1 = px_lum(textureLod(atlas_road, (q + vec2(1.0, 0.0)) / 256.0, 0.0).rgb);
			float l2 = px_lum(textureLod(atlas_road, (q - vec2(0.0, 1.0)) / 256.0, 0.0).rgb);
			float l3 = px_lum(textureLod(atlas_road, (q + vec2(0.0, 1.0)) / 256.0, 0.0).rgb);
			bump = vec2(l1 - l0, l3 - l2) * 0.5 * fade;
		} else {
			float l0 = px_lum(textureLod(atlas_dirt, (q - vec2(1.0, 0.0)) / 256.0, 0.0).rgb);
			float l1 = px_lum(textureLod(atlas_dirt, (q + vec2(1.0, 0.0)) / 256.0, 0.0).rgb);
			float l2 = px_lum(textureLod(atlas_dirt, (q - vec2(0.0, 1.0)) / 256.0, 0.0).rgb);
			float l3 = px_lum(textureLod(atlas_dirt, (q + vec2(0.0, 1.0)) / 256.0, 0.0).rgb);
			bump = vec2(l1 - l0, l3 - l2) * 0.35 * fade;
		}
	}

	// Rain-wet puddles (texel-quantised so their rims stay pixel-crisp).
	float pn = fbm2(tq * 0.55 + vec2(3.1, 7.4));
	float puddle = smoothstep(0.56, 0.6, pn) * smoothstep(0.3, 0.6, wet);
	float damp = wet * 0.35;
	base *= mix(1.0 - damp * 0.35, 0.5, puddle);
	rough = mix(rough * (1.0 - damp * 0.5), 0.03, puddle);
	bump *= (1.0 - puddle);

	// Contact occlusion at the foot of cliffs and buildings.
	float ao = 1.0;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dz == 0) continue;
			ivec2 nc = own + ivec2(dx, dz);
			if (!in_map(nc)) continue;
			ivec4 nd = cell(nc);
			if ((nd.b & 4) != 0) continue;
			float nh = cell_top(nd);
			if (nh > wpos.y + 0.3) {
				vec2 d = max(abs(wpos.xz - vec2(nc) * 1.6) - 0.8, 0.0);
				ao *= mix(0.42, 1.0, smoothstep(0.0, 0.85, length(d)));
			}
		}
	}
	for (int i = 0; i < ao_rect_count; i++) {
		vec4 r = ao_rects[i];
		if (wpos.y > ao_rect_h[i]) continue;
		vec2 c = (r.xy + r.zw) * 0.5;
		vec2 hs = (r.zw - r.xy) * 0.5;
		vec2 d = max(abs(wpos.xz - c) - hs, 0.0);
		ao *= mix(0.38, 1.0, smoothstep(0.0, 1.0, length(d)));
	}

	vec3 nw_ = normalize(wnorm + vec3(-bump.x, 0.0, -bump.y) * 3.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw_, 0.0)).xyz);
	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = base * emissive_spill(wpos, wnorm) * ao;
}

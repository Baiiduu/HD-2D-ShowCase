shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/pixel.gdshaderinc"
#include "res://shaders/spill.gdshaderinc"

uniform sampler2D tex_cliff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_lip : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 topbot;
varying vec4 info;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	topbot = UV2;
	info = COLOR;
}

void fragment() {
	vec2 t = normalize(vec2(-wnorm.z, wnorm.x));
	float along = dot(wpos.xz, t);
	vec2 uv = vec2(along / 1.6, -wpos.y / 1.6);
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	float fwt = max(length(gx), length(gy)) * 64.0;
	vec3 col = px_sample_g(tex_cliff, uv, vec2(64.0), gx, gy).rgb;
	vec2 bump = px_bump(tex_cliff, uv, vec2(64.0), fwt);

	float from_top = topbot.x - wpos.y;
	float from_bot = wpos.y - topbot.y;
	float tex_col = floor(along * 40.0);

	// Grass / stone lip hanging over the top edge (2-4 texels, ragged per column).
	float lip = (1.5 + floor(hash12(vec2(tex_col, 3.0)) * 3.0)) / 40.0;
	if (info.b > 0.5) {
		lip += step(0.82, hash12(vec2(tex_col, 9.0))) * 2.0 / 40.0;
	} else {
		lip = 1.5 / 40.0;
	}
	float in_lip = step(from_top, lip);
	vec3 lipc = info.b > 0.5
		? px_sample_g(tex_grass, vec2(along / 1.6, wpos.y / 1.6), vec2(64.0), gx, gy).rgb * 0.82
		: px_sample_g(tex_lip, vec2(along / 1.6, wpos.y / 1.6), vec2(64.0), gx, gy).rgb * 0.9;
	col = mix(col, lipc, in_lip);

	// Strata shading: lit rim under the crest, deepening toward the foot of the wall.
	float shade = mix(0.42, 1.0, smoothstep(0.0, 0.75, from_bot));
	shade *= 1.0 + 0.22 * (1.0 - smoothstep(0.0, 0.18, from_top - lip)) * (1.0 - in_lip);
	// a dark cast line right under the lip
	shade *= mix(1.0, 0.72, (1.0 - in_lip) * (1.0 - smoothstep(0.0, 2.0 / 40.0, from_top - lip)));
	float rough = 0.9;

	// Waterline: darker, glossy rock just above the stream.
	if (info.r > 0.5) {
		float wy = info.g * 4.0 - 2.0;
		float above = wpos.y - wy;
		float wetb = 1.0 - smoothstep(0.0, 0.14, above);
		shade *= mix(1.0, 0.6, wetb);
		rough = mix(rough, 0.18, wetb);
	}
	// Lowland fade: the outer skirt of the map sinks into the ground mist.
	float sink = smoothstep(-0.2, -1.6, wpos.y);
	col = mix(col, col * vec3(0.7, 0.72, 0.8), sink * 0.6);

	vec3 b3 = vec3(t.x, 0.0, t.y) * bump.x + vec3(0.0, 1.0, 0.0) * -bump.y;
	vec3 nw_ = normalize(wnorm + b3 * 2.5 * (1.0 - in_lip));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw_, 0.0)).xyz);
	ALBEDO = col * shade;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	AO = shade;
	AO_LIGHT_AFFECT = 0.3;
	EMISSION = col * shade * emissive_spill(wpos, wnorm);
}

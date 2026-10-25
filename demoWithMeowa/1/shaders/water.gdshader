shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/rain_surface.gdshaderinc"
#include "res://shaders/water_foam.gdshaderinc"

// Flowing pixel water, bank/fall foam and independent planar mirrors.

uniform sampler2D water_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(-7, -6);
uniform vec4 shallow_color : source_color = vec4(0.26, 0.46, 0.5, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.25, 0.3, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.85, 0.85, 1.0);
uniform float foam_scale : hint_range(0.5, 2.0) = 1.0;
uniform float foam_density : hint_range(0.0, 1.0) = 0.55;
uniform float foam_motion : hint_range(0.0, 0.3) = 0.08;
uniform float bank_foam_width : hint_range(0.02, 0.4) = 0.14;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.8;
uniform vec2 flow = vec2(0.0, 0.12);
uniform float cell_size = 1.6;
uniform float texture_pixels = 64.0;
// 深度差小于该值（米）的地方画泡沫
uniform float foam_distance = 0.12;
uniform float depth_fade = 1.6;
uniform float opacity = 0.86;
uniform float wave_strength = 0.08;
uniform float highlight_strength : hint_range(0.0, 4.0, 0.05) = 1.0;
uniform float highlight_roughness : hint_range(0.08, 0.5, 0.01) = 0.22;
uniform float glint_strength : hint_range(0.0, 2.0, 0.05) = 0.8;
uniform float reflection_strength = 0.85;
uniform sampler2D reflection_texture_0 : filter_linear, repeat_disable;
uniform sampler2D reflection_texture_1 : filter_linear, repeat_disable;
uniform mat4 reflection_matrix_0;
uniform mat4 reflection_matrix_1;
uniform vec2 reflection_heights = vec2(-0.32, 0.48);
uniform bool reflection_enabled_0 = false;
uniform bool reflection_enabled_1 = false;

group_uniforms rain;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 1.8;
uniform float rain_radius = 0.28;
uniform float rain_lifetime = 0.8;
uniform float rain_strength = 0.35;
group_uniforms;

varying vec3 world_position;
varying vec3 surface_normal;
varying float clear_water;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

ivec4 cell_at(ivec2 cell) {
	ivec2 point = cell - map_origin;
	ivec2 size = textureSize(terrain_map, 0);
	if (any(lessThan(point, ivec2(0))) || any(greaterThanEqual(point, size))) { return ivec4(0); }
	return ivec4(round(texelFetch(terrain_map, point, 0) * 255.0));
}

// Keep magnified texels crisp, with a one-screen-pixel transition and stable mip selection.
vec3 pixel_sample(vec2 uv) {
	vec2 pixel = uv * texture_pixels;
	vec2 seam = floor(pixel + 0.5);
	vec2 width = max(fwidth(pixel), vec2(0.0001));
	vec2 filtered = (seam + clamp((pixel - seam) / width, vec2(-0.5), vec2(0.5))) / texture_pixels;
	return textureGrad(water_texture, filtered, dFdx(uv), dFdy(uv)).rgb;
}

vec3 flow_pattern(vec2 uv, float time) {
	float rate = length(flow) / 0.12 * 0.6;
	float phase = fract(time * rate);
	float phase2 = fract(time * rate + 0.5);
	vec2 velocity = normalize(flow + vec2(0.0001)) * vec2(1.0, -1.0) * 0.66;
	// Each moving phase is blended out before its wrap; no periodic jump.
	vec2 a = uv - velocity * phase;
	vec2 b = uv - velocity * phase2 + 0.37;
	return mix(pixel_sample(a), pixel_sample(b), abs(phase - 0.5) * 2.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid = world_position.xz / cell_size;
	ivec2 cell = ivec2(floor(grid + 0.5));
	vec2 local = fract(grid + 0.5);
	ivec4 me = cell_at(cell);
	float bank = 9.0, fall = 9.0;
	// Map foam survives viewing angle changes; depth also catches props.
	for (int direction = 0; direction < 4; direction++) {
		ivec2 offset = direction == 0 ? ivec2(-1, 0) : direction == 1 ? ivec2(1, 0) : direction == 2 ? ivec2(0, -1) : ivec2(0, 1);
		float distance = (direction == 0 ? local.x : direction == 1 ? 1.0 - local.x : direction == 2 ? local.y : 1.0 - local.y) * cell_size;
		ivec4 neighbor = cell_at(cell + offset);
		if ((neighbor.g & 4) == 0) { bank = min(bank, distance); }
		else if (neighbor.b > me.b) { fall = min(fall, distance); }
	}
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float water_depth = max(0.0, -view.z / view.w + VERTEX.z);
	vec3 pattern = flow_pattern(grid * vec2(1.0, -1.0), TIME);
	float texel = cell_size / texture_pixels;
	vec2 pixel = (floor(world_position.xz / texel) + 0.5) * texel;
	vec2 foam_drift = length(flow) > 0.0001 ? normalize(flow) * foam_motion : vec2(0.0);
	float patches = foam_patches(world_position.xz, TIME, foam_scale, foam_density, foam_drift);
	float edge_variation = (foam_noise(pixel * 8.0 - foam_drift * TIME) - 0.5) * 0.07;
	float bank_foam = (1.0 - smoothstep(0.015, bank_foam_width, bank - edge_variation)) * (0.12 + patches * 0.88);
	// 水帘脚部已有白沫，河面只补充稀疏尾迹，避免两层叠成白色地毯。
	float fall_foam = (1.0 - smoothstep(0.03, 0.5, fall)) * patches * 0.35;
	float contact_foam = (1.0 - smoothstep(0.02, foam_distance, water_depth)) * (0.15 + patches * 0.85);
	float foam = max(max(bank_foam, fall_foam), contact_foam) * foam_strength;
	float glint = smoothstep(0.72, 0.95, dot(pattern, vec3(0.3, 0.4, 0.3)));
	// Benchmark keeps a dark body beneath the bright, broken reflections.
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, (1.0 - clamp(water_depth / depth_fade, 0.0, 1.0)) * 0.2);
	color += glint * shallow_color.rgb * 0.65 + pattern * 0.025;
	color = mix(color, foam_color.rgb, foam);
	vec4 rain = rain_surface(world_position.xz, rain_clock, rain_density * rain_amount, rain_radius, rain_lifetime) * rain_amount * rain_strength;
	color = mix(color, foam_color.rgb, clamp(rain.x * 0.55 + rain.w * 0.3, 0.0, 0.5) * (1.0 - foam));
	// Many small wave facets, stretched across the current. A large sine alone
	// produces smooth isolated blobs instead of a field of dancing highlights.
	vec2 current = normalize(flow + vec2(0.0001));
	vec2 wave_uv = (pixel - current * TIME * 0.22) * vec2(7.0, 23.0);
	float across = noise(wave_uv) * 2.0 - 1.0;
	float along = noise(wave_uv + vec2(13.7, 5.2)) * 2.0 - 1.0;
	vec2 ripples = vec2(across * 3.8 + (pattern.r - pattern.g), along * 2.8) * wave_strength;
	ripples += rain.yz * 0.5;
	vec3 world_normal = normalize(vec3(ripples.x, 1.0, ripples.y));
	surface_normal = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	clear_water = 1.0 - foam;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ROUGHNESS = mix(0.12, 0.75, foam);
	SPECULAR = 0.5;
	// The scene image uses the mean water plane, so microfacets cannot make
	// an entire character's reflection repeatedly fade in and out.
	float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(normalize(CAMERA_POSITION_WORLD - world_position).y, 0.0, 1.0), 5.0);
	bool upper = abs(world_position.y - reflection_heights.y) < abs(world_position.y - reflection_heights.x);
	bool enabled = upper ? reflection_enabled_1 : reflection_enabled_0;
	enabled = enabled && min(abs(world_position.y - reflection_heights.x), abs(world_position.y - reflection_heights.y)) < 0.01;
	vec3 reflection = vec3(0.0);
	float reflectivity = 0.0;
	if (enabled) {
		vec4 projected = (upper ? reflection_matrix_1 : reflection_matrix_0) * vec4(world_position, 1.0);
		vec2 projected_uv = projected.xy / max(projected.w, 0.0001) * 0.5 + 0.5;
		projected_uv.y = 1.0 - projected_uv.y;
		// Broad scene silhouettes retain a gentle, coherent wave displacement.
		vec2 scene_wave = vec2(sin(pixel.y * 2.7 + TIME * 0.8), cos(pixel.x * 2.1 - TIME * 0.6)) * wave_strength;
		vec2 scene_uv = projected_uv + scene_wave * vec2(0.016, 0.010) + rain.yz * vec2(0.008, 0.005);
		// Use the texture-driven displacement at benchmark scale, rather than
		// attenuating it twice by the small normal strength and UV scale.
		vec2 texture_wave = vec2((pattern.r - 0.5) * 0.9 + sin(pixel.y * 7.0 + TIME * 3.0) * 0.08, (pattern.g - 0.5) * 0.6);
		vec2 light_uv = projected_uv + (texture_wave * 0.03 + ripples * vec2(0.024, 0.016)) * (wave_strength / 0.08);
		float edge = smoothstep(0.0, 0.025, min(min(scene_uv.x, scene_uv.y), min(1.0 - scene_uv.x, 1.0 - scene_uv.y)));
		if (projected.w > 0.0) {
			vec3 scene_reflection = upper ? texture(reflection_texture_1, clamp(scene_uv, vec2(0.001), vec2(0.999))).rgb : texture(reflection_texture_0, clamp(scene_uv, vec2(0.001), vec2(0.999))).rgb;
			vec3 light_reflection = upper ? texture(reflection_texture_1, clamp(light_uv, vec2(0.001), vec2(0.999))).rgb : texture(reflection_texture_0, clamp(light_uv, vec2(0.001), vec2(0.999))).rgb;
			// Preserve ordinary scene radiance without luminance suppression.
			// Only the HDR excess gets the stronger sparkle displacement, and
			// is removed from the base sample to avoid doubling lamp energy.
			reflection = min(scene_reflection, vec3(1.0)) + max(light_reflection - vec3(1.0), vec3(0.0));
			reflectivity = clamp(mix(fresnel, 1.0, 0.22) * reflection_strength * clear_water * edge, 0.0, 0.95);
		}
	}
	ALBEDO = color * (1.0 - reflectivity);
	// Reflection already contains lighting; avoid lighting it a second time.
	EMISSION = reflection * reflectivity;
	ALPHA = mix(mix(opacity, 0.98, reflectivity), 0.96, foam);
}

// GGX with correlated Smith visibility. A broad lobe on the mean water plane
// keeps the soft lamp pool; a narrow rippled lobe breaks it into moving glints.
float water_specular(vec3 normal, vec3 light, vec3 view, float roughness) {
	vec3 half_vector = normalize(light + view);
	float nl = max(dot(normal, light), 0.0);
	float nv = max(dot(normal, view), 0.001);
	float nh = max(dot(normal, half_vector), 0.0);
	float vh = max(dot(view, half_vector), 0.0);
	float a = max(roughness * roughness, 0.004);
	float a2 = a * a;
	float denominator = 1.0 - nh * nh + nh * nh * a2;
	float distribution = a2 / max(PI * denominator * denominator, 0.00000001);
	float visibility = 0.5 / max(nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2), 0.0001);
	float fresnel = 0.04 + 0.96 * pow(1.0 - vh, 5.0);
	return distribution * visibility * fresnel * nl;
}

void light() {
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	float pool = water_specular(surface_normal, LIGHT, VIEW, highlight_roughness);
	float glints = water_specular(NORMAL, LIGHT, VIEW, 0.13) * glint_strength;
	float foam_specular = water_specular(NORMAL, LIGHT, VIEW, 0.75) * (1.0 - clear_water);
	SPECULAR_LIGHT += ((pool * 0.2 + glints) * clear_water + foam_specular) * highlight_strength * SPECULAR_AMOUNT * ATTENUATION * LIGHT_COLOR;
}

shader_type spatial;

// 崖壁保留岩层结构，用现有草地纹理衔接崖顶与崖脚；关闭过渡可恢复纯色草沿。
// UV2 = (墙顶高度, 墙底高度)，所有距离都量化到纹理像素，保持像素风。

uniform sampler2D wall_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.92, 0.88, 0.82, 1.0);
// 降低岩层颜色的饱和度，避免崖壁比地面更抢眼
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
uniform float texel = 0.025;
// 草沿厚度、沿下阴影线厚度（纹理像素）
uniform int lip_pixels = 3;
uniform int lip_shadow_pixels = 2;
// 崖底接触阴影的范围（米）与最暗程度
uniform float base_shadow_height = 0.5;
uniform float base_shadow_strength = 0.45;
uniform float roughness = 0.9;

group_uniforms grass_transition;
uniform bool transition_enabled = true;
uniform sampler2D grass_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(0.78, 0.91, 0.82, 1.0);
uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(0);
uniform float cell_size = 1.6;
uniform float grass_lip_pixels : hint_range(0.0, 8.0) = 3.0;
uniform float edge_variation_pixels : hint_range(0.0, 4.0) = 2.0;
uniform float transition_height : hint_range(0.0, 0.4) = 0.16;
uniform float moss_strength : hint_range(0.0, 1.0) = 0.4;
uniform float lip_shadow_strength : hint_range(0.0, 0.5) = 0.16;
uniform float base_blend_height : hint_range(0.0, 0.4) = 0.16;

varying float world_y;
varying vec2 wall_span;
varying vec3 terrain_position;
varying vec2 wall_direction;

float edge_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float edge_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(edge_hash(cell), edge_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(edge_hash(cell + vec2(0.0, 1.0)), edge_hash(cell + vec2(1.0)), f.x), f.y);
}

// Only blend against actual grass cells; paths, soil and water retain their edging.
bool has_grass(vec2 point) {
	ivec2 index = ivec2(round(point / cell_size)) - map_origin;
	ivec2 size = textureSize(terrain_map, 0);
	bool inside = all(greaterThanEqual(index, ivec2(0))) && all(lessThan(index, size));
	ivec2 cell = ivec2(round(texelFetch(terrain_map, clamp(index, ivec2(0), size - 1), 0).rg * 255.0));
	return inside && cell.x == 3 && (cell.y & 7) == 0;
}

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	wall_span = UV2;
	terrain_position = VERTEX;
	wall_direction = NORMAL.xz;
}

void fragment() {
	vec3 color = texture(wall_texture, UV).rgb;
	color = mix(vec3(dot(color, vec3(0.3, 0.59, 0.11))), color, saturation) * tint.rgb;
	float from_top = floor((wall_span.x - world_y) / texel);
	float from_bottom = floor((world_y - wall_span.y) / texel) * texel;
	bool grass_top = transition_enabled && has_grass(terrain_position.xz - wall_direction * texel);
	if (grass_top) {
		// UV2 and VERTEX are both local: Ground's vertical offset must not shift the rim.
		float depth = max(0.0, floor((wall_span.x - terrain_position.y) / texel)) * texel;
		float bottom = max(0.0, floor((terrain_position.y - wall_span.y) / texel)) * texel;
		float span = max(wall_span.x - wall_span.y, texel);
		vec2 pixel = (floor(terrain_position.xz / texel) + 0.5) * texel;
		float pattern = edge_noise(pixel * 5.0);
		float lip = max(0.0, grass_lip_pixels + floor((pattern - 0.5) * 2.0 * edge_variation_pixels)) * texel;
		float width = max(texel, min(transition_height, span * 0.35));
		// Fold the existing top texture down the face instead of painting a flat green stripe.
		vec2 grass_uv = (terrain_position.xz - wall_direction * (depth + texel * 0.5)) / cell_size;
		vec3 grass = texture(grass_texture, grass_uv).rgb * grass_tint.rgb;
		float cover = 1.0 - smoothstep(lip, lip + width, depth);
		float moss = moss_strength * smoothstep(0.25, 0.75, pattern);
		float full_grass = 1.0 - smoothstep(max(0.0, lip - texel), lip + texel, depth);
		color = mix(color, grass, cover * mix(moss, 1.0, full_grass));
		float shadow_fade = smoothstep(lip, lip + width, depth);
		float rim_shadow = 4.0 * shadow_fade * (1.0 - shadow_fade);
		color *= 1.0 - lip_shadow_strength * rim_shadow;
		if (has_grass(terrain_position.xz + wall_direction * texel) && base_blend_height > 0.0) {
			vec2 base_uv = (terrain_position.xz + wall_direction * (bottom + texel * 0.5)) / cell_size;
			vec3 base_grass = texture(grass_texture, base_uv).rgb * grass_tint.rgb;
			float base_cover = 1.0 - smoothstep(0.0, min(base_blend_height, span * 0.25), bottom);
			color = mix(color, base_grass, base_cover * moss_strength * (0.35 + pattern * 0.65));
		}
	} else if (from_top < float(lip_pixels)) {
		color = COLOR.rgb * (from_top < 1.0 ? 1.12 : 1.0);
	} else if (from_top < float(lip_pixels + lip_shadow_pixels)) {
		color *= 0.55;
	}
	float shade = mix(1.0 - base_shadow_strength, 1.0, smoothstep(0.0, base_shadow_height, from_bottom));
	ALBEDO = color * shade;
	ROUGHNESS = roughness;
}

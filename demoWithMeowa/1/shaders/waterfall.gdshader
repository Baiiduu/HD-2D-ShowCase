shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/water_foam.gdshaderinc"

// COLOR.r: 水帘=0、落水白沫=0.5、水滴=1；UV2 为上下水位。
// 水帘/白沫 COLOR.gb 标记真正的侧缘，相邻水格之间保持连续。
uniform vec4 water_color : source_color = vec4(0.18, 0.32, 0.38, 1.0);
uniform vec4 streak_color : source_color = vec4(0.5, 0.68, 0.72, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.85, 0.85, 1.0);
uniform float foam_scale : hint_range(0.5, 2.0) = 1.0;
uniform float foam_density : hint_range(0.0, 1.0) = 0.55;
uniform float foam_motion : hint_range(0.0, 0.3) = 0.08;
uniform vec2 foam_flow = vec2(0.0, 1.0);
uniform float splash_size : hint_range(0.02, 0.12) = 0.055;
uniform float splash_density : hint_range(0.0, 1.0) = 0.6;
uniform float speed : hint_range(0.2, 4.0) = 2.2;
uniform float texture_pixels = 64.0;
uniform float cell_size = 1.6;
uniform float lip_curve : hint_range(0.0, 0.4) = 0.18;
uniform float opacity : hint_range(0.0, 1.0) = 0.72;
uniform float stream_contrast : hint_range(0.0, 1.5) = 0.9;
uniform float foam_strength : hint_range(0.0, 1.5) = 0.85;
uniform float foam_length : hint_range(0.05, 1.0) = 0.65;
uniform float splash_strength : hint_range(0.0, 1.5) = 0.65;
uniform float glow : hint_range(0.0, 0.2) = 0.025;

varying vec3 world_position;
varying float world_across;
varying float drop_life;
varying float drop_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	vec3 direction = NORMAL;
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_across = dot(original_world.xz, vec2(-direction.z, direction.x));
	if (COLOR.r < 0.25) {
		// 上沿向外翻卷，随后落向下游；底端与白沫的起点一致。
		float u = UV.y;
		VERTEX += direction * lip_curve * (1.0 - pow(1.0 - u, 3.0));
		NORMAL = normalize(direction + vec3(0.0, 1.0, 0.0) *
			(3.0 * lip_curve * pow(1.0 - u, 2.0) / max(UV2.x - UV2.y, 0.01)));
	} else if (COLOR.r < 0.75) {
		VERTEX += direction * (lip_curve + UV.y * (foam_length - 1.0));
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		float seed = hash(COLOR.gb * vec2(71.0, 97.0));
		drop_seed = seed;
		float duration = 0.55 + seed * 0.35;
		drop_life = fract(TIME / duration + seed);
		float launch = 1.3 + seed * 0.6;
		float t = drop_life * launch / 4.9;
		float size = splash_size * foam_scale * (0.7 + seed * 0.6);
		// 每滴的顶点由相机朝向展开，斜视时不会变成细线。
		vec3 right = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz;
		vec3 up = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz;
		VERTEX += right * (UV.x - 0.5) * size + up * (0.5 - UV.y) * size * (1.1 + drop_life * 0.3);
		VERTEX += direction * (lip_curve + t * (0.35 + seed * 0.35));
		VERTEX += vec3(-direction.z, 0.0, direction.x) * (seed - 0.5) * t * 0.45;
		VERTEX.y += max(0.0, launch * t - 4.9 * t * t) * splash_strength;
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float texel = cell_size / texture_pixels;
	float column = floor(world_across / texel);
	float edge = mix(1.0, smoothstep(0.0, 0.06, UV.x), COLOR.g) *
		mix(1.0, 1.0 - smoothstep(0.94, 1.0, UV.x), COLOR.b);
	vec3 color;
	float alpha;
	if (COLOR.r < 0.25) {
		float lane_speed = speed * (0.85 + noise(vec2(column * 0.035, 2.7)) * 0.3);
		float flow = floor(world_position.y / texel) * texel + TIME * lane_speed;
		float broad = noise(vec2(column * 0.095, flow * 1.4));
		float fine = noise(vec2(column * 0.42 + 7.0, flow * 7.0));
		float ribbon = pow(smoothstep(0.35, 0.75, noise(vec2(column * 0.26 + 13.0, flow * 0.85))), 1.8);
		float streak = clamp(ribbon * (0.55 + broad * 0.45) + fine * 0.12, 0.0, 1.0) * stream_contrast;
		float top = (1.0 - smoothstep(0.0, 0.14, UV.y)) * (0.55 + broad * 0.45);
		float bottom = smoothstep(0.65, 1.0, UV.y) * (0.5 + fine * 0.5);
		float foam = clamp((top * 0.7 + bottom) * foam_strength, 0.0, 1.0);
		color = mix(water_color.rgb, streak_color.rgb, clamp(streak, 0.0, 1.0));
		color = mix(color, foam_color.rgb, foam);
		alpha = mix(opacity, min(opacity + 0.24, 1.0), clamp(streak, 0.0, 1.0));
		alpha = mix(alpha, 0.96, foam) * edge;
	} else if (COLOR.r < 0.75) {
		float progress = UV.y;
		float patches = foam_patches(world_position.xz, TIME, foam_scale, foam_density, foam_flow * foam_motion);
		float tail = 1.0 - smoothstep(0.12, 1.0, progress);
		float foam = (1.0 - smoothstep(0.0, 0.16, progress)) * 0.55 + patches * tail;
		color = foam_color.rgb;
		alpha = clamp(foam * foam_strength, 0.0, 0.95) * edge * tail;
	} else {
		// 4×4 的阶梯边缘，避免柔边圆点与水面像素泡沫脱节。
		vec2 tile = (floor(UV * 4.0) + 0.5) / 4.0 - 0.5;
		float drop = 1.0 - step(0.6, abs(tile.x) + abs(tile.y));
		float visibility = 1.0 - step(splash_density, drop_seed);
		color = foam_color.rgb;
		alpha = drop * visibility * sin(drop_life * 3.14159) * min(splash_strength, 1.0);
	}
	ALBEDO = color;
	EMISSION = COLOR.r < 0.25 ? color * glow : vec3(0.0);
	ALPHA = alpha;
	ROUGHNESS = COLOR.r < 0.25 ? 0.5 : 0.8;
	SPECULAR = COLOR.r < 0.25 ? 0.2 : 0.1;
}

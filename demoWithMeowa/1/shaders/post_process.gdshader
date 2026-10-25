shader_type canvas_item;

// 全屏后处理：椭圆虚化 + 暗角 + 分离色调（暗部偏冷、亮部偏暖）。

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D blurred_screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform bool ellipse_enabled = false;
uniform vec2 ellipse_center = vec2(0.5);
uniform vec2 ellipse_radius = vec2(0.34, 0.27);
uniform float ellipse_transition : hint_range(0.05, 2.0) = 0.7;
uniform float ellipse_blur_amount : hint_range(0.0, 1.0) = 0.03;
uniform bool lens_enabled = false;
uniform int lens_drop_count = 0;
// xy 为屏幕位置，z 为 900 像素高画面下的半径，w 为淡入/淡出权重。
uniform vec4 lens_drops[12];
// Stable per-drop phase, aspect, rotation and lower bulge; independent of slide.
uniform vec4 lens_drop_shapes[12];
uniform float lens_blur : hint_range(0.0, 5.0) = 1.0;
uniform float lens_refraction : hint_range(0.0, 24.0) = 9.0;
uniform float lens_irregularity : hint_range(0.0, 1.0) = 0.7;
uniform float lens_light_response : hint_range(0.0, 2.0) = 0.55;
uniform float lens_rim_strength : hint_range(0.0, 0.5) = 0.18;
uniform float lens_center_protection : hint_range(0.0, 0.35) = 0.14;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.94, 1.12);
uniform vec3 highlight_tint : source_color = vec3(1.08, 1.0, 0.9);
uniform float split_toning : hint_range(0.0, 1.0) = 0.5;

float lens_field(vec2 point, vec4 shape) {
	float c = cos(shape.z);
	float s = sin(shape.z);
	vec2 p = vec2(c * point.x + s * point.y, -s * point.x + c * point.y);
	p.y /= max(shape.y, 0.5);
	// A smooth lower bulge and bent axis avoid identical oval silhouettes.
	p.x += sin(p.y * 2.4 + shape.x) * p.y * 0.1 * lens_irregularity;
	p.x /= clamp(1.0 + shape.w * lens_irregularity * p.y * 0.35, 0.55, 1.35);
	float angle = atan(p.y, p.x + 0.00001);
	float boundary = 1.0 + lens_irregularity * (sin(angle * 2.0 + shape.x) * 0.16 + sin(angle * 3.0 - shape.x * 1.3) * 0.1 + sin(angle * 5.0 + shape.x * 0.7) * 0.055);
	return length(p) / boundary;
}

float lens_height(vec2 point, vec4 shape) {
	float field = lens_field(point, shape);
	// Smooth convex thickness, with shallow local variations within the drop.
	float body = sqrt(max(1.0 - field * field, 0.0));
	return body * (1.0 + sin(point.x * 3.0 + shape.x) * sin(point.y * 2.5 - shape.x) * 0.12 * lens_irregularity);
}

void fragment() {
	vec2 sample_uv = SCREEN_UV;
	float drop_blur = 0.0;
	float drop_mask = 0.0;
	float highlight = 0.0;
	float shade = 0.0;
	vec3 light_bleed = vec3(0.0);
	if (lens_enabled) {
		vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 focus_offset = (SCREEN_UV - ellipse_center) * vec2(screen_size.x / screen_size.y, 1.0);
		float protection = lens_center_protection > 0.0 ? smoothstep(lens_center_protection * 0.65, lens_center_protection, length(focus_offset)) : 1.0;
		for (int i = 0; i < 12; i++) {
			if (i >= lens_drop_count) { break; }
			vec4 drop = lens_drops[i];
			if (drop.w <= 0.0) { continue; }
			float drop_radius = max(drop.z * screen_size.y / 900.0, 1.0);
			vec2 point = (SCREEN_UV - drop.xy) * screen_size / drop_radius;
			// Most screen pixels miss every drop; skip expensive profiles/samples.
			if (dot(point, point) > 6.25) { continue; }
			vec4 shape = lens_drop_shapes[i];
			float radius = lens_field(point, shape);
			if (radius >= 1.0) { continue; }
			float mask = (1.0 - smoothstep(0.85, 1.0, radius)) * drop.w * protection;
			const float step_size = 0.025;
			vec2 gradient = vec2(lens_height(point + vec2(step_size, 0.0), shape) - lens_height(point - vec2(step_size, 0.0), shape), lens_height(point + vec2(0.0, step_size), shape) - lens_height(point - vec2(0.0, step_size), shape)) / (2.0 * step_size);
			vec2 bend = -gradient / max(length(gradient), 1.0);
			vec2 shift = bend * lens_refraction * SCREEN_PIXEL_SIZE * (screen_size.y / 900.0) * mask;
			sample_uv += shift;
			drop_mask = max(drop_mask, mask);
			drop_blur = max(drop_blur, lens_blur * mask);
			float rim = smoothstep(0.7, 0.88, radius) * (1.0 - smoothstep(0.88, 1.0, radius));
			float lighting = dot(bend, normalize(vec2(-0.5, -0.85)));
			highlight += rim * max(lighting, 0.0) * lens_rim_strength * drop.w * protection;
			shade += rim * max(-lighting, 0.0) * lens_rim_strength * 0.25 * drop.w * protection;
			if (lens_light_response > 0.0 && mask > 0.0) {
				// Gather existing bright pixels through the same optical field.
				// Lamp/halo colors travel with the scene, rather than a white decal.
				vec2 spread = bend * drop_radius * 0.16 * SCREEN_PIXEL_SIZE;
				float light_lod = log2(1.0 + drop_radius * 0.08);
				vec3 light = textureLod(blurred_screen, SCREEN_UV + shift, light_lod).rgb * 0.5;
				light += textureLod(blurred_screen, SCREEN_UV + shift + spread, light_lod).rgb * 0.25;
				light += textureLod(blurred_screen, SCREEN_UV + shift - spread, light_lod).rgb * 0.25;
				float brightness = max(light.r, max(light.g, light.b));
				float focus = rim * 0.75 + lens_height(point, shape) * 0.18;
				light_bleed += light * smoothstep(0.5, 0.9, brightness) * lens_light_response * focus * mask;
			}
		}
	}
	vec3 color = texture(screen_texture, sample_uv).rgb;
	float blur_lod = log2(1.0 + drop_blur);
	float blur_mask = drop_mask;
	if (ellipse_enabled && ellipse_blur_amount > 0.0) {
		float radius = length((SCREEN_UV - ellipse_center) / max(ellipse_radius, vec2(0.01)));
		float mask = smoothstep(1.0, 1.0 + max(ellipse_transition, 0.01), radius);
		blur_lod = max(blur_lod, log2(1.0 + ellipse_blur_amount * 64.0 * mask));
		blur_mask = max(blur_mask, mask);
	}
	if (blur_lod > 0.0) {
		color = mix(color, textureLod(blurred_screen, sample_uv, blur_lod).rgb, blur_mask);
	}
	color = color * (1.0 - min(shade, 0.5)) + vec3(highlight) + light_bleed;
	float luma = dot(color, vec3(0.3, 0.59, 0.11));
	vec3 toned = color * mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.7, luma));
	color = mix(color, toned, split_toning);
	vec2 centered = (SCREEN_UV - 0.5) * vec2(1.0, 0.8);
	float vignette = smoothstep(vignette_radius, vignette_radius * 0.35, length(centered) * 1.6);
	color *= mix(1.0 - vignette_strength, 1.0, vignette);
	COLOR = vec4(color, 1.0);
}

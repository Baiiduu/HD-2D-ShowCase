shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform float root_uv = 0.9166667;
uniform float flexibility = 0.055;
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.6;
uniform float gust_strength = 0.3;
uniform float wind_time = 0.0;

group_uniforms lighting;
uniform bool lighting_enabled = true;
uniform bool stable_shadows = true;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float root_occlusion : hint_range(0.0, 0.8) = 0.3;
uniform float backlight_strength : hint_range(0.0, 0.5) = 0.12;
varying vec3 clump_direction;
varying float wind_lean;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xz;
	float facing = fract(sin(dot(origin, vec2(12.9898, 78.233))) * 43758.5453) * TAU;
	clump_direction = vec3(cos(facing), 0.0, sin(facing));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	// A fixed card silhouette in the shadow pass prevents Q/E from turning the caster.
	// This is a stylized clump shadow, not exact three-dimensional leaf geometry.
	if (lighting_enabled && stable_shadows && IN_SHADOW_PASS) {
		forward = clump_direction;
		right = cross(vec3(0.0, 1.0, 0.0), forward);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(forward, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float weight = pow(clamp((root_uv - UV.y) / root_uv, 0.0, 1.0), 1.8);
	float phase = dot(origin, vec2(0.79, 1.37));
	float gust = 1.0 + gust_strength * sin(wind_time * 0.47 + dot(origin, vec2(0.13, 0.19)));
	float wave = sin(wind_time * wind_speed + phase) + 0.22 * sin(wind_time * wind_speed * 1.83 + phase * 2.1);
	vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
	float bend = wave * gust * wind_strength * flexibility * weight;
	VERTEX.x += dot(wind, right) * bend;
	VERTEX.z += dot(wind, forward) * bend * 0.4;
	// The displayed card faces the camera; its lighting basis stays in the world.
	wind_lean = wave * gust * wind_strength * flexibility * weight;
}

void fragment() {
	vec4 sprite = texture(sprite_texture, UV);
	ALBEDO = sprite.rgb;
	ALPHA = sprite.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	if (lighting_enabled) {
		float height = clamp((root_uv - UV.y) / root_uv, 0.0, 1.0);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), clump_direction);
		float leaf = (UV.x - 0.5) * 0.45 + (sprite.g - sprite.r) * 0.2;
		vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
		vec3 world_normal = normalize(vec3(0.0, 1.0, 0.0)
			+ normal_strength * (clump_direction * (0.35 + height * 0.25) + side * leaf)
			+ wind * wind_lean * 0.5);
		NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
		float root = 1.0 - smoothstep(0.0, 0.48, height);
		ALBEDO *= 1.0 - root_occlusion * root * 0.45;
		AO = 1.0 - root_occlusion * root;
		AO_LIGHT_AFFECT = 0.25;
		// Native backlighting respects the real lights and their attenuation/shadows.
		BACKLIGHT = vec3(backlight_strength * smoothstep(0.12, 0.8, height));
	}
}

shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool lighting_enabled = true;
uniform float light_wrap : hint_range(0.0, 0.8) = 0.3;
uniform float top_light_response : hint_range(0.0, 1.0) = 0.4;
uniform float back_rim_strength : hint_range(0.0, 0.5) = 0.12;
// The water proxy shares lighting, with its own camera and clipping plane.
uniform bool mirror_view = false;
uniform float clip_height = -10000.0;
uniform bool fixed_y = true;
uniform bool flip_h = false;
uniform bool flip_v = false;
varying vec3 world_position;
varying vec3 world_up_view;
varying vec3 card_right_view;
varying vec3 card_up_view;
varying vec3 edge_normal;
varying float edge_amount;

void vertex() {
	mat4 camera = mirror_view ? INV_VIEW_MATRIX : MAIN_CAM_INV_VIEW_MATRIX;
	vec3 right = normalize(camera[0].xyz);
	vec3 up = normalize(camera[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 billboard = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
	world_up_view = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	card_right_view = mat3(VIEW_MATRIX) * right;
	card_up_view = mat3(VIEW_MATRIX) * up;
}

void fragment() {
	if (world_position.y < clip_height) { discard; }
	vec2 uv = mirror_view ? vec2(flip_h ? 1.0 - UV.x : UV.x, flip_v ? 1.0 - UV.y : UV.y) : UV;
	vec4 color = texture(sprite_texture, uv) * tint;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	edge_normal = vec3(0.0);
	edge_amount = 0.0;
	if (lighting_enabled && back_rim_strength > 0.0) {
		vec2 pixel = 1.0 / vec2(textureSize(sprite_texture, 0));
		float left = texture(sprite_texture, uv - vec2(pixel.x, 0.0)).a;
		float right = texture(sprite_texture, uv + vec2(pixel.x, 0.0)).a;
		float above = texture(sprite_texture, uv - vec2(0.0, pixel.y)).a;
		float below = texture(sprite_texture, uv + vec2(0.0, pixel.y)).a;
		vec2 outward = vec2(left - right, below - above);
		outward *= vec2(flip_h ? -1.0 : 1.0, flip_v ? -1.0 : 1.0);
		edge_amount = clamp(length(outward), 0.0, 1.0);
		edge_normal = (card_right_view * outward.x + card_up_view * outward.y) / max(length(outward), 0.001);
	}
}

void light() {
	float facing = dot(NORMAL, LIGHT);
	float diffuse = max(facing, 0.0);
	if (lighting_enabled) {
		// Approximate a solid body's broad response, rather than transmitting light through clothing.
		float wrapped = max(facing + light_wrap, 0.0) / (1.0 + light_wrap);
		float upper = max(dot(normalize(world_up_view), LIGHT), 0.0) * 0.75;
		diffuse = mix(wrapped, max(wrapped, upper), top_light_response);
		float back = 1.0 - smoothstep(-0.35, 0.25, facing);
		float rim = edge_amount * back * max(dot(edge_normal, LIGHT) + back * 0.15, 0.0);
		diffuse += rim * back_rim_strength;
	}
	// Includes native distance/cone attenuation and shadow visibility. No emission or extra lamp.
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
}

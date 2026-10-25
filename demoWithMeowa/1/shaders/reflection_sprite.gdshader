shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float clip_height = 0.0;
uniform bool fixed_y = true;
uniform bool flip_h = false;
uniform bool flip_v = false;
varying vec3 world_position;

void vertex() {
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 billboard = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0), vec4(up * length(MODEL_MATRIX[1].xyz), 0.0), vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_position.y < clip_height) { discard; }
	vec2 uv = vec2(flip_h ? 1.0 - UV.x : UV.x, flip_v ? 1.0 - UV.y : UV.y);
	vec4 color = texture(sprite_texture, uv) * tint;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}

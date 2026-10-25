shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 rain_color : source_color = vec4(0.65, 0.76, 0.84, 0.24);
uniform vec2 slant = vec2(0.08, 0.02);

void vertex() {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(forward, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX.x -= VERTEX.y * dot(vec3(slant.x, 0.0, slant.y), right);
}

void fragment() {
	float width = 1.0 - smoothstep(0.05, 0.5, abs(UV.x - 0.5));
	float tail = sin(UV.y * PI);
	float distance_fade = smoothstep(1.5, 3.0, length(VERTEX)) * (1.0 - smoothstep(18.0, 32.0, length(VERTEX)));
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a * width * tail * distance_fade;
}

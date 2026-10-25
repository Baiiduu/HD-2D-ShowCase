shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled;

uniform float energy : hint_range(0.0, 2.0, 0.05) = 0.45;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float edge = 1.0 - smoothstep(0.45, 1.0, length(UV - 0.5) * 2.0);
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a * edge;
	ROUGHNESS = 1.0;
}

void light() {
	// Isotropic scattering at a dust mote; native attenuation includes shadows.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION;
}

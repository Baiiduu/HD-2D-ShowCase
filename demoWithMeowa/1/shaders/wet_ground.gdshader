shader_type spatial;
render_mode cull_disabled;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float outline = 0.77 + 0.08 * sin(angle * 5.0) + 0.06 * cos(angle * 9.0);
	if (length(p) > outline) {
		discard;
	}
	ALBEDO = vec3(0.035, 0.075, 0.11);
	ROUGHNESS = 0.065;
	METALLIC = 0.0;
	SPECULAR = 1.0;
}

shader_type spatial;
render_mode unshaded, cull_disabled;

float band(float radius, float target, float width) {
	return 1.0 - step(width, abs(radius - target));
}

void fragment() {
	vec2 p = (floor(UV * 128.0) / 128.0 - 0.5) * 2.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float outer = band(radius, 0.88, 0.013);
	float inner = band(radius, 0.73, 0.012);
	float middle = band(radius, 0.39, 0.016);
	float glyphs = step(0.78, cos(angle * 12.0)) * step(0.57, radius) * (1.0 - step(0.67, radius));
	float spokes = step(0.995, cos(angle * 6.0)) * step(0.41, radius) * (1.0 - step(0.72, radius));
	if (max(max(outer, inner), max(middle, max(glyphs, spokes))) < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.1, 0.42, 0.34);
	EMISSION = vec3(0.12, 0.85, 0.63) * 1.8;
}

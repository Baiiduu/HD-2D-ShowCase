shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.7, 0.4);
uniform float intensity = 2.0;

varying float tw;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	tw = 0.8 + 0.2 * sin(TIME * (0.5 + INSTANCE_CUSTOM.g * 2.0) + INSTANCE_CUSTOM.r * 30.0);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float a = (1.0 - smoothstep(0.08, 0.2, max(abs(q.x), abs(q.y)))) + exp(-d * d * 6.0) * 0.35;
	a *= 1.0 - smoothstep(0.8, 1.0, d);
	ALBEDO = color * a * intensity * tw * COLOR.rgb;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.85, 1.0, 0.45);
uniform float intensity = 3.0;

varying float blink;

float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	float id = float(INSTANCE_ID);
	float rate = 0.6 + h11(id) * 1.1;
	float ph = h11(id + 3.7) * 6.283;
	float b = 0.5 + 0.5 * sin(TIME * rate + ph);
	blink = (0.25 + 0.75 * b * b) * COLOR.a;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	// pixel-ish core (2x2 texel look) plus a soft halo
	float core = 1.0 - smoothstep(0.1, 0.16, max(abs(q.x), abs(q.y)));
	float halo = exp(-d * d * 7.0) * 0.45;
	float a = (core * 1.6 + halo) * (1.0 - smoothstep(0.8, 1.0, d));
	ALBEDO = color * a * intensity * blink;
}

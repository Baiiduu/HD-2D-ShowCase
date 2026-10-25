shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.55;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * strength;
	ALBEDO = vec3(1.0 - a);
}

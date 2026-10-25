shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 细小亮核与柔和圆形光晕；独立的透明轮廓不依赖全局泛光。

uniform vec4 glow_color : source_color = vec4(0.75, 1.0, 0.45, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.6;
uniform float softness : hint_range(0.0, 1.0) = 0.7;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.55;
uniform float pulse_speed : hint_range(0.0, 2.0) = 0.35;

varying flat float pulse;

void vertex() {
	// Preserve random particle sizes when replacing the orientation for billboarding.
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
	float seed = fract(sin(float(INSTANCE_ID) * 12.9898 + 0.37) * 43758.5453);
	float wave = 0.5 + 0.5 * sin(TIME * TAU * pulse_speed * mix(0.8, 1.2, seed) + seed * TAU);
	pulse = mix(1.0, 0.2 + 0.8 * wave * wave, pulse_strength);
}

void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	float core_width = mix(0.26, 0.18, softness);
	float halo_width = mix(0.3, 0.65, softness);
	float core = exp(-radius * radius / (core_width * core_width));
	float halo = exp(-radius * radius / (halo_width * halo_width));
	float edge = 1.0 - smoothstep(0.75, 1.0, radius);
	float halo_weight = softness * 0.22;
	ALBEDO = glow_color.rgb * energy * pulse;
	ALPHA = (core + halo * halo_weight) / (1.0 + halo_weight) * edge * COLOR.a * glow_color.a;
}

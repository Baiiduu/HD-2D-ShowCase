shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, diffuse_burley;

#include "res://shaders/pixel.gdshaderinc"

uniform sampler2D tex_water : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fall_speed = 1.6;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float len = UV2.x;
	float v = UV.y;              // metres along the fall, 0 = lip
	float s = v / max(len, 0.01);
	// accelerate: phase grows faster further down
	float phase = v + v * v * 0.6;
	vec2 tq = vec2(floor(UV.x * 64.0) / 64.0, floor(v * 40.0) / 40.0);
	vec2 uv = vec2(UV.x, phase * 0.5 - TIME * fall_speed);
	vec3 w = px_sample(tex_water, uv * vec2(1.0, 1.0), vec2(64.0, 64.0)).rgb;
	float streak = vnoise(vec2(tq.x * 40.0, phase * 3.0 - TIME * fall_speed * 6.0));
	float streak2 = hash12(vec2(tq.x * 64.0, 1.0));
	float l = px_lum(w);
	float white = smoothstep(0.55, 0.9, l * 0.7 + streak * 0.5 + streak2 * 0.15);
	vec3 col = mix(vec3(0.3, 0.46, 0.48), vec3(0.92, 0.96, 0.95), white);
	// lip highlight and churning foot
	col = mix(col, vec3(0.92, 0.95, 0.94), smoothstep(0.75, 1.0, s) * 0.8);
	col = mix(col, vec3(0.6, 0.75, 0.76), (1.0 - smoothstep(0.0, 0.08, s)) * 0.5);
	float side = UV2.y; // 0..1 across the width
	float a = 0.82 + 0.18 * white;
	a *= smoothstep(0.0, 0.06, side) * smoothstep(1.0, 0.94, side);
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
	EMISSION = col * (0.22 + 0.25 * white);
}

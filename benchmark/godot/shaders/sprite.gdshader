shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://shaders/pixel.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool flip_h = false;
uniform float self_light = 0.08;

void vertex() {
	// Y-axis billboard: stay upright, turn toward the viewer (or the light in shadow passes).
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec3 xa = cross(up, back);
	if (length(xa) < 1e-3) xa = vec3(1.0, 0.0, 0.0);
	xa = normalize(xa);
	vec3 za = normalize(cross(xa, up));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(xa * sx, 0.0), vec4(up * sy, 0.0), vec4(za, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	if (flip_h) uv.x = 1.0 - uv.x;
	vec4 c = px_sample(tex, uv, vec2(64.0));
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Face the camera but lean the normal upward so moonlight from above reads on the figure.
	NORMAL = normalize(vec3(0.0, 0.45, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	EMISSION = c.rgb * self_light;
}

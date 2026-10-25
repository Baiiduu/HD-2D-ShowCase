shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec3 color : source_color = vec3(0.78, 0.82, 0.84);
uniform float opacity = 0.22;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float a = (1.0 - smoothstep(0.2, 1.0, d));
	a *= a;
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vp.xyz /= vp.w;
	a *= clamp((VERTEX.z - vp.z) / 0.35, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = a * opacity * COLOR.a;
}

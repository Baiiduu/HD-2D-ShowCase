shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.75, 0.45);
uniform float intensity = 0.5;
uniform float core = 0.15;
uniform float pull = 0.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	// spherical billboard, nudged toward the camera so the lamp body never clips it
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam - center);
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c2 = center + to_cam * pull;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(c2, 1.0));
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q);
	float glow = exp(-d * d * 4.5) * 0.65 + exp(-d * 9.0) * 0.6;
	glow += (1.0 - smoothstep(0.0, core, d)) * 0.4;
	glow *= 1.0 - smoothstep(0.75, 1.0, d);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vp.xyz /= vp.w;
	float fade = clamp((VERTEX.z - vp.z) / 0.6, 0.0, 1.0);
	ALBEDO = color * glow * intensity * fade;
}

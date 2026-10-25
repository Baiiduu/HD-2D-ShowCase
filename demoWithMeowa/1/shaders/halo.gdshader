shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 灯光光晕：始终朝向镜头的加色面片，径向衰减，按像素网格量化保持像素风。
// 颜色用实例参数，同一个材质可以给不同颜色的灯使用。

instance uniform vec4 halo_color : source_color = vec4(1.0, 0.82, 0.58, 1.0);
uniform float energy = 0.35;
// 光晕直径上的像素数
uniform float pixels = 28.0;
uniform float falloff = 2.4;
// Street lamps keep a small luminous core and a restrained, warm outer halo.
uniform bool street_style = false;
uniform float front_offset = 0.0;
// Only mirror cameras use layers 19/20; the main camera omits those bits.
uniform float reflection_height_0 = -0.32;
uniform float reflection_height_1 = 0.48;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[3].xyz += normalize(-MODELVIEW_MATRIX[3].xyz) * front_offset;
}

void fragment() {
	float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	if (((CAMERA_VISIBLE_LAYERS & 262144u) != 0u && world_y < reflection_height_0 + 0.005) ||
		((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_y < reflection_height_1 + 0.005)) { discard; }
	vec2 uv = (floor(UV * pixels) + 0.5) / pixels;
	float r = length(uv - 0.5) * 2.0;
	float intensity = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	if (street_style) {
		r = length(UV - 0.5) * 2.0;
		intensity = (exp(-r * r * 52.0) * 0.75 + exp(-r * r * 9.0) * 0.22) * (1.0 - smoothstep(0.65, 1.0, r));
	}
	ALBEDO = halo_color.rgb * energy * intensity;
}

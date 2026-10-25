shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float height = 2.36;
uniform float gain : hint_range(0.0, 2.0, 0.005) = 0.055;
instance uniform vec3 lamp_position = vec3(0.0);
varying float beam_depth;
varying vec3 world_position;

void vertex() {
	beam_depth = 0.5 - VERTEX.y / height;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float falloff = pow(1.0 - beam_depth, 2.0) * 0.85 + 0.15;
	float floor_fade = 1.0 - smoothstep(0.65, 1.0, beam_depth);
	float source_fade = smoothstep(0.0, 0.12, beam_depth);
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec4 background = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float separation = -background.z / background.w + VERTEX.z;
	float contact_fade = smoothstep(0.0, 0.18, separation);
	ALBEDO = vec3(1.0);
	ALPHA = facing * falloff * source_fade * floor_fade * contact_fade * 0.22;
}

void light() {
	// Only the street spots affect layer 18. Their native attenuation supplies
	// actual shadow occlusion; distance compensation keeps the stylized cone legible.
	float distance_squared = dot(world_position - lamp_position, world_position - lamp_position);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(distance_squared, 0.03) * gain;
}

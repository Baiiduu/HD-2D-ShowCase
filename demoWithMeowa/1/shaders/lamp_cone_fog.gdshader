shader_type fog;

// Density only: native spot lighting and its shadow map illuminate this volume.
// Unlike an emissive cone, blocked regions of the beam remain dark.
uniform float density : hint_range(0.0, 0.3, 0.005) = 0.085;
uniform float texture_strength : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float wisp_scale : hint_range(0.25, 4.0, 0.05) = 1.0;
uniform float drift_speed : hint_range(0.0, 0.2, 0.005) = 0.035;
uniform vec3 scattering_color : source_color = vec3(0.9, 0.92, 0.95);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float soft_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(cell), hash(cell + vec3(1, 0, 0)), f.x),
		mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), f.x),
		mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fog() {
	float depth = 1.0 - UVW.y;
	float radius = mix(0.035, 0.5, clamp(depth, 0.0, 1.0));
	float radial = length(UVW.xz - vec2(0.5)) / radius;
	// Continuous radial falloff avoids a solid cone silhouette; fade before the floor.
	float edge = exp(-radial * radial * 1.3) * (1.0 - smoothstep(0.65, 1.0, radial));
	float ends = smoothstep(0.0, 0.08, depth) * (1.0 - smoothstep(0.82, 1.0, depth));
	float wisps = soft_noise(WORLD_POSITION * vec3(3.0, 1.2, 3.0) * wisp_scale + vec3(TIME * drift_speed, 0.0, 0.0));
	float texture = mix(1.0, mix(0.3, 1.5, wisps), texture_strength);
	DENSITY = density * edge * ends * mix(1.0, 0.7, depth) * texture;
	ALBEDO = scattering_color;
}

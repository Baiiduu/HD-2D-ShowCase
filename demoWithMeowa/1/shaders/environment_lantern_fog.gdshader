shader_type fog;

// Density only: native lights and shadow maps provide illumination and occlusion.
uniform float density = 0.10;
uniform float texture_strength = 0.7;
uniform float ground_haze = 0.75;
uniform vec2 wind = vec2(0.06, 0.02);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(cell), hash(cell + vec3(1, 0, 0)), f.x),
		mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), f.x),
		mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fog() {
	float radial = length((UVW.xz - 0.5) * 2.0);
	float edge = exp(-radial * radial * 3.0) * (1.0 - smoothstep(0.65, 1.0, radial));
	float ends = smoothstep(0.0, 0.14, UVW.y) * (1.0 - smoothstep(0.65, 1.0, UVW.y));
	float low = exp(-pow((UVW.y - 0.25) * 4.0, 2.0));
	vec3 drift = vec3(wind.x, 0.0, wind.y) * TIME;
	float wisps = noise((WORLD_POSITION - drift) * vec3(2.4, 3.0, 2.4));
	float texture = mix(1.0, mix(0.25, 1.6, wisps), texture_strength);
	DENSITY = density * edge * ends * mix(0.45, low * 1.4, ground_haze) * texture;
	ALBEDO = vec3(0.88, 0.92, 0.96);
}

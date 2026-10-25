// Local rain impacts in world space. Returns ring, normal X/Z and birth flash.
float rain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 rain_surface(vec2 position, float clock, float density, float radius, float lifetime) {
	vec4 result = vec4(0.0);
	if (density <= 0.0) { return result; }
	float period = max(1.35, lifetime * 1.2);
	// One event per cell per period; nearby cells have independent phases.
	// Bound spacing so the nine sampled cells cover the complete wave radius.
	float scale = min(sqrt(density * period), 1.0 / max(radius, 0.01));
	vec2 cell = floor(position * scale);
	float aa = max(length(fwidth(position)) * 0.7, 0.002);
	for (int z = -1; z <= 1; z++) {
		for (int x = -1; x <= 1; x++) {
			vec2 tile = cell + vec2(float(x), float(z));
			float phase = clock / period + rain_hash(tile + 19.7);
			float age = fract(phase) * period;
			if (age >= lifetime) { continue; }
			float cycle = floor(phase);
			vec2 jitter = vec2(rain_hash(tile + cycle * 7.31), rain_hash(tile + cycle * 11.73 + 8.7));
			vec2 center = (tile + 0.15 + jitter * 0.7) / scale;
			vec2 offset = position - center;
			float distance = length(offset);
			float progress = age / lifetime;
			float wave_radius = radius * (0.12 + progress * 0.88);
			float width = max(0.008, radius * 0.07);
			float ring = 1.0 - smoothstep(width, width + aa, abs(distance - wave_radius));
			float fade = smoothstep(0.0, 0.08, progress) * pow(1.0 - progress, 1.5);
			vec2 gradient = offset / max(distance, 0.001) * clamp((distance - wave_radius) / width, -1.0, 1.0) * ring * fade;
			float flash = (1.0 - smoothstep(0.0, radius * 0.18, distance)) * (1.0 - smoothstep(0.0, 0.2, progress));
			result += vec4(ring * fade, gradient, flash);
		}
	}
	return result;
}

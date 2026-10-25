shader_type sky;

uniform vec3 zenith : source_color = vec3(0.035, 0.045, 0.1);
uniform vec3 mid : source_color = vec3(0.12, 0.11, 0.2);
uniform vec3 horizon : source_color = vec3(0.36, 0.27, 0.27);
uniform vec3 ground : source_color = vec3(0.12, 0.1, 0.1);

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h > 0.0) {
		float t = pow(h, 0.5);
		col = mix(horizon, mid, smoothstep(0.0, 0.35, t));
		col = mix(col, zenith, smoothstep(0.3, 1.0, t));
	} else {
		col = mix(horizon, ground, smoothstep(0.0, 0.2, -h));
	}
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		// stars, blocky like pixel art
		vec2 sp = vec2(atan(d.x, d.z), asin(h)) * 260.0;
		vec2 cell = floor(sp);
		float r = h21(cell);
		float star = step(0.9965, r) * (0.4 + 0.6 * h21(cell + 7.0));
		star *= 0.7 + 0.3 * sin(TIME * (1.0 + 3.0 * h21(cell + 3.0)) + r * 40.0);
		col += vec3(1.0, 0.92, 0.82) * star * smoothstep(0.02, 0.2, h) * 1.4;
		// thin drifting cloud bands catching the town glow
		float c = vn(vec2(atan(d.x, d.z) * 6.0 + TIME * 0.004, h * 30.0));
		c *= vn(vec2(atan(d.x, d.z) * 17.0, h * 70.0));
		col = mix(col, vec3(0.42, 0.32, 0.32), smoothstep(0.25, 0.6, c) * 0.35 * (1.0 - smoothstep(0.05, 0.35, h)));
	}
	// moon glow (moon sits behind the camera, but brightens that half of the sky)
	float m = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += vec3(0.5, 0.48, 0.45) * pow(m, 24.0) * 0.4 + vec3(0.12, 0.11, 0.1) * pow(m, 3.0) * 0.4;
	if (!AT_CUBEMAP_PASS) {
		col += vec3(1.0, 0.97, 0.9) * smoothstep(0.9995, 0.9997, m) * 3.0;
	}
	COLOR = col;
}

// 水面与落水白沫共用世界像素尺度，纹理随水流连续移动。
float foam_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float foam_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(foam_hash(i), foam_hash(i + vec2(1.0, 0.0)), f.x),
		mix(foam_hash(i + vec2(0.0, 1.0)), foam_hash(i + vec2(1.0)), f.x), f.y);
}

float foam_patches(vec2 position, float time, float scale, float density, vec2 drift) {
	float pixel_size = 0.025 * scale;
	vec2 pixel = (floor(position / pixel_size) + 0.5) * pixel_size;
	vec2 uv = (pixel - drift * time) / scale;
	float clusters = foam_noise(uv * 7.0) * 0.7 + foam_noise(uv * 21.0 + 13.1) * 0.3;
	float threshold = mix(0.60, 0.30, density);
	return smoothstep(threshold, threshold + 0.13, clusters);
}

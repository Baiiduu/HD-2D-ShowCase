shader_type sky;

// 像素风雾夜天空：天幕渐变 + 星星 + 月晕 + 地平线雾带，
// 地平线附近是几层"雾中剪影"（远山 → 四排松林），越远越小、越亮、越接近雾色，
// 每排松林的树脚融进雾里。所有图案按固定角度步长量化，保持像素块面。
// 不使用 TIME，天空反射只需烘焙一次。

uniform vec3 zenith_color : source_color = vec3(0.02, 0.04, 0.08);
uniform vec3 horizon_color : source_color = vec3(0.2, 0.32, 0.4);
// 地平线雾带：整片天空最亮的地方，与环境雾同色
uniform vec3 fog_color : source_color = vec3(0.2, 0.32, 0.4);
// 剪影最近一层的颜色，远层逐渐向雾色靠拢
uniform vec3 silhouette_color : source_color = vec3(0.06, 0.1, 0.14);
// 北方地平线（城市方向）的暖色辉光
uniform vec3 glow_color : source_color = vec3(0.55, 0.32, 0.2);
uniform float glow_strength = 0.35;
uniform vec3 moon_glow_color : source_color = vec3(0.6, 0.7, 0.9);
uniform float star_density : hint_range(0.0, 0.05) = 0.01;
// 每个"天空像素"对应的角度（弧度）
uniform float pixel_angle = 0.004;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(vec2(i, 0.0)), hash(vec2(i + 1.0, 0.0)), f);
}

float ridge(float azimuth, float base, float height, float frequency, float seed) {
	float n = noise(azimuth * frequency + seed) * 0.6 + noise(azimuth * frequency * 2.7 + seed * 3.1) * 0.3
		+ noise(azimuth * frequency * 7.0 + seed) * 0.1;
	return base + n * height;
}

// 松林线：每棵树占一个角度格子，高度随机，轮廓是分层的阶梯三角形（像素风松树）
float pine_line(float azimuth, float base, float tree_width, float tree_height, float seed) {
	float shifted = azimuth + hash(vec2(seed, 1.0)) * tree_width;
	float cell = floor(shifted / tree_width);
	float x = fract(shifted / tree_width);
	float h = hash(vec2(cell, seed));
	// 高矮有差异，偶尔夹一棵矮树，避免像一排栅栏
	float height = tree_height * mix(0.5, 1.0, h) * (hash(vec2(cell, seed + 3.0)) < 0.2 ? 0.45 : 1.0);
	x = (x - 0.5) / mix(0.75, 1.0, hash(vec2(cell, seed + 7.0))) + 0.5;
	float profile = 1.0 - clamp(abs(x * 2.0 - 1.0), 0.0, 1.0);
	profile = floor(profile * 5.0) / 5.0;
	// 树与树之间的林冠高度
	float canopy = tree_height * 0.25 * (0.6 + 0.4 * noise(azimuth / tree_width * 0.3 + seed));
	return base + max(height * profile, canopy);
}

// 一排雾中松林：树冠是剪影色，越往下越融进雾里
vec3 forest_layer(vec3 color, float azimuth, float elevation, float base, float tree_width, float tree_height,
		float depth, float seed) {
	float line = pine_line(azimuth, base, tree_width, tree_height, seed);
	if (elevation < line) {
		vec3 layer_color = mix(fog_color, silhouette_color, depth);
		float mist = smoothstep(base + tree_height * 0.2, base - tree_height * 0.6, elevation);
		color = mix(layer_color, fog_color, mist * 0.7);
	}
	return color;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float azimuth = floor(atan(dir.x, -dir.z) / pixel_angle) * pixel_angle;
	float elevation = floor(asin(clamp(dir.y, -1.0, 1.0)) / pixel_angle) * pixel_angle;

	// 天幕：地平线处是最亮的雾带，往上逐渐变暗
	float t = clamp(elevation / 0.8, 0.0, 1.0);
	vec3 color = mix(horizon_color, zenith_color, pow(t, 0.5));
	color = mix(color, fog_color, exp(-max(elevation, 0.0) * 25.0));
	float north = pow(max(cos(azimuth), 0.0), 3.0);
	color += glow_color * glow_strength * north * exp(-max(elevation, 0.0) * 12.0);

	vec2 cell = vec2(floor(azimuth / pixel_angle), floor(elevation / pixel_angle));
	float star = step(1.0 - star_density * smoothstep(0.08, 0.4, elevation), hash(cell));
	color += vec3(0.75, 0.82, 1.0) * star * (0.35 + 0.5 * hash(cell + 13.0));

	if (LIGHT0_ENABLED) {
		float moon = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		color += moon_glow_color * (pow(moon, 80.0) * 0.5 + pow(moon, 8.0) * 0.06);
	}

	// 雾中剪影，从远到近：远山，然后四排松林，越近越大、越暗
	vec3 far_tint = mix(fog_color, silhouette_color, 0.25) + glow_color * glow_strength * north * 0.2;
	if (elevation < ridge(azimuth, -0.005, 0.045, 4.0, 3.0)) {
		color = far_tint;
	}
	color = forest_layer(color, azimuth, elevation, -0.02, 0.016, 0.022, 0.38, 5.0);
	color = forest_layer(color, azimuth, elevation, -0.045, 0.024, 0.032, 0.52, 9.0);
	color = forest_layer(color, azimuth, elevation, -0.08, 0.034, 0.045, 0.66, 13.0);
	color = forest_layer(color, azimuth, elevation, -0.125, 0.05, 0.06, 0.8, 17.0);
	// 最近一排松林以下：雾气笼罩的林地，往下渐暗
	if (elevation < -0.125) {
		color = mix(mix(fog_color, silhouette_color, 0.85), fog_color, 0.5 * smoothstep(-0.4, -0.125, elevation));
	}
	COLOR = color;
}

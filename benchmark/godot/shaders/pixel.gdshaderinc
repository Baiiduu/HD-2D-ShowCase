// Shared helpers for crisp pixel-art sampling and procedural noise.

// "Fat pixel" sampling: texels stay perfectly square, but the edge between two texels
// is anti-aliased over exactly one screen pixel. With a linear+mipmap sampler this
// removes both blur (magnified) and shimmering (minified).
vec4 px_sample_g(sampler2D tex, vec2 uv, vec2 size, vec2 duvdx, vec2 duvdy) {
	vec2 p = uv * size - 0.5;
	vec2 fw = max(abs(duvdx * size) + abs(duvdy * size), vec2(1e-4));
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = clamp((f - 0.5) / fw + 0.5, 0.0, 1.0);
	return textureGrad(tex, (i + f + 0.5) / size, duvdx, duvdy);
}

vec4 px_sample(sampler2D tex, vec2 uv, vec2 size) {
	return px_sample_g(tex, uv, size, dFdx(uv), dFdy(uv));
}

float px_lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Per-texel luminance gradient (central differences on the texel grid). Gives every
// pixel-art texel its own little bevel so lamps rake across stones and planks.
vec2 px_bump(sampler2D tex, vec2 uv, vec2 size, float fw) {
	float fade = 1.0 - smoothstep(0.7, 2.2, fw);
	if (fade <= 0.0) {
		return vec2(0.0);
	}
	vec2 c = (floor(uv * size) + 0.5) / size;
	vec2 ts = 1.0 / size;
	float lx0 = px_lum(textureLod(tex, c - vec2(ts.x, 0.0), 0.0).rgb);
	float lx1 = px_lum(textureLod(tex, c + vec2(ts.x, 0.0), 0.0).rgb);
	float ly0 = px_lum(textureLod(tex, c - vec2(0.0, ts.y), 0.0).rgb);
	float ly1 = px_lum(textureLod(tex, c + vec2(0.0, ts.y), 0.0).rgb);
	return vec2(lx1 - lx0, ly1 - ly0) * 0.5 * fade;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

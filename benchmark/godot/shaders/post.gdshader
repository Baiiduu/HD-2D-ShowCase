shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float saturation = 1.08;
uniform vec3 shadow_tint = vec3(0.96, 0.98, 1.04);
uniform vec3 highlight_tint = vec3(1.05, 1.0, 0.93);
uniform float contrast = 1.06;
uniform float tilt = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	// subtle tilt-shift: blur only the very top band (far distance) and the bottom edge
	float band = max(smoothstep(0.24, 0.0, uv.y), smoothstep(0.9, 1.0, uv.y) * 0.6);
	if (band > 0.001) {
		vec2 px = 1.0 / vec2(textureSize(screen_tex, 0));
		vec3 acc = c;
		float r = band * 2.2;
		acc += textureLod(screen_tex, uv + vec2( 1.0,  0.0) * px * r, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2(-1.0,  0.0) * px * r, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2( 0.0,  1.0) * px * r, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2( 0.0, -1.0) * px * r, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2( 0.7,  0.7) * px * r * 1.8, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2(-0.7,  0.7) * px * r * 1.8, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2( 0.7, -0.7) * px * r * 1.8, 0.0).rgb;
		acc += textureLod(screen_tex, uv + vec2(-0.7, -0.7) * px * r * 1.8, 0.0).rgb;
		c = mix(c, acc / 9.0, clamp(band * tilt * 1.6, 0.0, 1.0));
	}
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	c *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, l));
	c = (c - 0.5) * contrast + 0.5;
	vec2 vq = (uv - 0.5) * vec2(1.6, 1.0);
	float v = 1.0 - dot(vq, vq) * vignette * 1.1;
	c *= clamp(v, 0.0, 1.0);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}

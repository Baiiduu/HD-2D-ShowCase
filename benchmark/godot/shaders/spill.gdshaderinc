// Cheap "bounce light" from emissive surfaces (windows, neon strips, lanterns).
// Each emitter: spill_pos[i] = (xyz, radius), spill_col[i] = (rgb * strength, 0).
uniform vec4 spill_pos[24];
uniform vec4 spill_col[24];
uniform int spill_count = 0;

vec3 emissive_spill(vec3 wp, vec3 wn) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < spill_count; i++) {
		vec3 d = spill_pos[i].xyz - wp;
		float dist = length(d);
		float r = spill_pos[i].w;
		if (dist < r) {
			float att = 1.0 - dist / r;
			att *= att;
			float facing = clamp(dot(wn, d / max(dist, 1e-3)) * 0.6 + 0.4, 0.0, 1.0);
			acc += spill_col[i].rgb * att * facing;
		}
	}
	return acc;
}

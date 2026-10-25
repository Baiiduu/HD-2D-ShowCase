shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/pixel.gdshaderinc"
#include "res://shaders/spill.gdshaderinc"

// 0 plain, 1 textured (triplanar or mesh uv), 2 plaster wall, 3 roof slab, 4 window,
// 5 lamp box, 6 neon, 7 cyber tower, 8 temple roof, 9 red lantern
uniform int mode = 0;
uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tex_avg = vec3(0.5);
uniform bool use_mesh_uv = false;
uniform bool swap_top_uv = false;
uniform vec2 mesh_uv_scale = vec2(1.0);
uniform vec3 box_half = vec3(0.5);
uniform float ground_y = 0.02;
uniform float seed = 0.0;
uniform float bump_strength = 2.0;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	lnorm = NORMAL;
}

// face-local 2D coords in metres (u horizontal, v vertical/up)
vec2 face_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) return vec2(p.x, -p.z);
	if (a.x > a.z) return vec2(-p.z * sign(n.x), p.y);
	return vec2(p.x * sign(n.z), p.y);
}

vec2 face_half(vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) return box_half.xz;
	if (a.x > a.z) return box_half.zy;
	return box_half.xy;
}

void fragment() {
	vec3 col = albedo;
	float rough = roughness;
	float metal = metallic;
	vec3 emit = vec3(0.0);
	vec2 bump = vec2(0.0);
	vec3 n = wnorm;
	bool vertical = abs(n.y) < 0.6;
	vec2 fuv = face_uv(wpos, n);                  // world metres on the face
	vec2 luv = face_uv(lpos, lnorm);              // local metres on the face
	vec2 fh = face_half(lnorm);
	vec2 px = floor(fuv * 40.0);                  // 40 texels per metre grid

	if (mode == 1 || mode == 7) {
		vec2 uv = use_mesh_uv ? UV * mesh_uv_scale : fuv / 1.6 * vec2(1.0, -1.0);
		if (swap_top_uv && !vertical) uv = uv.yx;
		vec2 gx = dFdx(uv);
		vec2 gy = dFdy(uv);
		vec3 t = px_sample_g(tex, uv, vec2(64.0), gx, gy).rgb;
		col = t / max(tex_avg, vec3(0.05)) * albedo;
		bump = px_bump(tex, uv, vec2(64.0), max(length(gx), length(gy)) * 64.0);
		if (mode == 7 && vertical) {
			// lit apartment slits on the dark towers
			vec2 cellp = floor(vec2(fuv.x / 0.2, fuv.y / 0.3));
			vec2 inside = fract(vec2(fuv.x / 0.2, fuv.y / 0.3));
			float h = hash12(cellp + seed * 13.1);
			float win = step(0.3, inside.x) * step(inside.x, 0.7) * step(0.35, inside.y) * step(inside.y, 0.75);
			win = floor(win * 8.0) / 8.0;
			vec3 wc = h < 0.05 ? vec3(1.0, 0.75, 0.45) : (h < 0.09 ? vec3(0.3, 0.9, 0.95) : (h < 0.11 ? vec3(0.95, 0.35, 0.75) : vec3(0.0)));
			float topcut = step(wpos.y, (box_half.y * 2.0) - 0.2 + ground_y) * step(0.5, wpos.y);
			emit += wc * win * 1.4 * topcut;
			col = mix(col, col * 0.55, win * step(0.11, h));
		}
	} else if (mode == 2) {
		// half-timbered plaster
		float noise = hash12(px + seed) * 0.06 + vnoise(px * 0.15) * 0.08;
		col = albedo * (0.92 + noise);
		bump = vec2(hash12(px + 1.0) - 0.5, hash12(px + 2.0) - 0.5) * 0.12;
		if (vertical) {
			float hy = wpos.y - ground_y;
			float edge = fh.x - abs(luv.x);
			bool beam = edge < 0.13 || abs(hy - 1.88) < 0.07 || hy > box_half.y * 2.0 - 0.14;
			bool plinth = hy < 0.38;
			if (beam) {
				col = vec3(0.24, 0.16, 0.11) * (0.85 + 0.15 * hash12(vec2(px.y, px.x * 0.1)));
				bump = vec2(0.0, (hash12(vec2(floor(px.x / 3.0), px.y)) - 0.5) * 0.15);
			} else if (plinth) {
				vec2 bp = vec2(fuv.x * 40.0 + (mod(floor(hy * 40.0 / 6.0), 2.0) * 5.0), hy * 40.0);
				vec2 br = floor(bp / vec2(10.0, 6.0));
				vec2 bf = fract(bp / vec2(10.0, 6.0));
				float mortar = step(bf.x, 0.1) + step(bf.y, 0.17);
				col = mix(vec3(0.42, 0.39, 0.36) * (0.85 + 0.3 * hash12(br + seed)), vec3(0.2, 0.18, 0.17), clamp(mortar, 0.0, 1.0));
				bump = vec2(step(bf.x, 0.1) - step(0.9, bf.x), step(bf.y, 0.17) - step(0.83, bf.y)) * -0.25;
			}
		}
	} else if (mode == 3) {
		// clay roof tiles
		vec2 tp = px;
		float row = floor(tp.y / 5.0);
		float shift = mod(row, 2.0) * 3.0;
		float colm = floor((tp.x + shift) / 6.0);
		vec2 f = vec2(fract((tp.x + shift) / 6.0), fract(tp.y / 5.0));
		if (!vertical) {
			row = floor(-fuv.y * 40.0 / 5.0);
			f = vec2(fract((tp.x + mod(row, 2.0) * 3.0) / 6.0), fract(-fuv.y * 40.0 / 5.0));
		}
		float shade = 0.8 + 0.35 * f.y + 0.12 * hash12(vec2(colm, row) + seed);
		shade *= mix(1.0, 0.55, step(0.84, f.x));
		col = albedo * shade;
		bump = vec2(step(0.84, f.x) * 0.3, (f.y - 0.5) * 0.25);
	} else if (mode == 4) {
		vec2 q = luv / fh;                       // -1..1 across the window
		vec2 qp = floor(q * vec2(13.0, 17.0)) / vec2(13.0, 17.0);
		float frame = step(0.82, abs(qp.x)) + step(0.86, abs(qp.y)) + step(abs(qp.x), 0.07) + step(abs(qp.y + 0.05), 0.06);
		frame = clamp(frame, 0.0, 1.0);
		float h = hash12(vec2(seed, 3.0));
		float curtain = step(0.55, abs(qp.x)) * step(-0.7, qp.y) * step(0.5, h);
		float grad = 0.75 + 0.35 * (1.0 - (qp.y * 0.5 + 0.5));
		vec3 glass = emission_color * grad * mix(1.0, 0.55, curtain);
		col = mix(albedo, vec3(0.2, 0.13, 0.09), frame);
		emit = glass * emission_energy * (1.0 - frame);
		rough = mix(0.15, 0.8, frame);
	} else if (mode == 5) {
		vec2 q = luv / fh;
		vec2 qp = floor(q * 8.0) / 8.0;
		float frame = clamp(step(0.74, abs(qp.x)) + step(0.74, abs(qp.y)) + step(abs(qp.x), 0.05), 0.0, 1.0);
		if (!vertical) frame = 1.0;
		col = mix(albedo, vec3(0.16, 0.11, 0.08), frame);
		emit = emission_color * emission_energy * (1.0 - frame) * (0.85 + 0.15 * (1.0 - abs(q.y)));
	} else if (mode == 6) {
		float flick = 0.94 + 0.06 * step(0.5, fract(TIME * 0.37 + seed));
		col = albedo;
		emit = emission_color * emission_energy * flick;
	} else if (mode == 8) {
		// glazed teal temple tiles running down the slope
		float along = wpos.x;
		float down = vertical ? wpos.y : (wpos.y * 1.3 + abs(wpos.z - 3.2) * 0.4);
		vec2 tp = vec2(along * 40.0, down * 40.0);
		float ch = fract(tp.x / 7.0);
		float rr = fract(tp.y / 6.0);
		float shade = 0.82 + 0.25 * smoothstep(0.0, 0.5, ch) * smoothstep(1.0, 0.6, ch);
		shade *= mix(0.7, 1.0, step(0.18, rr));
		shade *= 0.92 + 0.12 * hash12(floor(tp / vec2(7.0, 6.0)) + seed);
		col = albedo * shade;
		bump = vec2(ch - 0.5, -step(rr, 0.18)) * 0.3;
		rough = 0.45;
	} else if (mode == 9) {
		float vv = UV.y;                        // 0 top .. 1 bottom
		float band = step(vv, 0.09) + step(0.91, vv);
		float rib = step(0.85, fract(floor(vv * 24.0) / 24.0 * 5.0));
		float around = fract(UV.x * 10.0);
		float glow = 1.0 - abs(vv - 0.5) * 1.3;
		vec3 red = vec3(1.0, 0.24, 0.1);
		vec3 core = emission_color;
		col = mix(vec3(0.75, 0.16, 0.08), vec3(0.3, 0.2, 0.06), clamp(band, 0.0, 1.0));
		vec3 e = mix(red, core, glow * 0.45) * emission_energy * (0.55 + 0.6 * glow);
		e *= mix(1.0, 0.45, rib) * mix(1.0, 0.8, step(0.9, around));
		emit = e * (1.0 - clamp(band, 0.0, 1.0));
		if (!vertical) emit *= 0.0;
	}

	if (emission_energy > 0.0 && mode == 0) {
		emit = emission_color * emission_energy;
	}

	// contact shadow toward the ground
	float hy = wpos.y - ground_y;
	float ao = mix(0.5, 1.0, smoothstep(0.0, 0.7, hy));

	vec3 nwb = n;
	if (length(bump) > 0.0) {
		vec3 tu, tv;
		vec3 a = abs(n);
		if (a.y > a.x && a.y > a.z) { tu = vec3(1.0, 0.0, 0.0); tv = vec3(0.0, 0.0, 1.0); }
		else if (a.x > a.z) { tu = vec3(0.0, 0.0, -sign(n.x)); tv = vec3(0.0, -1.0, 0.0); }
		else { tu = vec3(sign(n.z), 0.0, 0.0); tv = vec3(0.0, -1.0, 0.0); }
		nwb = normalize(n - (tu * bump.x + tv * bump.y) * bump_strength);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nwb, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = emit + col * emissive_spill(wpos, n) * ao;
}

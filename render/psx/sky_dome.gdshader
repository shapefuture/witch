shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

// The sky behind the grove: a low sun in the notch above the way out, peach and coral bands,
// lilac overhead, and a few big stylised cloud banks lit from below. Pure gradient + noise.

global uniform float stage_time;
global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 sun_dir = vec3(-0.36, 0.64, -0.68);
uniform vec3 glow_dir = vec3(0.0, 0.06, -1.0);
uniform vec3 zenith : source_color = vec3(0.86, 0.80, 0.56);
uniform vec3 high : source_color = vec3(0.94, 0.86, 0.62);
uniform vec3 mid : source_color = vec3(0.98, 0.88, 0.60);
uniform vec3 horizon : source_color = vec3(1.0, 0.90, 0.62);
uniform vec3 ground_haze : source_color = vec3(0.70, 0.60, 0.40);

varying vec3 v_dir;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Centred on the camera whatever it does: only the view ROTATION (including roll) applies.
	v_dir = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
	// Far away along the view ray: the projection itself decides what "far" means (the depth
	// convention differs between renderers, so it is never written by hand).
	POSITION = PROJECTION_MATRIX * vec4(mat3(VIEW_MATRIX) * v_dir * 3000.0, 1.0);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float e = d.y;
	vec3 col = mix(ground_haze, horizon, smoothstep(-0.12, 0.02, e));
	col = mix(col, mid, smoothstep(0.02, 0.2, e));
	col = mix(col, high, smoothstep(0.18, 0.5, e));
	col = mix(col, zenith, smoothstep(0.45, 1.0, e));
	vec3 s = normalize(sun_dir);
	float sd = max(dot(d, s), 0.0);
	float g = max(dot(d, normalize(glow_dir)), 0.0);
	col += vec3(1.0, 0.62, 0.3) * pow(g, 5.0) * 0.5;
	col += vec3(1.0, 0.8, 0.5) * pow(sd, 2.5) * 0.7;
	col += vec3(1.0, 0.7, 0.35) * pow(sd, 6.0) * 0.45;
	col += vec3(1.0, 0.86, 0.55) * pow(sd, 40.0) * 0.8;
	col = mix(col, vec3(1.0, 0.97, 0.82), smoothstep(0.9988, 0.9994, sd));
	// cloud banks: stretched noise, hard-ish edges, warm underside, lilac tops
	vec2 p = vec2(d.x, d.z) / (abs(e) + 0.28) * 1.4 + vec2(stage_time * 0.012, 0.0);
	float n = fbm(p * vec2(1.0, 2.6));
	float cloud = smoothstep(0.52, 0.58, n) * smoothstep(0.02, 0.14, e) * (1.0 - smoothstep(0.55, 0.85, e));
	vec3 cloud_col = mix(vec3(0.98, 0.80, 0.52), vec3(0.88, 0.80, 0.62), smoothstep(0.12, 0.45, e));
	cloud_col = mix(cloud_col, vec3(1.0, 0.86, 0.6), pow(sd, 3.0) * 0.8);
	col = mix(col, cloud_col, cloud * 0.85);
	ALBEDO = max(col, vec3(0.0));
}

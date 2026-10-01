// Pre-rendered plates projected onto the hall's proxy geometry (docs/art/PLATE_CONTRACT.md,
// docs/art/compositor.md). View-dependent projective texturing from up to three plates (Debevec 1996):
// slot 0 is the shot's own plate (or the closest one), slot 1 `wide`, slot 2 the best cover. Each
// plate is projected perspective-correctly from its own camera, kept only where that camera saw this
// surface (a shadow-map test against the plate's depth), and weighted by how close its view is to
// ours and how densely its texels cover the surface. Where no plate sees a fragment, the proxy's
// vertex colour (a dim baked fallback) shows. At the plate's own pose the plate IS the picture: no
// depth test, so every screen pixel is exactly the plate pixel whatever the proxy's shape.
//
// Runtime light: beauty * mix(1, sun, key) * mix(1, flicker, glow), plus the spell's tint.
// Display-referred, like the rest of the PSX pipeline: plates are sampled raw and written as is.

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
global uniform vec2 snap_grid;
global uniform float stage_time;
global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;
global uniform float lens_warp : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D beauty_0 : filter_linear, repeat_disable;
uniform sampler2D depth_0 : filter_nearest, repeat_disable;
uniform sampler2D key_0 : filter_linear, repeat_disable;
uniform sampler2D glow_0 : filter_linear, repeat_disable;
uniform sampler2D beauty_1 : filter_linear, repeat_disable;
uniform sampler2D depth_1 : filter_nearest, repeat_disable;
uniform sampler2D key_1 : filter_linear, repeat_disable;
uniform sampler2D glow_1 : filter_linear, repeat_disable;
uniform sampler2D beauty_2 : filter_linear, repeat_disable;
uniform sampler2D depth_2 : filter_nearest, repeat_disable;
uniform sampler2D key_2 : filter_linear, repeat_disable;
uniform sampler2D glow_2 : filter_linear, repeat_disable;
// world -> plate camera space (the camera looks along -z)
uniform mat4 view_0;
uniform mat4 view_1;
uniform mat4 view_2;
// tan(half horizontal fov), tan(half vertical fov), near, far
uniform vec4 lens_0 = vec4(1.0, 1.0, 0.1, 80.0);
uniform vec4 lens_1 = vec4(1.0, 1.0, 0.1, 80.0);
uniform vec4 lens_2 = vec4(1.0, 1.0, 0.1, 80.0);
// plate camera position (xyz) and enabled (w)
uniform vec4 eye_0 = vec4(0.0);
uniform vec4 eye_1 = vec4(0.0);
uniform vec4 eye_2 = vec4(0.0);
// exact pose (x), texels per unit of tangent: height / (2 tan(half vfov)) (y)
uniform vec2 info_0 = vec2(0.0, 512.0);
uniform vec2 info_1 = vec2(0.0, 512.0);
uniform vec2 info_2 = vec2(0.0, 512.0);
// a plate that lacks the room's variant is drawn from its base, regraded: sun scale (x), tint (yzw)
uniform vec4 grade_0 = vec4(1.0);
uniform vec4 grade_1 = vec4(1.0);
uniform vec4 grade_2 = vec4(1.0);

uniform float sun = 1.0;                 // the key's share is scaled by this (1 = as rendered)
uniform float flicker_amount = 0.12;     // candles and lamps (glow share)
uniform float screen_texels = 400.0;     // our own: viewport height / (2 tan(half vfov))
uniform float depth_bias = 0.06;         // metres; covers the proxy's departure from the set
uniform float depth_bias_slope = 0.006;  // grows with distance and at grazing angles
uniform float fade = 1.0;                // the crossfade overlay's opacity (PLATE_FADE only)

varying vec3 v_world;

vec4 snap(vec4 p) {
	vec4 s = p;
	s.xyz = p.xyz / p.w;
	vec2 res = max(floor(snap_grid * precision_multiplier), vec2(1.0));
	s.xy = floor(res * s.xy) / res;
	s.xyz *= p.w;
	return s;
}

void vertex() {
	// UVs come from this UNSNAPPED position; only the drawn position wobbles, and only during the spell
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = lens_warp > 0.0 ? snap(clip) : clip;
}

float decode_depth(vec2 rg, vec4 lens) {
	float v = (floor(rg.r * 255.0 + 0.5) * 256.0 + floor(rg.g * 255.0 + 0.5)) / 65535.0;
	return mix(lens.z, lens.w, v);
}

// One plate's opinion of this fragment: its colour, key and glow, and how much to trust it.
float plate(sampler2D b, sampler2D d, sampler2D k, sampler2D g, mat4 view, vec4 lens, vec4 eye, vec2 info, vec4 grade,
		vec3 p, vec3 n, vec3 to_cam, float cam_dist, out vec3 colour, out float key, out float glow, out float coverage) {
	colour = vec3(0.0);
	key = 0.0;
	glow = 0.0;
	coverage = 0.0;
	if (eye.w < 0.5) {
		return 0.0;
	}
	vec4 q = view * vec4(p, 1.0);
	float z = -q.z;
	if (z <= lens.z) {
		return 0.0;
	}
	vec2 ndc = q.xy / (z * lens.xy);
	vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec3 to_plate = eye.xyz - p;
	float plate_dist = length(to_plate);
	to_plate /= max(plate_dist, 1e-4);
	float facing = dot(n, to_plate);
	float exact = info.x;
	if (exact > 0.5) {
		coverage = 1.0;
	} else {
		// the plate saw the other side of this face: its pixel belongs to something else
		float front = smoothstep(0.02, 0.12, facing);
		float stored = decode_depth(texture(d, uv).rg, lens);
		float bias = depth_bias + depth_bias_slope * z / max(facing, 0.25);
		float visible = 1.0 - smoothstep(stored + bias, stored + bias * 2.0, z);
		vec2 edge = min(uv, vec2(1.0) - uv) * vec2(lens.x / lens.y, 1.0);
		float border = smoothstep(0.0, 0.025, min(edge.x, edge.y));
		coverage = front * visible * border;
	}
	if (coverage <= 0.0) {
		return 0.0;
	}
	colour = texture(b, uv).rgb;
	key = texture(k, uv).r;
	glow = texture(g, uv).r;
	colour *= mix(1.0, grade.x, key) * grade.yzw;
	key *= grade.x;
	// closer views win by a lot (1 / angle); the exact pose wins outright
	float angle_weight = 1.0 / max(1.0 - dot(to_plate, to_cam), 1e-5);
	// texels per metre this plate puts on the surface vs. pixels per metre we draw it with
	float plate_density = info.y * max(facing, 0.0) / max(plate_dist, 1e-3);
	float our_density = screen_texels * max(dot(n, to_cam), 0.05) / max(cam_dist, 1e-3);
	float density_weight = clamp(plate_density / max(our_density, 1e-4), 0.02, 1.0);
	return coverage * angle_weight * mix(density_weight, 1.0, exact);
}

void fragment() {
	vec3 p = v_world;
	vec3 to_cam = CAMERA_POSITION_WORLD - p;
	float cam_dist = length(to_cam);
	to_cam /= max(cam_dist, 1e-4);
	vec3 n = normalize(cross(dFdx(p), dFdy(p)));
	n = dot(n, to_cam) < 0.0 ? -n : n;

	vec3 c0; vec3 c1; vec3 c2;
	float k0; float k1; float k2;
	float g0; float g1; float g2;
	float v0; float v1; float v2;
	float w0 = plate(beauty_0, depth_0, key_0, glow_0, view_0, lens_0, eye_0, info_0, grade_0, p, n, to_cam, cam_dist, c0, k0, g0, v0);
	float w1 = plate(beauty_1, depth_1, key_1, glow_1, view_1, lens_1, eye_1, info_1, grade_1, p, n, to_cam, cam_dist, c1, k1, g1, v1);
	float w2 = plate(beauty_2, depth_2, key_2, glow_2, view_2, lens_2, eye_2, info_2, grade_2, p, n, to_cam, cam_dist, c2, k2, g2, v2);
	float total = w0 + w1 + w2;
	vec3 colour = COLOR.rgb;
	float key = 0.0;
	float glow = 0.0;
	if (total > 0.0) {
		vec3 seen = (c0 * w0 + c1 * w1 + c2 * w2) / total;
		float coverage = max(v0, max(v1, v2));
		colour = mix(colour, seen, coverage);
		key = (k0 * w0 + k1 * w1 + k2 * w2) / total * coverage;
		glow = (g0 * w0 + g1 * w1 + g2 * w2) / total * coverage;
	}
	float t = stage_time;
	float flicker = 1.0 + flicker_amount * (0.5 * sin(t * 7.3) + 0.3 * sin(t * 13.1 + 1.7) + 0.2 * sin(t * 23.7 + 0.4));
	colour *= mix(1.0, sun, key) * mix(1.0, flicker, glow);
	// the spell: reality warms where the light falls and leans toward violet elsewhere
	colour *= mix(vec3(1.0), vec3(1.04, 0.95, 1.10), magic_amount);
	colour += key * magic_amount * 0.06 * vec3(1.0, 0.85, 0.55);
	ALBEDO = max(colour, vec3(0.0));
#ifdef PLATE_FADE
	ALPHA = fade;
#endif
}

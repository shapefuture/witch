shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

// Characters and anything that moves. They are not baked, so they sample the baked LIGHT MAP of
// the floor beneath them: standing in the golden shaft they glow, in the shade they go purple.
// Plus a half-lambert from the key light, a warm rim where the sun is behind them, and the same
// PSX vertex snap, affine UVs and per-vertex wobble (hand-animated GTE jitter) as the set.

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
global uniform vec2 snap_grid;
global uniform float stage_time;
global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;
global uniform vec4 fog_color : source_color;
global uniform float fog_density;

uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float wobble_amount : hint_range(0.0, 0.02) = 0.005;
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec4 light_rect = vec4(-12.0, -14.0, 12.0, 10.0); // x0, z0, x1, z1
uniform float light_scale = 1.4;
uniform vec3 sun_dir = vec3(-0.36, 0.64, -0.68);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.4);
uniform vec2 lit_range = vec2(0.28, 0.9); // luma of the floor in shade / in the shaft
uniform float rim_strength = 1.3;
// Experimental, so live actors sit in the painted plates: a faint paper grain fixed to the screen
// (the plates are still pictures) and a small tone shift per facet (the plates' baked facet mosaic).
uniform float paper_grain = 0.035;
uniform float facet_tone = 0.05;

varying vec3 v_world;
varying vec3 v_normal;
varying float v_dist;

vec4 snap(vec4 p) {
	vec4 s = p;
	s.xyz = p.xyz / p.w;
	vec2 res = max(floor(snap_grid * precision_multiplier), vec2(1.0));
	s.xy = floor(res * s.xy) / res;
	s.xyz *= p.w;
	return s;
}

void vertex() {
	float t = stage_time * 8.0;
	VERTEX.x += sin(t + VERTEX.x * 43.2 + VERTEX.z * 17.8) * wobble_amount;
	VERTEX.y += sin(t * 0.5 + VERTEX.y * 31.5 + VERTEX.x * 23.1) * wobble_amount * 0.25;
	VERTEX.z += sin(t * 1.31 + VERTEX.z * 51.7 + VERTEX.y * 11.4) * wobble_amount;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = length(mv.xyz);
	POSITION = snap(PROJECTION_MATRIX * mv);
	POSITION /= abs(POSITION.w);
}

void fragment() {
	vec3 base = modulate_color.rgb * COLOR.rgb;
	if (use_texture) {
		base *= texture(albedoTex, UV).rgb;
	}
	vec2 uv = (v_world.xz - light_rect.xy) / (light_rect.zw - light_rect.xy);
	vec3 floor_light = texture(light_map, clamp(uv, vec2(0.0), vec2(1.0))).rgb * light_scale;
	float luma = dot(floor_light, vec3(0.3, 0.55, 0.15));
	float in_sun = clamp((luma - lit_range.x) / max(lit_range.y - lit_range.x, 0.01), 0.0, 1.0);
	vec3 n = normalize(v_normal);
	float half_lambert = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	// shade colour is the floor's own purple; the shaft adds gold on sun-facing sides
	vec3 shade = floor_light * mix(0.85, 1.05, half_lambert);
	vec3 gold = sun_color * (0.25 + 0.75 * half_lambert) * in_sun * 0.95;
	vec3 view = normalize(-(VIEW_MATRIX * vec4(v_world, 1.0)).xyz);
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float rim = pow(clamp(1.0 - dot(n_view, view), 0.0, 1.0), 2.4) * rim_strength;
	vec3 col = base * (shade + gold) + sun_color * rim * (0.35 + 0.65 * in_sun) * 0.6;
	vec3 facet = normalize(cross(dFdx(v_world), dFdy(v_world)));
	float facet_hash = fract(sin(dot(floor(facet * 23.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	col *= 1.0 + (facet_hash - 0.5) * 2.0 * facet_tone;
	// grain cells of one pixel of a 360-row picture, whatever the render size
	vec2 cell = floor(FRAGCOORD.xy / max(VIEWPORT_SIZE.y / 360.0, 1.0));
	float grain = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453) - 0.5;
	col *= 1.0 + grain * paper_grain;
	float haze = (1.0 - exp(-fog_density * v_dist)) * exp(-max(v_world.y, 0.0) * 0.035);
	col = mix(col, fog_color.rgb, clamp(haze, 0.0, 0.9));
	ALBEDO = max(col, vec3(0.0));
}

shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

// The baked diorama surface. Light was baked into the vertex colours in Blender (golden shaft,
// purple shade, warm bounce), so this shader does no lighting at all: it multiplies a hand-painted
// tile by that baked light, then bends the picture the way a 1996 GPU did: vertex snapping, affine
// (non-perspective-correct) UVs, nearest-texel sampling. On top: wind sway for leaves/grass
// (vertex alpha is the sway weight), atmospheric haze, and a magic loosening of the snap.

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
global uniform vec2 snap_grid;
global uniform float stage_time;
global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;
global uniform vec4 fog_color : source_color;
global uniform float fog_density;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float gain = 1.55; // exposure: baked light is stored with the sunlit floor at 1.0
uniform float sway = 0.0;
uniform float glow = 0.0;
uniform float fog_amount = 1.0;
uniform float cutout = 0.0; // 1: texels with alpha < 0.5 are not drawn (the eye on the wall)
uniform float rim = 0.16; // warm edge light from the key's side: the baked world has no specular

varying float v_dist;
varying float v_height;

vec4 snap(vec4 p) {
	vec4 s = p;
	s.xyz = p.xyz / p.w;
	vec2 res = max(floor(snap_grid * precision_multiplier), vec2(1.0));
	s.xy = floor(res * s.xy) / res;
	s.xyz *= p.w;
	return s;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = stage_time * 1.15 + world.x * 0.33 + world.z * 0.27;
	float weight = COLOR.a;
	VERTEX.x += sin(phase) * sway * weight + sin(phase * 2.3 + world.z) * sway * 0.25 * weight;
	VERTEX.z += cos(phase * 0.8) * sway * 0.6 * weight;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_dist = length(mv.xyz);
	v_height = world.y;
	POSITION = snap(PROJECTION_MATRIX * mv);
	POSITION /= abs(POSITION.w); // affine texture mapping
}

void fragment() {
	vec4 sample_ = texture(albedo_tex, UV);
	if (cutout > 0.5 && sample_.a < 0.5) {
		discard;
	}
	vec3 tex = sample_.rgb;
	vec3 lit = tex * COLOR.rgb * tint.rgb * gain;
	float edge = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 3.0);
	vec3 col = mix(lit + vec3(1.0, 0.78, 0.45) * edge * rim * (COLOR.r + COLOR.g) * 0.5, tint.rgb * 1.15, glow);
	float haze = (1.0 - exp(-fog_density * v_dist)) * exp(-max(v_height, 0.0) * 0.035) * fog_amount;
	col = mix(col, fog_color.rgb, clamp(haze, 0.0, 0.9));
	// Display-referred on purpose (a PS1 had no linear light): the Compatibility renderer writes
	// ALBEDO to the screen as is, so what is computed here is what appears.
	ALBEDO = max(col, vec3(0.0));
}

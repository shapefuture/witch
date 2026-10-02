shader_type spatial;
// The painting's shaft of light and the pool it makes on the floor, alive (PaintedLife). The mesh is the room's own
// depth grid, restricted to where `mask` (R: the shaft, G: the pool) is non-zero and pulled 1.5 % towards the
// camera, so it lies over the painting like a coat of fog: nearer things (props, characters) cover it, and where the
// painting is the surface the beam falls on. blend_mix lets one pass do everything:
//   - the beam breathing around the painted brightness (above 1 the lit parts lift towards the beam colour, below 1 the
//     painting dims towards the shade colour), so at level 1 and base 0 the painting is exactly the painting;
//   - the characters' shadow along the ray from the surface to the light (a few spheres per character);
//   - dust motes that catch the light only inside the shaft, stepped like hand-drawn animation.
// Everything is banded and dithered with painted_screen.gdshader's 4x4 Bayer.
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D plate : filter_nearest, repeat_disable;
uniform vec2 luma_range = vec2(0.04, 0.32); // painted brightness below which the beam leaves a surface alone
uniform bool psx = true;
uniform vec2 texel_res = vec2(640.0, 360.0);
uniform vec2 snap_res = vec2(480.0, 270.0);
uniform vec2 image_size = vec2(1280.0, 720.0);
uniform vec3 beam_color = vec3(1.0, 0.88, 0.58);
uniform vec3 shade_color = vec3(0.16, 0.1, 0.2);
uniform float level = 1.0;
uniform vec4 shaft = vec4(0.06, 1.2, 0.5, 0.25); // base haze, breathing gain, taper towards the floor, shadow strength
uniform vec4 pool = vec4(0.04, 1.0, 1.0, 0.4); // base, gain, (unused), shadow strength
uniform vec2 taper_rows = vec2(40.0, 600.0); // painting rows where the shaft is fullest / thinnest
uniform float levels = 24.0;
uniform float master = 1.0;

uniform vec3 light_pos = vec3(0.0, 10.0, -12.0);
uniform vec4 occ[8]; // xyz: centre of a sphere that blocks the light, w: its radius
uniform int occ_count = 0;

uniform float clock = 0.0; // seconds, held on a few steps per second
uniform vec4 motes = vec4(9.0, 0.3, 0.16, 0.6); // cell (texels), density, fall speed (cells per second), strength
uniform vec3 mote_color = vec3(1.0, 0.93, 0.7);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (psx) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = floor(ndc.xy * snap_res * 0.5 + 0.5) / (snap_res * 0.5);
		clip = vec4(ndc * clip.w, clip.w);
		clip /= abs(clip.w);
	}
	POSITION = clip;
}

float hash(vec2 p, float k) {
	return fract(sin(dot(p + k * 17.17, vec2(127.1, 311.7))) * 43758.5453);
}

// One dust mote per cell of the texel grid, at most: it falls (or rises) through its cell and fades in and out
// at the ends, so nothing pops and nothing ever has to look into a neighbouring cell.
float mote_alpha(vec2 texel) {
	float cell = motes.x;
	vec2 id = floor(texel / cell);
	vec2 local = texel - id * cell;
	if (hash(id, 4.0) > motes.y) {
		return 0.0;
	}
	float dir = hash(id, 6.0) < 0.5 ? 1.0 : -1.0;
	float phase = fract(hash(id, 3.0) + dir * clock * motes.z);
	float sway = sin(clock * (0.6 + hash(id, 7.0)) + hash(id, 2.0) * 6.2832) * 1.4;
	vec2 pos = vec2(floor(hash(id, 1.0) * (cell - 5.0) + 2.5 + sway), floor(phase * (cell - 3.0) + 1.5));
	vec2 d = abs(local - pos);
	bool big = hash(id, 5.0) < 0.1;
	float hit = (d.x + d.y < 0.5) ? 1.0 : ((big && d.x + d.y < 1.5) ? 0.45 : 0.0);
	float twinkle = fract(hash(id, 8.0) + floor(clock * 1.7) * 0.37) < 0.3 ? 0.4 : 1.0;
	return hit * sin(phase * 3.14159) * twinkle;
}

void fragment() {
	vec2 uv = psx ? (floor(UV * texel_res) + 0.5) / texel_res : UV;
	vec3 m = texture(mask, uv).rgb;
	float row = uv.y * image_size.y;
	float taper = mix(1.0, shaft.z, smoothstep(taper_rows.x, taper_rows.y, row));
	// Light on a surface scales what is lit: the beam moves the lit parts of the painting and leaves its blacks
	// (a hood, a shelf's depths) black, instead of fogging them grey.
	vec3 painted = texture(plate, uv).rgb;
	float lit = smoothstep(luma_range.x, luma_range.y, dot(painted, vec3(0.3, 0.55, 0.15)));
	float haze = (m.r * taper * (shaft.x + shaft.y * (level - 1.0)) + m.g * (pool.x + pool.y * (level - 1.0))) * lit;

	float blocked = 0.0;
	if (occ_count > 0 && m.r + m.g > 0.02) {
		vec3 to_light = light_pos - v_world;
		float len = length(to_light);
		vec3 dir = to_light / len;
		for (int i = 0; i < 8; i++) {
			if (i >= occ_count) {
				break;
			}
			vec3 c = occ[i].xyz - v_world;
			float t = clamp(dot(c, dir), 0.0, len);
			float dist = length(c - dir * t);
			float r = occ[i].w;
			blocked = max(blocked, 1.0 - smoothstep(r * 0.7, r * 1.1 + t * 0.06, dist));
		}
	}
	vec2 cell = floor(mod(FRAGCOORD.xy, 4.0));
	float threshold = (BAYER[int(cell.y) * 4 + int(cell.x)] + 0.5) / 16.0;
	blocked = floor(blocked * 3.0 + threshold) / 3.0;
	float dark = blocked * (m.r * taper * shaft.w + m.g * pool.w) * lit;

	float mote = 0.0;
	if (m.r > 0.35 && motes.w > 0.0) {
		mote = mote_alpha(floor(uv * texel_res)) * motes.w * smoothstep(0.35, 0.8, m.r);
	}

	float lift = max(haze, 0.0) * master;
	float dim = max(-haze, 0.0) * master + dark * master;
	mote *= master;
	float a = lift + dim + mote;
	a = floor(a * levels + threshold) / levels;
	if (a <= 0.0) {
		discard;
	}
	float total = max(lift + dim + mote, 0.0001);
	ALBEDO = (beam_color * lift + shade_color * dim + mote_color * mote) / total;
	ALPHA = min(a, 1.0);
}

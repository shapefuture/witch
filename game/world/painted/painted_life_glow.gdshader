shader_type spatial;
// The painting's own lamps, alive (PaintedLife). One mesh holds every glow card; each card is a flat square at its
// light's depth, so anything nearer (a prop, a character, a shelf edge) hides it the way it would hide the lamp.
// The falloff is banded and dithered with the same 4x4 Bayer as painted_screen.gdshader, never smooth, and the
// colour of every card (its strength, its flicker, its flare) arrives in `state`, refreshed a few times a second.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform vec4 state[32]; // rgb: colour x strength x level; a: unused
uniform bool psx = true;
uniform vec2 snap_res = vec2(480.0, 270.0);
uniform float levels = 6.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

varying vec3 v_color;
varying float v_core;

void vertex() {
	v_color = state[int(UV2.x + 0.5)].rgb;
	v_core = max(COLOR.r, 0.02);
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (psx) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = floor(ndc.xy * snap_res * 0.5 + 0.5) / (snap_res * 0.5);
		clip = vec4(ndc * clip.w, clip.w);
		clip /= abs(clip.w);
	}
	POSITION = clip;
}

void fragment() {
	float r = length(UV);
	float halo = pow(max(1.0 - r, 0.0), 2.0) * 0.45;
	float core = pow(max(1.0 - r / v_core, 0.0), 1.5);
	float f = clamp(halo + core, 0.0, 1.0);
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float q = floor(f * levels + threshold) / levels;
	if (q <= 0.0 || max(v_color.r, max(v_color.g, v_color.b)) <= 0.0) {
		discard;
	}
	ALBEDO = v_color * q;
}

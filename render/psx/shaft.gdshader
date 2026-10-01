shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;

// A shaft of light through dusty air, faked as a translucent prism: brightest where you look
// through its middle, fading to nothing at its edges, strongest just under the hole and dying out
// toward the floor, with slow streaks drifting inside it.

global uniform float stage_time;
global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 colour : source_color = vec3(1.0, 0.82, 0.48);
uniform float strength = 0.5;
uniform float streaks = 1.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, 1.6);
	float along = smoothstep(0.0, 0.06, UV.y) * mix(1.0, 0.3, smoothstep(0.1, 1.0, UV.y));
	float band = sin(UV.x * 37.7 + stage_time * 0.22 + sin(UV.x * 11.0 + stage_time * 0.1) * 2.2);
	float streak = 1.0 - streaks * 0.28 * (0.5 + 0.5 * band);
	ALBEDO = colour * strength * body * along * streak * (1.0 + magic_amount * 0.4);
	ALPHA = 1.0;
}

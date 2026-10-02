shader_type canvas_item;
// The dark frame of the painting (its heavy foreground shelves and rubble), breathing against the light: when the
// beam swells the frame closes in a little, when it ebbs the frame lets go. Multiplied under painted_screen's colour
// quantisation, banded and dithered with the same 4x4 Bayer.
render_mode blend_mul;

uniform float strength = 0.12; // how far the corners go towards the tint (0..1)
uniform vec3 tint = vec3(0.34, 0.24, 0.4);
uniform float levels = 32.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 p = (SCREEN_UV - vec2(0.5, 0.45)) * vec2(1.7, 2.1);
	float d = smoothstep(0.55, 1.45, length(p));
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float k = floor(d * strength * levels + threshold) / levels;
	COLOR = vec4(mix(vec3(1.0), tint, k), 1.0);
}

shader_type canvas_item;
// PlayStation colour: 5 bits per channel with a 4x4 ordered dither, over the whole frame (plate and actors).

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform bool enabled = true;
uniform float levels = 31.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	if (enabled) {
		ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
		float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0 - 0.5;
		col = floor(col * levels + 0.5 + threshold) / levels;
	}
	COLOR = vec4(col, 1.0);
}

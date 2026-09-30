shader_type canvas_item;

// Fullscreen PSX grade: ordered dither + colour quantisation over the 320x240 render.
// The mundane world is coarse and banded. Magic (global magic_amount, 0..1) makes reality
// visibly LESS constrained: a much deeper palette, a relaxed dither, richer saturation.

global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D dither_tex : hint_default_white, repeat_enable, filter_nearest;
uniform float col_depth = 15.0;
uniform float magic_col_depth = 63.0;

void fragment() {
	vec4 base_color = texture(screen_texture, SCREEN_UV);
	vec2 dith_size = vec2(textureSize(dither_tex, 0));
	vec2 buf_size = vec2(textureSize(screen_texture, 0));
	vec3 dith = texture(dither_tex, SCREEN_UV * (buf_size / dith_size)).rgb - 0.5;
	float depth = mix(col_depth, magic_col_depth, magic_amount);
	float banding = 1.0 - magic_amount * 0.75;
	vec3 graded = round(base_color.rgb * depth + dith * banding) / depth;
	float luma = dot(graded, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(luma), graded, 1.0 + magic_amount * 0.6), 1.0);
}

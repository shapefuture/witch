shader_type canvas_item;

// The last pass over the whole picture, at the 480x360-ish internal resolution:
//   lens warp      the cast spell swings the lens out to a fisheye (global lens_warp, 0..1)
//   glow           a cheap bloom from the screen's own mip chain: the shaft and the lamps bleed
//   grade          lifted purple shadows, golden highlights, a little more chroma
//   vignette       the dark frame that pushes the eye to the lit pool
//   dither + 5-bit ordered dither into a 32-level-per-channel palette, like a 15-bit framebuffer
// Magic (global magic_amount, 0..1) makes reality visibly LESS constrained: a much deeper
// palette, a relaxed dither, richer saturation.

global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;
global uniform float lens_warp : hint_range(0.0, 1.0) = 0.0;
global uniform float stage_time;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D dither_tex : hint_default_white, repeat_enable, filter_nearest;
uniform float col_depth = 31.0;
uniform float magic_col_depth = 127.0;
uniform float glow_amount = 0.55;
uniform float vignette = 0.78;
uniform vec3 shadow_tint : source_color = vec3(0.93, 0.91, 0.90);
uniform vec3 light_tint : source_color = vec3(1.03, 1.0, 0.90);

vec2 warp(vec2 uv, float k) {
	vec2 c = uv * 2.0 - 1.0;
	float r2 = dot(c, c);
	c *= (1.0 + k * r2) / (1.0 + k);
	return clamp(c * 0.5 + 0.5, vec2(0.0), vec2(1.0));
}

void fragment() {
	vec2 uv = warp(SCREEN_UV, lens_warp * 0.55);
	vec3 base = texture(screen_texture, uv).rgb;
	vec3 halo = (textureLod(screen_texture, uv, 2.0).rgb * 0.5 + textureLod(screen_texture, uv, 3.5).rgb * 0.5);
	vec3 bloom = max(halo - vec3(0.55), vec3(0.0)) * glow_amount * 1.6;
	vec3 c = base + bloom;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(shadow_tint, light_tint, smoothstep(0.1, 0.8, luma));
	c = mix(vec3(luma), c, 1.0 + 0.12 + magic_amount * 0.6);
	vec2 q = SCREEN_UV * 2.0 - 1.0;
	float edge = dot(q * vec2(0.9, 1.0), q * vec2(0.9, 1.0));
	c *= 1.0 - vignette * smoothstep(0.35, 1.9, edge);
	vec2 dith_size = vec2(textureSize(dither_tex, 0));
	vec2 buf_size = vec2(textureSize(screen_texture, 0));
	vec3 dith = texture(dither_tex, SCREEN_UV * (buf_size / dith_size)).rgb - 0.5;
	float depth = mix(col_depth, magic_col_depth, magic_amount);
	float banding = 1.0 - magic_amount * 0.75;
	COLOR = vec4(round(c * depth + dith * banding) / depth, 1.0);
}

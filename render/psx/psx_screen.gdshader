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
uniform float glow_amount = 0.4;
uniform float vignette = 0.5;
uniform vec3 shadow_tint : source_color = vec3(0.93, 0.91, 0.90);
uniform vec3 light_tint : source_color = vec3(0.97, 1.0, 0.96);

vec2 warp(vec2 uv, float k) {
	vec2 c = uv * 2.0 - 1.0;
	float r2 = dot(c, c);
	c *= (1.0 + k * r2) / (1.0 + k * 1.6);
	// past the edge the picture folds back on itself instead of smearing the last pixel
	vec2 folded = sign(c) * (1.0 - abs(1.0 - abs(c)));
	return folded * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = warp(SCREEN_UV, lens_warp * 0.55);
	vec3 base = texture(screen_texture, uv).rgb;
	vec3 halo = (textureLod(screen_texture, uv, 2.0).rgb * 0.5 + textureLod(screen_texture, uv, 3.5).rgb * 0.5);
	vec3 bloom = max(halo - vec3(0.55), vec3(0.0)) * glow_amount * 1.6;
	vec3 c = base + bloom;
	// a soft shoulder: the beam and the sky patch glow without clipping to flat yellow (the reference's
	// brightest pixels sit near 0.65)
	c = c / (1.0 + max(c - vec3(0.5), vec3(0.0)) * 1.1);
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(shadow_tint, light_tint, smoothstep(0.1, 0.8, luma));
	c = mix(vec3(luma), c, 1.2 + magic_amount * 0.2);
	c *= mix(vec3(1.0), vec3(1.06, 0.90, 1.14), magic_amount); // reality loosens toward purple and coral, not acid yellow
	vec2 q = SCREEN_UV * 2.0 - 1.0;
	float edge = dot(q * vec2(0.9, 1.0), q * vec2(0.9, 1.0));
	c *= 1.0 - vignette * smoothstep(0.35, 1.9, edge);
	float grain = fract(sin(dot(floor(SCREEN_UV * vec2(textureSize(screen_texture, 0))), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	c += grain * 0.016 * (1.0 - magic_amount);
	vec2 dith_size = vec2(textureSize(dither_tex, 0));
	vec2 buf_size = vec2(textureSize(screen_texture, 0));
	vec3 dith = texture(dither_tex, SCREEN_UV * (buf_size / dith_size)).rgb - 0.5;
	float depth = mix(col_depth, magic_col_depth, magic_amount);
	float banding = 1.0 - magic_amount * 0.75;
	COLOR = vec4(round(c * depth + dith * banding) / depth, 1.0);
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

// The raccoon's telesomatic flash (GAME_SPEC section 4; BIBLE section 6): a place's plate seen through a soft, warped,
// slightly colour-shifted card hung in front of the camera. It draws no caption: a sensation is an image, not a sentence.
// `strength` is the card's fade (set by the presenter); `warp` is zero under reduced effects.

uniform sampler2D plate : filter_linear_mipmap, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float warp : hint_range(0.0, 0.2) = 0.025;
uniform float shift : hint_range(0.0, 0.02) = 0.005;
uniform float wobble_speed : hint_range(0.0, 8.0) = 1.4;
uniform vec3 wash : source_color = vec3(0.62, 0.52, 0.95);

void fragment() {
	vec2 uv = UV;
	float t = TIME * wobble_speed;
	uv += warp * vec2(sin(uv.y * 9.0 + t), cos(uv.x * 7.0 - 0.8 * t));
	vec3 col;
	col.r = texture(plate, uv + vec2(shift, 0.0)).r;
	col.g = texture(plate, uv).g;
	col.b = texture(plate, uv - vec2(shift, 0.0)).b;
	col = mix(col, col * wash * 1.6, 0.35);
	vec2 centred = (UV - vec2(0.5)) * vec2(1.0, 0.8);
	float vignette = smoothstep(0.75, 0.2, length(centred));
	ALBEDO = col;
	ALPHA = strength * vignette;
}

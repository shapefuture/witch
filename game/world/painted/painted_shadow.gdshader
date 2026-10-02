shader_type spatial;
// A soft contact shadow multiplied into the painting under a character's feet.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint = vec3(0.42, 0.38, 0.48);
uniform float strength = 0.75;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = (1.0 - smoothstep(0.15, 1.0, r)) * strength;
	ALBEDO = mix(vec3(1.0), tint, a);
}

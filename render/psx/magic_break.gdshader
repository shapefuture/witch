shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// Material for things that are MAGIC. Unlike every mundane PSX surface it does no vertex
// snapping and is unlit: light that comes from nowhere, colour outside the world's palette,
// motion on a smooth cadence. The player should be able to SEE that reality stopped being
// constrained, not merely that an effect played.

global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float intensity = 1.0;
uniform float speed = 0.45;

void fragment() {
	float t = TIME * speed;
	vec3 spectrum = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + UV.y * 0.8 + t));
	float fade = clamp(1.0 - UV.y, 0.0, 1.0);
	ALBEDO = mix(tint.rgb, spectrum, 0.7) * intensity;
	ALPHA = fade * tint.a * (0.35 + 0.65 * magic_amount);
}

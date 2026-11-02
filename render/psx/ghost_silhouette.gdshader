shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// The chuika's ghost (Expectation-Sight, GAME_SPEC section 4): a translucent, faintly violet copy of an actor, brightest at
// its edges and flickering a little, so it reads as a trace and not as a person. Presentation only: nothing reads it back.
// `strength` is set per copy by the presenter (its move's fade in and out).

uniform vec4 tint : source_color = vec4(0.72, 0.64, 0.95, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = 1.0 - facing;
	float flicker = 0.92 + 0.08 * sin(TIME * 9.0 + FRAGCOORD.y * 0.04);
	ALBEDO = tint.rgb * (0.75 + 0.45 * rim);
	ALPHA = tint.a * strength * (0.2 + 0.5 * rim) * flicker;
}

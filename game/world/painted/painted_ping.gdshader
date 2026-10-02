shader_type spatial;
// The painted room's answer to a tap that hit nothing (PaintedPings): a soft ring of light that opens at the
// tapped pixel and fades, on a camera-facing quad. Additive and unshaded, so on the dark edges it glows and
// on the bright beam it barely shows; display-referred colour, as every shader in the room.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform float progress = 1.0;   // 0 just tapped, 1 gone
uniform vec3 tint = vec3(1.0, 0.82, 0.5);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_radius = mix(0.2, 0.95, 1.0 - pow(1.0 - progress, 2.0));
	float ring = smoothstep(0.16, 0.0, abs(r - ring_radius));
	float core = smoothstep(0.4, 0.0, r) * (1.0 - smoothstep(0.0, 0.5, progress));
	float fade = 1.0 - progress;
	ALBEDO = tint * (ring * 0.85 + core * 0.8) * fade;
	ALPHA = 1.0;
}

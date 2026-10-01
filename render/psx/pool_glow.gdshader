shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// The warm bloom where the shaft meets the floor: a soft ellipse, brightest in the middle.

global uniform float stage_time;

uniform vec3 colour : source_color = vec3(1.0, 0.86, 0.52);
uniform float strength = 0.4;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = smoothstep(1.0, 0.05, r);
	float shimmer = 0.92 + 0.08 * sin(stage_time * 0.7 + r * 6.0);
	ALBEDO = colour * strength * a * a * shimmer;
	ALPHA = 1.0;
}

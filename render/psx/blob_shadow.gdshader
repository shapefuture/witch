shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

// A soft contact shadow under something that stands on the floor: a dark brown-olive ellipse that
// multiplies what is below it. Elongated along the key light's ground direction by the caller.
// (The baked set carries its own shadows; characters are not baked, so they get these.)

global uniform float magic_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 tint : source_color = vec3(0.42, 0.34, 0.26);
uniform float strength = 0.75;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = smoothstep(1.0, 0.55, r);
	float a = core * strength * (1.0 - magic_amount * 0.5);
	ALBEDO = mix(vec3(1.0), tint, a);
	ALPHA = 1.0;
}

shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;

// Flat-ish "carved" slabs for the speech bubble and the option plaques. They live in the 3D scene
// (they are placed by projecting a screen position into the world and scaled so one unit is one
// render pixel), but they are never hidden by scenery: depth test off, drawn in render_priority
// order. The painted tile is mapped affinely, nearest-filtered, like every other surface.

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tiles_per_unit = 0.03;
uniform float use_tex = 1.0;
uniform float highlight = 0.0;

void vertex() {
	UV = VERTEX.xy * tiles_per_unit;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION /= abs(POSITION.w);
}

void fragment() {
	vec3 base = tint.rgb;
	if (use_tex > 0.5) {
		base *= texture(tex, UV).rgb;
	}
	base = mix(base, vec3(1.0, 0.86, 0.5), highlight * 0.45);
	ALBEDO = base;
	ALPHA = tint.a;
}

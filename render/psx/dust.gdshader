shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Motes of dust: camera-facing quads that drift on slow lissajous paths around where each
// instance was placed, twinkling. Every mote's motion comes from stage_time, so a given frame is
// the same picture every run.

global uniform float stage_time;

uniform vec3 colour : source_color = vec3(1.0, 0.86, 0.55);
uniform float size = 0.07;
uniform float drift = 0.45;

varying float v_twinkle;

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float h = fract(sin(dot(seed, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec3 d = vec3(sin(stage_time * (0.21 + h * 0.17) + seed.y * 5.1),
		sin(stage_time * (0.17 + h * 0.13) + seed.x * 3.7) * 0.7,
		cos(stage_time * (0.19 + h * 0.15) + seed.z * 4.3)) * drift;
	vec4 centre = VIEW_MATRIX * vec4(seed + d, 1.0);
	centre.xy += VERTEX.xy * size * (0.6 + h * 0.8);
	v_twinkle = 0.55 + 0.45 * sin(stage_time * (1.3 + h * 2.1) + h * 40.0);
	POSITION = PROJECTION_MATRIX * centre;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, r);
	ALBEDO = colour * a * a * v_twinkle * 1.4;
	ALPHA = 1.0;
}

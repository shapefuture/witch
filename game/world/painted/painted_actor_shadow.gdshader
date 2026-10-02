shader_type spatial;
// A character's cast shadow: its own (skinned) mesh flattened onto the floor along the beam, drawn as a material
// overlay so it follows every pose. Multiplied into the painting, once per pixel (the stencil stops the overlap of
// the limbs from darkening twice), strongest at the feet and in the lit pool, fading toward the tip.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
stencil_mode read, write, compare_equal, 0;

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
global uniform vec2 snap_grid;

uniform vec3 sun_dir = vec3(0.393, 0.81, -0.436);
uniform vec3 tint : source_color = vec3(0.45, 0.36, 0.58);
uniform float strength = 0.8;
uniform float reach = 2.2;       // metres of shadow after which it has faded to `tip`
uniform float tip = 0.35;
uniform float bias = 0.04;       // toward the camera, so the floor mesh never swallows it
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec4 light_rect = vec4(-6.0, -16.0, 6.0, -1.0);
uniform vec2 lit_range = vec2(0.28, 0.9);

varying float v_fade;
varying vec3 v_floor;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float floor_y = MODEL_MATRIX[3].y;
	vec3 l = normalize(sun_dir);
	float t = max(w.y - floor_y, 0.0) / max(l.y, 0.08);
	vec3 p = w - l * t;
	p.y = floor_y;
	v_fade = mix(1.0, tip, clamp(t * length(l.xz) / reach, 0.0, 1.0));
	v_floor = p;
	p += normalize(CAMERA_POSITION_WORLD - p) * bias;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
	vec2 res = max(floor(snap_grid * precision_multiplier), vec2(1.0));
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = floor(res * ndc.xy) / res;
	POSITION = vec4(ndc * clip.w, clip.w);
	POSITION /= abs(POSITION.w);
}

void fragment() {
	vec2 uv = (v_floor.xz - light_rect.xy) / (light_rect.zw - light_rect.xy);
	vec3 lit = texture(light_map, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	float luma = dot(lit, vec3(0.3, 0.55, 0.15));
	float in_sun = clamp((luma - lit_range.x) / max(lit_range.y - lit_range.x, 0.01), 0.0, 1.0);
	float a = strength * v_fade * mix(0.3, 1.0, in_sun);
	ALBEDO = mix(vec3(1.0), tint, a);
}

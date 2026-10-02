shader_type spatial;
// A character's cast shadow on the painted floor (PaintedActorShadow): its silhouette seen from the beam, drawn by a
// small viewport that holds only this character, sampled where each floor point's ray toward the beam meets it.
// Blurred more the farther from the feet (contact-hardening, like a soft painted shadow), fading toward the tip, and
// multiplied into the painting. One sample per pixel, so it is even however the limbs, hair and curls overlap.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D silhouette : filter_linear, repeat_disable;
uniform vec3 look_point;            // where the beam's camera aims (above the feet)
uniform vec3 look_right;            // that camera's right and up, in the world
uniform vec3 look_up;
uniform float look_size = 2.0;      // the square it sees, metres
uniform vec3 feet;
uniform vec3 tint : source_color = vec3(0.45, 0.36, 0.58);
uniform float strength = 0.55;
uniform float reach = 2.2;          // metres from the feet after which it has faded to `tip`
uniform float tip = 0.45;
uniform vec2 blur = vec2(0.012, 0.05);  // blur radius at the feet / at `reach`, in fractions of the camera's square
uniform float contact = 0.6;        // a darker patch where the character touches the floor
uniform float contact_radius = 0.4;
uniform vec3 contact_offset;        // that patch sits a little away from the beam
uniform float bias = 0.04;          // toward the camera, so the floor's bumps never swallow it
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec4 light_rect = vec4(-6.0, -16.0, 6.0, -1.0);
uniform vec2 lit_range = vec2(0.28, 0.9);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p = v_world + normalize(CAMERA_POSITION_WORLD - v_world) * bias;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	vec3 d = v_world - look_point;
	// (the viewport texture comes in bottom-up)
	vec2 uv = vec2(0.5 + dot(d, look_right) / look_size, 0.5 + dot(d, look_up) / look_size);
	float far = clamp(distance(v_world.xz, feet.xz) / reach, 0.0, 1.0);
	float r = mix(blur.x, blur.y, far);
	float cover = 0.0;
	// a ring of eight and the centre: enough for a soft edge at 128 texels
	cover += texture(silhouette, uv).a * 2.0;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398 + 0.3;
		cover += texture(silhouette, uv + vec2(cos(a), sin(a)) * r).a;
		cover += texture(silhouette, uv + vec2(cos(a + 0.39), sin(a + 0.39)) * r * 0.5).a;
	}
	cover /= 18.0;
	vec2 luv = (v_world.xz - light_rect.xy) / (light_rect.zw - light_rect.xy);
	float luma = dot(texture(light_map, clamp(luv, vec2(0.0), vec2(1.0))).rgb, vec3(0.3, 0.55, 0.15));
	float in_sun = clamp((luma - lit_range.x) / max(lit_range.y - lit_range.x, 0.01), 0.0, 1.0);
	float a = strength * cover * mix(1.0, tip, far) * mix(0.55, 1.0, in_sun);
	float c = 1.0 - smoothstep(0.15, 1.0, distance(v_world.xz, feet.xz + contact_offset.xz) / contact_radius);
	a = max(a, c * contact * strength);
	ALBEDO = mix(vec3(1.0), tint, clamp(a, 0.0, 1.0));
}

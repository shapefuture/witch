shader_type spatial;
// A hotspot of the painting (PaintedProp, kind "hotspot"): a region with no moving part, so its reaction is
// the painting itself answering. The card is the same plate read by screen position, faded in by a soft mask,
// and it is only drawn while a reaction runs: a ripple (the paint rings outwards), a shake, a swell, a flash.
// The warp fades to nothing at the mask's edge, so the region never tears away from the painting around it.
// PSX handling matches painted_plate.gdshader.
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform sampler2D plate : filter_nearest, repeat_disable;
uniform sampler2D plate_smooth : filter_linear, repeat_disable;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform bool psx = true;
uniform vec2 texel_res = vec2(640.0, 360.0);
uniform vec2 snap_res = vec2(480.0, 270.0);
uniform vec2 plate_px = vec2(1280.0, 720.0);
uniform vec2 center_uv = vec2(0.5);
uniform vec3 flash = vec3(0.0);
uniform float ripple = 0.0;       // progress 0..1 of a ring running outwards; 0 is off
uniform vec2 shake = vec2(0.0);   // painting pixels
uniform float zoom = 0.0;         // 0.05 swells the region by 5 %

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (psx) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = floor(ndc.xy * snap_res * 0.5 + 0.5) / (snap_res * 0.5);
		clip = vec4(ndc * clip.w, clip.w);
		clip /= abs(clip.w);
	}
	POSITION = clip;
}

void fragment() {
	float m = texture(mask, UV2).r;
	vec2 uv = UV;
	vec2 p = (UV - center_uv) * plate_px;
	if (ripple > 0.0) {
		float wave = sin(length(p) * 0.2 - ripple * 22.0);
		uv += normalize(p + vec2(0.001)) * wave * (1.0 - ripple) * 5.0 * m / plate_px;
	}
	uv = center_uv + (uv - center_uv) / (1.0 + zoom * m);
	uv += shake * m / plate_px;
	vec3 col;
	if (psx) {
		col = texture(plate, (floor(uv * texel_res) + 0.5) / texel_res).rgb;
	} else {
		col = texture(plate_smooth, uv).rgb;
	}
	ALBEDO = col + flash * m;
	ALPHA = m;
}

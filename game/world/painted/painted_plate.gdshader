shader_type spatial;
// A painted still on its own depth: the room mesh carries the painting by screen position, so from the
// painting's camera the frame IS the painting. In PSX mode the vertices snap to a coarse grid and the
// texture is mapped affinely (POSITION /= w, as render/psx does), so any camera motion warps it the way
// PlayStation texturing did; the painting is also read through a coarser texel grid.
// The plate sampler has no source_color hint: Compatibility doesn't sRGB-encode, colour stays display-referred.
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D plate : filter_nearest, repeat_disable;
uniform sampler2D plate_smooth : filter_linear, repeat_disable;
uniform bool psx = true;
uniform vec2 texel_res = vec2(640.0, 360.0);
uniform vec2 snap_res = vec2(480.0, 270.0);

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
	vec3 col;
	if (psx) {
		vec2 uv = (floor(UV * texel_res) + 0.5) / texel_res;
		col = texture(plate, uv).rgb;
	} else {
		col = texture(plate_smooth, UV).rgb;
	}
	ALBEDO = col;
}

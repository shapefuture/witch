shader_type spatial;
// A piece of the painting lifted onto its own card (PaintedProp): the same plate, read by screen position (UV)
// and cut out by the prop's mask (UV2). At rest it lies exactly over the painting; when it moves, the room
// behind it shows the painting with the object removed. PSX handling matches painted_plate.gdshader.
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D plate : filter_nearest, repeat_disable;
uniform sampler2D plate_smooth : filter_linear, repeat_disable;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform bool psx = true;
uniform vec2 texel_res = vec2(640.0, 360.0);
uniform vec2 snap_res = vec2(480.0, 270.0);
uniform vec3 flash = vec3(0.0);

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
	if (texture(mask, UV2).r < 0.5) {
		discard;
	}
	vec3 col;
	if (psx) {
		col = texture(plate, (floor(UV * texel_res) + 0.5) / texel_res).rgb;
	} else {
		col = texture(plate_smooth, UV).rgb;
	}
	ALBEDO = col + flash;
}

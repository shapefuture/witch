shader_type spatial;
// The same projection drawn over the opaque proxy with another variant's plates, faded in by
// `fade`: how the room ages (PlateStage.crossfade_to). Same geometry and the same vertex code, so it
// lands on the opaque pass's depth exactly; it writes none of its own.
render_mode unshaded, cull_back, depth_draw_never, blend_mix, fog_disabled;

#define PLATE_FADE
#include "res://render/psx/plate_projection.gdshaderinc"

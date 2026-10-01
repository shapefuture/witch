shader_type spatial;
// Opaque: the proxy writes depth like any set, so actors are hidden behind the statue and shelves.
// Back faces are culled, as in the plates (the spell's low camera looks up through the floor).
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix, fog_disabled;

#include "res://render/psx/plate_projection.gdshaderinc"

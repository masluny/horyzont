// Solid stand-in that only ever draws into the shadow maps.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/tree_common.gdshaderinc"

void vertex() {
	vec3 t = vec3(1.0, 0.0, 0.0);
	tree_place(INSTANCE_ID, VERTEX, NORMAL, t, 0.0, 0.0, 0.0, CAMERA_POSITION_WORLD);
}

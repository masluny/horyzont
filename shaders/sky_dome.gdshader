// Visible sky, drawn on an opaque camera-centred dome so it gets motion vectors
// and temporal accumulation (MetalFX / TAA) like the rest of the frame.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled, depth_draw_opaque;

#include "res://shaders/sky_common.gdshaderinc"

global uniform float frame_jitter;
uniform int debug_quality = 1;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 rd = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec2 px = FRAGCOORD.xy + frame_jitter * vec2(47.0, 17.0);
	float ign = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
	float px_angle = 2.0 / (VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]);
	ALBEDO = render_sky(rd, CAMERA_POSITION_WORLD, ign, px_angle, debug_quality);
}

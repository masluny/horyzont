// Visible sky, drawn on an opaque camera-centred dome so it gets motion vectors
// and temporal accumulation (MetalFX / TAA) like the rest of the frame. The soft
// sky and clouds come from a half-resolution pass; only the sun, moon and stars
// are computed here at full resolution.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled, depth_draw_opaque;

#include "res://shaders/sky_common.gdshaderinc"

uniform sampler2D sky_lowres : filter_linear, repeat_disable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 rd = normalize(world_pos - CAMERA_POSITION_WORLD);
	float px_angle = 2.0 / (VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]);
	vec4 low = texture(sky_lowres, SCREEN_UV);
	ALBEDO = low.rgb + sky_bodies(rd, CAMERA_POSITION_WORLD, px_angle) * low.a;
}

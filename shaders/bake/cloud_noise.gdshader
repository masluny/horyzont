// Bakes a 3D noise volume as a 2D atlas of slices (tiles_x * tiles_y slices).
// mode 0: base shape (R perlin-worley, GBA worley fbm at 3 frequencies)
// mode 1: erosion detail (RGB worley fbm at 3 frequencies)
shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform int mode = 0;
uniform float slice_size = 128.0;
uniform float tiles_x = 16.0;

void fragment() {
	vec2 px = floor(FRAGCOORD.xy);
	vec2 tile = floor(px / slice_size);
	vec2 inner = px - tile * slice_size;
	float z = tile.y * tiles_x + tile.x;
	vec3 p = (vec3(inner, z) + 0.5) / slice_size;
	if (mode == 0) {
		float pf = perlin_fbm(p, 4.0, 4, 3.0) * 0.5 + 0.5;
		float w = worley_fbm(p, 4.0, 11.0);
		float pw = clamp(remap(pf, 0.0, 1.0, w, 1.0), 0.0, 1.0);
		COLOR = vec4(pw, w, worley_fbm(p, 8.0, 21.0), worley_fbm(p, 16.0, 31.0));
	} else {
		COLOR = vec4(worley_fbm(p, 2.0, 41.0), worley_fbm(p, 4.0, 51.0), worley_fbm(p, 8.0, 61.0), 1.0);
	}
}

// Tileable 2D weather map. R: cumulus coverage, G: cloud type variation,
// B: cirrus pattern, A: rain cells.
shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/noise.gdshaderinc"

void fragment() {
	vec3 p = vec3(UV, 0.5);
	float base = perlin_fbm(p, 4.0, 5, 70.0) * 0.5 + 0.5;
	float cells = worley_fbm(p, 6.0, 80.0);
	float cov = clamp(remap(base, 0.25, 0.85, 0.0, 1.0) * 0.7 + cells * 0.45 - 0.1, 0.0, 1.0);
	float type = clamp(perlin_fbm(p + 0.37, 2.0, 3, 90.0) * 0.8 + 0.5, 0.0, 1.0);
	// Cirrus: stretched noise (period 4 along x, 16 along y keeps it tileable).
	vec3 q = vec3(UV.x, UV.y, 0.2);
	float streak = perlin_fbm(vec3(q.x * 1.0, q.y * 4.0, q.z), 4.0, 5, 100.0) * 0.5 + 0.5;
	float wisps = perlin_fbm(q, 16.0, 4, 110.0) * 0.5 + 0.5;
	float cirrus = clamp(streak * 1.2 - 0.25 + (wisps - 0.5) * 0.6, 0.0, 1.0);
	float rain = clamp(remap(perlin_fbm(p + 0.71, 3.0, 3, 120.0) * 0.5 + 0.5, 0.45, 0.75, 0.0, 1.0), 0.0, 1.0);
	COLOR = vec4(cov, type, cirrus, rain);
}

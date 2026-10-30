// Lighthouse beam: crossed additive ribbons. UV.x is -1..1 across, UV.y is 0 at the lamp.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	float across = UV.x;
	float along = UV.y;
	float core = exp(-across * across * 5.5);
	float body = exp(-along * 1.15) * pow(max(1.0 - along, 0.0), 0.55);
	ALBEDO = vec3(1.0, 0.95, 0.82) * core * body * 0.006;
}

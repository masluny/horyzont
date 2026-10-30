// Soft vertical light pillar marking the current postcard spot.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float fade = 1.0;

void fragment() {
	float h = UV.y;
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float a = (1.0 - h) * (1.0 - h) * (0.25 + 0.75 * (1.0 - edge)) * fade;
	ALBEDO = vec3(1.0, 0.78, 0.45) * a * 0.35;
}

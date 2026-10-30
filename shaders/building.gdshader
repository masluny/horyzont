// Whitewash, slate and painted timber. Vertex colour rgb is albedo, alpha is roughness.
shader_type spatial;
render_mode cull_disabled;

global uniform float wetness;

void fragment() {
	vec3 alb = COLOR.rgb;
	float rough = clamp(COLOR.a, 0.04, 1.0);
	alb *= mix(1.0, 0.7, wetness * 0.9);
	rough = mix(rough, 0.16, wetness * 0.75);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.42;
}

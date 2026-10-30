// Galvanised W-beam. UV.y runs along the rail.
shader_type spatial;

global uniform float wetness;

void fragment() {
	float streak = sin(UV.y * 1.6) * 0.012 + sin(UV.y * 0.37 + UV.x * 4.0) * 0.012;
	vec3 alb = vec3(0.52, 0.54, 0.56) + streak;
	float rough = 0.46 + streak * 2.0;
	alb *= mix(1.0, 0.55, wetness);
	rough = mix(rough, 0.18, wetness);
	ALBEDO = alb;
	METALLIC = 0.88;
	ROUGHNESS = clamp(rough, 0.08, 0.85);
	SPECULAR = 0.55;
}

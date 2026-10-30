// Roadside post with a retro-reflective band that lights up in headlights.
shader_type spatial;

varying float band;

void vertex() {
	band = step(0.28, VERTEX.y) * step(VERTEX.y, 0.42);
}

void fragment() {
	ALBEDO = mix(vec3(0.85, 0.85, 0.82), vec3(0.9, 0.08, 0.02), band);
	ROUGHNESS = mix(0.6, 0.25, band);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ndl / PI;
	// Retro-reflection: bounces light back toward its source (headlights).
	if (!LIGHT_IS_DIRECTIONAL) {
		float back = pow(clamp(dot(VIEW, LIGHT), 0.0, 1.0), 8.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * back * band * 6.0;
	}
}

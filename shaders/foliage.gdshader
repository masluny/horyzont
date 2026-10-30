// Dark canopy. Vertex alpha is 1 on leaves (wind) and 0 on unused.
shader_type spatial;
render_mode cull_disabled;

global uniform vec2 world_wind;
global uniform float wetness;

void vertex() {
	float s = COLOR.a;
	if (s > 0.5) {
		float wobble = sin(TIME * 1.35 + VERTEX.x * 0.17 + VERTEX.z * 0.13);
		VERTEX.xz += world_wind * 0.006 * wobble * s;
	}
}

void fragment() {
	vec3 alb = COLOR.rgb * mix(1.0, 0.7, wetness);
	ALBEDO = alb;
	ROUGHNESS = mix(0.78, 0.45, wetness);
	SPECULAR = 0.22;
}

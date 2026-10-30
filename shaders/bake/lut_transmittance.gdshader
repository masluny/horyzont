// Transmittance to the top of the atmosphere, 256x64, Bruneton parameterisation.
shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/atmosphere.gdshaderinc"

void fragment() {
	float r;
	float mu;
	transmittance_params(UV, r, mu);
	vec3 ro = vec3(0.0, r, 0.0);
	vec3 rd = vec3(sqrt(max(0.0, 1.0 - mu * mu)), mu, 0.0);
	float t_end = ray_sphere(ro, rd, R_TOP).y;
	vec2 gnd = ray_sphere(ro, rd, R_GROUND);
	if (gnd.x > 0.0) {
		t_end = min(t_end, gnd.x);
	}
	const int N = 40;
	float dt = t_end / float(N);
	vec3 od = vec3(0.0);
	for (int i = 0; i < N; i++) {
		vec3 p = ro + rd * (float(i) + 0.5) * dt;
		od += atmo_extinction(length(p) - R_GROUND) * dt;
	}
	COLOR = vec4(exp(-od), 1.0);
}

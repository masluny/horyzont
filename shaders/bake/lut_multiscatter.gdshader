// Multiple-scattering contribution Psi_ms (Hillaire 2020, section 5.5), 32x32.
// x: cosine of the sun zenith angle, y: altitude.
shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/atmosphere.gdshaderinc"

uniform sampler2D transmittance_lut : filter_linear, repeat_disable;

void fragment() {
	float mu_s = UV.x * 2.0 - 1.0;
	float r = mix(R_GROUND + 0.01, R_TOP - 0.01, UV.y);
	vec3 ro = vec3(0.0, r, 0.0);
	vec3 ldir = vec3(sqrt(max(0.0, 1.0 - mu_s * mu_s)), mu_s, 0.0);
	const int DIRS = 64;
	const int STEPS = 20;
	const float ISO = 1.0 / (4.0 * PI);
	vec3 l2 = vec3(0.0);
	vec3 f_ms = vec3(0.0);
	for (int d = 0; d < DIRS; d++) {
		// Fibonacci sphere.
		float k = (float(d) + 0.5) / float(DIRS);
		float phi = float(d) * 2.39996323;
		float cz = 1.0 - 2.0 * k;
		float sz = sqrt(max(0.0, 1.0 - cz * cz));
		vec3 rd = vec3(cos(phi) * sz, cz, sin(phi) * sz);
		vec2 top = ray_sphere(ro, rd, R_TOP);
		vec2 gnd = ray_sphere(ro, rd, R_GROUND);
		bool hits_ground = gnd.x > 0.0;
		float t_end = hits_ground ? gnd.x : top.y;
		float dt = t_end / float(STEPS);
		vec3 tr = vec3(1.0);
		vec3 lum = vec3(0.0);
		vec3 fms = vec3(0.0);
		for (int i = 0; i < STEPS; i++) {
			vec3 p = ro + rd * (float(i) + 0.5) * dt;
			float pr = length(p);
			vec3 sr;
			vec3 sm;
			vec3 ext;
			atmo_medium(pr - R_GROUND, sr, sm, ext);
			vec3 scat = sr + sm;
			vec3 t_sun = texture(transmittance_lut, lut_uv(transmittance_uv(pr, dot(p / pr, ldir)), vec2(256.0, 64.0))).rgb
					* horizon_visibility(pr, dot(p / pr, ldir));
			vec3 step_t = exp(-ext * dt);
			vec3 integ = (vec3(1.0) - step_t) / max(ext, vec3(1e-7));
			lum += tr * scat * ISO * t_sun * integ;
			fms += tr * scat * integ;
			tr *= step_t;
		}
		if (hits_ground) {
			vec3 gp = ro + rd * t_end;
			float gr = length(gp);
			vec3 n = gp / gr;
			float ndl = max(dot(n, ldir), 0.0);
			vec3 t_sun = texture(transmittance_lut, lut_uv(transmittance_uv(gr, dot(n, ldir)), vec2(256.0, 64.0))).rgb;
			lum += tr * t_sun * ndl * GROUND_ALBEDO / PI;
		}
		l2 += lum / float(DIRS);
		f_ms += fms / float(DIRS);
	}
	vec3 psi = l2 / max(vec3(1.0) - f_ms, vec3(1e-3));
	COLOR = vec4(psi, 1.0);
}

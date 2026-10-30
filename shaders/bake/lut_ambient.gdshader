// Sky ambient luminance (cosine-weighted upper hemisphere average), 32x2.
// x: cosine of the sun zenith angle, row 0: ground level, row 1: 3 km.
shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/atmosphere.gdshaderinc"

uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
uniform sampler2D multiscatter_lut : filter_linear, repeat_disable;

void fragment() {
	float mu_s = UV.x * 2.0 - 1.0;
	float alt = UV.y < 0.5 ? 0.05 : 3.0;
	vec3 ro = vec3(0.0, R_GROUND + alt, 0.0);
	vec3 ldir = vec3(sqrt(max(0.0, 1.0 - mu_s * mu_s)), mu_s, 0.0);
	const int N = 48;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < N; i++) {
		float u = (float(i) + 0.5) / float(N);
		float phi = float(i) * 2.39996323;
		float ct = sqrt(1.0 - u);
		float st = sqrt(u);
		vec3 rd = vec3(cos(phi) * st, ct, sin(phi) * st);
		vec3 tr;
		sum += integrate_sky(transmittance_lut, multiscatter_lut, ro, rd, ldir, 1e9, 14, tr);
	}
	COLOR = vec4(sum / float(N), 1.0);
}

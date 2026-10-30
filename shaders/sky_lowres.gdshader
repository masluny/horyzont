// Soft sky and clouds at half resolution. Each frame adds a differently jittered
// sample to the reprojected history, so a low step count still converges cleanly.
// a = how much of what lies beyond the sky (sun, stars) shows through.
shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/sky_common.gdshaderinc"

global uniform float frame_jitter;

uniform sampler2D history : filter_linear, repeat_disable;
uniform mat3 cam_basis = mat3(1.0);
uniform mat3 prev_basis_inv = mat3(1.0);
uniform vec2 tan_half = vec2(1.0);
uniform vec3 cam_pos = vec3(0.0);
uniform float history_weight = 0.0;
uniform int debug_quality = 1;

void fragment() {
	vec2 ndc = UV * 2.0 - 1.0;
	vec3 rd = normalize(cam_basis * vec3(ndc.x * tan_half.x, -ndc.y * tan_half.y, -1.0));
	vec2 px = FRAGCOORD.xy + frame_jitter * vec2(47.0, 17.0);
	float ign = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
	float behind;
	vec3 col = render_sky(rd, cam_pos, ign, 0.002, debug_quality, behind);

	vec3 pv = prev_basis_inv * rd;
	float w = 0.0;
	if (pv.z < -0.01) {
		vec2 q = pv.xy / (-pv.z) / tan_half;
		vec2 huv = vec2(q.x, -q.y) * 0.5 + 0.5;
		if (huv.x > 0.0 && huv.y > 0.0 && huv.x < 1.0 && huv.y < 1.0) {
			vec4 h = textureLod(history, huv, 0.0);
			w = history_weight;
			col = mix(col, min(h.rgb, vec3(4000.0)), w);
			behind = mix(behind, h.a, w);
		}
	}
	COLOR = vec4(col, behind);
}

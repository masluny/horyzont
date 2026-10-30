// Shared by tree bark and leaves: instance lookup, wind, LOD cross-fade.

#ifndef TREE_COMMON_INC
#define TREE_COMMON_INC

uniform sampler2D tree_table : filter_nearest, repeat_disable;
// 0 = LOD0 (fades out at r0), 1 = LOD1 (fades in at r0, out at r1), 2 = shadow proxy.
uniform int lod_kind = 0;
uniform float lod_r0 = 60.0;
uniform float lod_r1 = 240.0;
instance uniform int table_row = 0;

global uniform vec2 world_wind;

float tree_fade(float d) {
	if (lod_kind == 2) {
		return 1.0;
	}
	float a = smoothstep(lod_r0 - 9.0, lod_r0, d);
	return lod_kind == 0 ? 1.0 - a : a * (1.0 - smoothstep(lod_r1 - 26.0, lod_r1, d));
}

// Writes the instance placement and wind into position, normal and tangent.
float tree_place(int id, inout vec3 v, inout vec3 n, inout vec3 t, float flex, float phase, float flutter, vec3 cam) {
	vec4 inst = texelFetch(tree_table, ivec2(id, table_row), 0);
	float yaw = fract(inst.x * 0.137 + inst.z * 0.331) * 6.2831;
	float c = cos(yaw);
	float s = sin(yaw);
	mat2 r = mat2(vec2(c, s), vec2(-s, c));
	v *= inst.w;
	v.xz = r * v.xz;
	n.xz = r * n.xz;
	t.xz = r * t.xz;
	vec2 wd = normalize(world_wind + vec2(1e-3));
	float ws = clamp(length(world_wind) / 12.0, 0.15, 1.8);
	float tree_phase = fract(inst.x * 0.61 + inst.z * 0.27) * 6.2831;
	float gust = 0.6 + 0.4 * sin(TIME * 0.31 + inst.x * 0.013 + inst.z * 0.017);
	float sway = (sin(TIME * 0.83 + tree_phase) * 0.55 + 0.75) * gust * ws;
	float h2 = v.y * v.y;
	v.xz += wd * sway * h2 * 0.0011;
	float branch = sin(TIME * 1.7 + phase + tree_phase) * 0.5 + sin(TIME * 2.9 + phase * 2.0) * 0.25;
	v.y += branch * flex * flex * ws * 0.22;
	v.xz += vec2(wd.y, -wd.x) * branch * flex * flex * ws * 0.14;
	float leaf = sin(TIME * 7.3 + phase * 7.0 + v.x * 1.3 + v.z * 1.1);
	v += vec3(0.0, leaf, 0.0) * flutter * flex * ws * 0.035;
	v += inst.xyz;
	return tree_fade(length(inst.xz - cam.xz));
}

global uniform float frame_jitter;

void tree_dither(vec2 frag, float fade) {
	if (fade >= 0.999) {
		return;
	}
	// Interleaved gradient noise, shifted every frame so the upscaler resolves it.
	vec2 q = frag + frame_jitter * vec2(5.588, 2.113);
	float ign = fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
	if (fade < ign) {
		discard;
	}
}

// Mipped alpha shrinks thin leaves away; scale it back up with distance.
float tree_alpha(float a, vec2 uv, float size) {
	vec2 dx = dFdx(uv) * size;
	vec2 dy = dFdy(uv) * size;
	float mip = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0));
	return a * (1.0 + mip * 0.3);
}

#endif

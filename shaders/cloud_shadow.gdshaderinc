// Reads the shared cloud shadow map. 1 = full sun, 0.12 = under a thick cloud.

#ifndef CLOUD_SHADOW_INC
#define CLOUD_SHADOW_INC

global uniform sampler2D cloud_shadow_tex : filter_linear, repeat_disable;
global uniform vec2 cloud_shadow_center;

float cloud_shadow(vec2 world_xz) {
	vec2 uv = (world_xz - cloud_shadow_center) / 8000.0 + 0.5;
	vec2 edge = abs(uv - 0.5) * 2.0;
	float k = 1.0 - smoothstep(0.85, 1.0, max(edge.x, edge.y));
	return mix(1.0, mix(0.12, 1.0, textureLod(cloud_shadow_tex, uv, 0.0).r), k);
}

#endif

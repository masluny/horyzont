// Shared terrain heightmap access (R32F, sampled manually with bilinear).

#ifndef TERRAIN_COMMON_INC
#define TERRAIN_COMMON_INC

uniform sampler2D heightmap : filter_nearest, repeat_disable;

const float WORLD_SIZE = 10240.0;
const float TERRAIN_TEXEL = 2.5;
const int TERRAIN_RES = 4096;

float terrain_height(vec2 wxz) {
	vec2 f = (wxz + WORLD_SIZE * 0.5) / TERRAIN_TEXEL - 0.5;
	vec2 fl = floor(f);
	vec2 t = clamp(f - fl, 0.0, 1.0);
	ivec2 i = clamp(ivec2(fl), ivec2(0), ivec2(TERRAIN_RES - 2));
	if (fl.x < 0.0 || fl.y < 0.0 || fl.x > float(TERRAIN_RES - 2) || fl.y > float(TERRAIN_RES - 2)) {
		t = clamp(f - vec2(i), 0.0, 1.0);
	}
	float h00 = texelFetch(heightmap, i, 0).r;
	float h10 = texelFetch(heightmap, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(heightmap, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(h00, h10, t.x), mix(h01, h11, t.x), t.y);
}

#endif

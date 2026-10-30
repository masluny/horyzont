// Vegetation map baked from the terrain.
// R grass density, G forest density, B shrubs, A dryness (0 lush .. 1 straw).
shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/terrain_common.gdshaderinc"

uniform sampler2D normalmap : filter_linear, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p, int n) {
	float a = 0.0;
	float b = 0.5;
	for (int i = 0; i < n; i++) {
		a += b * vnoise(p);
		b *= 0.5;
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03;
	}
	return a;
}

void fragment() {
	vec2 p = (UV - 0.5) * WORLD_SIZE;
	float h = terrain_height(p);
	vec4 nm = textureLod(normalmap, UV, 0.0);
	vec2 nxz = nm.rg * 2.0 - 1.0;
	float ny = sqrt(max(0.0, 1.0 - dot(nxz, nxz)));
	float road = textureLod(maskmap, UV, 0.0).r;
	float valley = 0.5 - nm.a;

	// Exposed west plateau stays open; sheltered hollows and the east grow woods.
	float west = smoothstep(-300.0, -2200.0, p.x + 0.3 * p.y);
	float big = fbm(p / 1500.0 + 3.7, 5);
	float small = fbm(p / 170.0 + 11.0, 4);
	float f = big * 1.05 + small * 0.42 + valley * 1.1 - west * 0.27;
	float forest = smoothstep(0.66, 0.8, f);
	forest *= smoothstep(9.0, 24.0, h) * (1.0 - smoothstep(300.0, 430.0, h)) * smoothstep(0.76, 0.88, ny);
	forest *= 1.0 - smoothstep(0.02, 0.4, road);

	float shrub = smoothstep(0.52, 0.7, fbm(p / 260.0 + 41.0, 5) + (1.0 - ny) * 1.2 + forest * 0.1);
	shrub *= smoothstep(5.0, 10.0, h) * (1.0 - smoothstep(420.0, 560.0, h)) * smoothstep(0.62, 0.8, ny);
	shrub *= 1.0 - smoothstep(0.05, 0.3, road);

	float grass = smoothstep(0.7, 0.84, ny) * smoothstep(4.0, 7.0, h) * (1.0 - smoothstep(460.0, 620.0, h));
	grass *= 1.0 - smoothstep(0.62, 0.96, road * 1.2 + (vnoise(p * 0.7) - 0.5) * 0.3);
	grass *= smoothstep(0.1, 0.34, fbm(p / 36.0 + 5.0, 4) + 0.28 * ny);
	grass *= 1.0 - forest * 0.5;

	float dry = clamp(fbm(p / 900.0 + 8.0, 4) * 1.5 - 0.42 + (nm.a - 0.5) * 0.9 + west * 0.12, 0.0, 1.0);
	COLOR = vec4(grass, forest, shrub, dry);
}

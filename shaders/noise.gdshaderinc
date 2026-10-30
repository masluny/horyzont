// Tileable noise used to bake cloud and terrain textures. Coordinates are in
// [0,1) and tile with the given integer period.

#ifndef NOISE_INC
#define NOISE_INC

uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

vec3 hash3(vec3 cell, float seed) {
	uvec3 u = uvec3(ivec3(cell) + ivec3(1024)) + uvec3(uint(seed) * 7919u);
	return vec3(pcg3d(u)) / 4294967295.0;
}

// Inverted Worley F1: 1 at feature points, 0 far away.
float worley(vec3 p, float period, float seed) {
	vec3 x = p * period;
	vec3 id = floor(x);
	vec3 f = x - id;
	float md = 1.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 o = vec3(float(i), float(j), float(k));
				vec3 cell = mod(id + o, period);
				vec3 r = o + hash3(cell, seed) - f;
				md = min(md, dot(r, r));
			}
		}
	}
	return 1.0 - clamp(sqrt(md), 0.0, 1.0);
}

vec3 grad3(vec3 cell, float period, float seed) {
	return normalize(hash3(mod(cell, period), seed) * 2.0 - 1.0);
}

// Gradient (Perlin) noise in roughly [-1, 1].
float perlin(vec3 p, float period, float seed) {
	vec3 x = p * period;
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(grad3(i + vec3(0, 0, 0), period, seed), f - vec3(0, 0, 0));
	float n100 = dot(grad3(i + vec3(1, 0, 0), period, seed), f - vec3(1, 0, 0));
	float n010 = dot(grad3(i + vec3(0, 1, 0), period, seed), f - vec3(0, 1, 0));
	float n110 = dot(grad3(i + vec3(1, 1, 0), period, seed), f - vec3(1, 1, 0));
	float n001 = dot(grad3(i + vec3(0, 0, 1), period, seed), f - vec3(0, 0, 1));
	float n101 = dot(grad3(i + vec3(1, 0, 1), period, seed), f - vec3(1, 0, 1));
	float n011 = dot(grad3(i + vec3(0, 1, 1), period, seed), f - vec3(0, 1, 1));
	float n111 = dot(grad3(i + vec3(1, 1, 1), period, seed), f - vec3(1, 1, 1));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z) * 1.7;
}

float perlin_fbm(vec3 p, float period, int octaves, float seed) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		sum += perlin(p, period, seed + float(o)) * amp;
		norm += amp;
		period *= 2.0;
		amp *= 0.5;
	}
	return sum / norm;
}

float worley_fbm(vec3 p, float period, float seed) {
	return worley(p, period, seed) * 0.625
			+ worley(p, period * 2.0, seed + 1.0) * 0.25
			+ worley(p, period * 4.0, seed + 2.0) * 0.125;
}

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) / max(b - a, 1e-5) * (d - c);
}

#endif

// Dry-stone and boulder material. INSTANCE_CUSTOM: warmth, value, moss, phase.
shader_type spatial;

global uniform float wetness;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 custom;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float warm = custom.r;
	float value = custom.g;
	float moss_amt = custom.b;
	float phase = custom.a * 6.283;
	vec3 grey = vec3(0.30, 0.29, 0.27);
	vec3 brown = vec3(0.32, 0.24, 0.17);
	vec3 base = mix(grey, brown, warm) * (0.58 + 0.34 * value);
	// Triplanar-ish: top and side samples blended by the world normal.
	float n_top = vnoise(wpos * vec3(3.4, 1.3, 3.4) + vec3(phase, 0.0, 0.0));
	float n_side = vnoise(wpos.yxz * 2.8 + vec3(2.0, phase, 5.0));
	float up = clamp(wnorm.y, 0.0, 1.0);
	float grain = mix(n_side, n_top, up);
	base *= 0.82 + 0.28 * grain;
	float speck = smoothstep(0.66, 0.84, n_top);
	float fine = smoothstep(0.55, 0.78, fract(n_side * 3.7 + n_top));
	vec3 lichen = mix(vec3(0.32, 0.46, 0.14), vec3(0.62, 0.58, 0.16), fine);
	float top = smoothstep(0.25, 0.82, wnorm.y);
	float moss = speck * top * moss_amt;
	vec3 alb = mix(base, lichen, moss * 0.9);
	float rough = mix(0.94, 0.72, moss);
	alb *= mix(1.0, 0.62, wetness);
	rough = mix(rough, 0.28, wetness * 0.85);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.28;
}

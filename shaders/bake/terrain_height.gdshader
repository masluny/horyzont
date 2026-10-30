// Island heightmap. Output encodes height in [-200, 800] m as hi/lo halves:
// h01 = R + G / 1024. x = east, UV.y grows southwards (+Z).
shader_type canvas_item;
render_mode blend_disabled;

uniform float world_size = 10240.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise with analytic derivatives (Inigo Quilez), range [-1, 1].
vec3 noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	return vec3(-1.0 + 2.0 * (a + k1 * u.x + k2 * u.y + k4 * u.x * u.y),
			2.0 * du * vec2(k1 + k4 * u.y, k2 + k4 * u.x));
}

const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// Derivative-damped fbm: detail fades on slopes, which reads as erosion.
float eroded_fbm(vec2 p, int octaves) {
	float a = 0.0;
	float b = 0.5;
	vec2 d = vec2(0.0);
	for (int i = 0; i < octaves; i++) {
		vec3 n = noised(p);
		d += n.yz;
		a += b * n.x / (1.0 + dot(d, d));
		b *= 0.5;
		p = ROT * p * 2.0;
	}
	return a;
}

float ridged_fbm(vec2 p, int octaves) {
	float a = 0.0;
	float b = 0.55;
	vec2 d = vec2(0.0);
	for (int i = 0; i < octaves; i++) {
		vec3 n = noised(p);
		float r = 1.0 - abs(n.x);
		r *= r;
		d += n.yz * r;
		a += b * r / (1.0 + 0.6 * dot(d, d));
		b *= 0.5;
		p = ROT * p * 2.05;
	}
	return a;
}

float plain_fbm(vec2 p, int octaves) {
	float a = 0.0;
	float b = 0.5;
	for (int i = 0; i < octaves; i++) {
		a += b * noised(p).x;
		b *= 0.5;
		p = ROT * p * 2.0;
	}
	return a;
}

float islet(vec2 q, vec2 c, float radius, float height) {
	float d = length(q - c) / radius;
	return height * exp(-d * d * 2.5) * (0.75 + 0.25 * eroded_fbm(q * 9.0, 4));
}

float island_height(vec2 p) {
	vec2 q = p / 1000.0;
	// Coastline: warped ellipse, a little wider east-west.
	vec2 w = q + vec2(plain_fbm(q * 0.32 + 3.1, 5), plain_fbm(q * 0.32 + 7.7, 5)) * 1.1;
	float r = length(w * vec2(0.92, 1.05)) / 3.6;
	float s = 1.0 - r; // > 0 on land

	float west = smoothstep(0.6, -1.8, q.x + 0.3 * q.y);
	float hills = 14.0 + (eroded_fbm(q * 0.55 + 11.0, 9) * 0.5 + 0.5) * 120.0;
	vec2 mc = q - vec2(0.9, -1.0);
	float mmask = exp(-dot(mc, mc) / 2.0);
	vec2 mc2 = q - vec2(-1.3, 1.4);
	float mmask2 = exp(-dot(mc2, mc2) / 0.7) * 0.45;
	float mountains = pow(ridged_fbm(q * 0.42 + 5.0, 8), 1.3) * 1250.0 * (mmask + mmask2);
	float plateau = west * 58.0 * smoothstep(0.02, 0.15, s);
	float valley = 1.0 - 0.55 * exp(-pow((q.y - 1.2) / 0.6, 2.0)) * smoothstep(-0.5, 0.8, q.x);
	float land = (hills + plateau) * valley + mountains;
	land *= smoothstep(-0.02, 0.35, s) * 0.6 + 0.4;
	// Small relief the 2.5 m grid can hold: hummocks and rocky ledges.
	float inland = smoothstep(0.015, 0.09, s);
	float hummock = plain_fbm(q * 42.0 + 19.0, 4) * 2.1 + plain_fbm(q * 150.0 + 4.0, 3) * 0.55;
	float ledge_m = smoothstep(0.1, 0.55, plain_fbm(q * 2.3 + 31.0, 4) + mmask * 0.6 + west * 0.25);
	float ledges = ridged_fbm(q * 7.5 + 2.0, 6) * 6.0 * ledge_m * ledge_m;
	land += (hummock + ledges) * inland;

	// Shore profile: sharp cliffs to the west, wide beaches to the east.
	float edge_w = mix(0.11, 0.009, west);
	float k = smoothstep(-0.006, edge_w, s);
	float sea = -6.0 - 70.0 * smoothstep(0.0, -0.35, s);
	float beach = 1.2 + 3.0 * smoothstep(0.0, 0.05, s);
	float shore = mix(beach, land, smoothstep(0.02, 0.09, s) * (1.0 - west) + west);
	float h = mix(sea, shore, k);

	// Sea stacks and islets off the sunset coast.
	h = max(h, -60.0 + islet(q, vec2(-4.55, -0.6), 0.22, 95.0));
	h = max(h, -60.0 + islet(q, vec2(-4.25, 0.75), 0.12, 60.0));
	h = max(h, -60.0 + islet(q, vec2(-3.9, -1.75), 0.08, 42.0));
	h = max(h, -60.0 + islet(q, vec2(4.6, 1.6), 0.3, 70.0));
	return h;
}

void fragment() {
	vec2 p = (UV - 0.5) * world_size;
	float h = island_height(p);
	float hn = clamp((h + 200.0) / 1000.0, 0.0, 1.0);
	float hi = floor(hn * 1024.0) / 1024.0;
	COLOR = vec4(hi, (hn - hi) * 1024.0, 0.0, 1.0);
}

// Physically based atmosphere (Hillaire 2020, "A Scalable and Production Ready
// Sky and Atmosphere Rendering Technique"). All distances in kilometres, the
// planet centre is the origin and the camera sits on the +Y axis.

#ifndef ATMOSPHERE_INC
#define ATMOSPHERE_INC

const float R_GROUND = 6360.0;
const float R_TOP = 6460.0;

const vec3 RAYLEIGH_SCATTER = vec3(5.802, 13.558, 33.1) * 1e-3;
const float RAYLEIGH_H = 8.0;
const float MIE_SCATTER = 3.996e-3;
const float MIE_EXTINCT = 4.44e-3;
const float MIE_H = 1.2;
const float MIE_G = 0.8;
const vec3 OZONE_ABSORB = vec3(0.650, 1.881, 0.085) * 1e-3;
const vec3 GROUND_ALBEDO = vec3(0.12, 0.13, 0.11);

global uniform vec3 sun_direction;
global uniform vec3 moon_direction;
global uniform vec3 sun_illuminance;
global uniform vec3 moon_illuminance;
global uniform float mie_scale;
global uniform float ozone_scale;

// --- geometry -----------------------------------------------------------------

// Ray / origin-centred sphere. Returns (near, far); far < 0 means no hit.
vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float len = length(ro);
	float c = (len - r) * (len + r);
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(-1.0, -1.0);
	}
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

// Soft planet shadow: 1 when the light is above the local horizon at radius r.
float horizon_visibility(float r, float mu) {
	float s = R_GROUND / r;
	float mu_h = -sqrt(max(0.0, 1.0 - s * s));
	return clamp((mu - mu_h) / 0.012 + 0.5, 0.0, 1.0);
}

// --- medium -------------------------------------------------------------------

void atmo_medium(float alt, out vec3 scat_r, out vec3 scat_m, out vec3 extinction) {
	alt = max(alt, 0.0);
	float dr = exp(-alt / RAYLEIGH_H);
	float dm = exp(-alt / MIE_H) * mie_scale;
	float doz = max(0.0, 1.0 - abs(alt - 25.0) / 15.0) * ozone_scale;
	scat_r = RAYLEIGH_SCATTER * dr;
	scat_m = vec3(MIE_SCATTER * dm);
	extinction = scat_r + vec3(MIE_EXTINCT * dm) + OZONE_ABSORB * doz;
}

vec3 atmo_extinction(float alt) {
	vec3 a;
	vec3 b;
	vec3 e;
	atmo_medium(alt, a, b, e);
	return e;
}

float phase_rayleigh(float c) {
	return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

float phase_mie(float c, float g) {
	float g2 = g * g;
	float k = 3.0 / (8.0 * PI) * (1.0 - g2) / (2.0 + g2);
	return k * (1.0 + c * c) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5);
}

float phase_hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

// --- transmittance LUT parameterisation (Bruneton) ----------------------------

const float ATMO_H = 1129.4246; // sqrt(R_TOP^2 - R_GROUND^2)

vec2 transmittance_uv(float r, float mu) {
	float rho = sqrt(max(0.0, (r - R_GROUND) * (r + R_GROUND)));
	float disc = r * r * (mu * mu - 1.0) + R_TOP * R_TOP;
	float d = max(0.0, -r * mu + sqrt(max(disc, 0.0)));
	float d_min = R_TOP - r;
	float d_max = rho + ATMO_H;
	return vec2((d - d_min) / max(d_max - d_min, 1e-4), rho / ATMO_H);
}

void transmittance_params(vec2 uv, out float r, out float mu) {
	float rho = ATMO_H * uv.y;
	r = sqrt(rho * rho + R_GROUND * R_GROUND);
	float d_min = R_TOP - r;
	float d_max = rho + ATMO_H;
	float d = d_min + uv.x * (d_max - d_min);
	mu = d == 0.0 ? 1.0 : (ATMO_H * ATMO_H - rho * rho - d * d) / (2.0 * r * d);
	mu = clamp(mu, -1.0, 1.0);
}

// Sub-texel safe lookup into a LUT of the given size.
vec2 lut_uv(vec2 uv, vec2 size) {
	return (uv * (size - 1.0) + 0.5) / size;
}

vec3 sample_transmittance(sampler2D lut, float r, float mu) {
	return texture(lut, lut_uv(transmittance_uv(r, mu), vec2(256.0, 64.0))).rgb;
}

vec3 sample_multiscatter(sampler2D lut, float r, float mu) {
	vec2 uv = vec2(mu * 0.5 + 0.5, clamp((r - R_GROUND) / (R_TOP - R_GROUND), 0.0, 1.0));
	return texture(lut, lut_uv(uv, vec2(32.0))).rgb;
}

// Transmittance from point (radius r) toward direction with cosine mu, including
// the planet shadow.
vec3 light_transmittance(sampler2D lut, float r, float mu) {
	return sample_transmittance(lut, r, mu) * horizon_visibility(r, mu);
}

// --- single + multiple scattering along a view ray --------------------------

// Integrates in-scattered luminance for one light (unit illuminance).
// ro: position relative to planet centre (km). t_limit: optional max distance.
vec3 integrate_sky(sampler2D t_lut, sampler2D ms_lut, vec3 ro, vec3 rd, vec3 ldir,
		float t_limit, int steps, out vec3 transmittance) {
	transmittance = vec3(1.0);
	vec2 top = ray_sphere(ro, rd, R_TOP);
	if (top.y < 0.0) {
		return vec3(0.0);
	}
	vec2 gnd = ray_sphere(ro, rd, R_GROUND);
	float t_start = max(top.x, 0.0);
	float t_end = top.y;
	if (gnd.x > 0.0) {
		t_end = min(t_end, gnd.x);
	}
	t_end = min(t_end, t_limit);
	float cos_t = dot(rd, ldir);
	float ph_r = phase_rayleigh(cos_t);
	float ph_m = phase_mie(cos_t, MIE_G);
	vec3 lum = vec3(0.0);
	float span = t_end - t_start;
	float prev = 0.0;
	for (int i = 0; i < steps; i++) {
		float f = (float(i) + 1.0) / float(steps);
		float t1 = f * f * span;
		float dt = t1 - prev;
		float t = t_start + prev + dt * 0.3;
		prev = t1;
		vec3 p = ro + rd * t;
		float r = length(p);
		vec3 up = p / r;
		float mu_l = dot(up, ldir);
		vec3 sr;
		vec3 sm;
		vec3 ext;
		atmo_medium(r - R_GROUND, sr, sm, ext);
		vec3 t_sun = light_transmittance(t_lut, r, mu_l);
		vec3 ms = sample_multiscatter(ms_lut, r, mu_l);
		vec3 s = (sr * ph_r + sm * ph_m) * t_sun + ms * (sr + sm);
		vec3 step_t = exp(-ext * dt);
		lum += transmittance * (s - s * step_t) / max(ext, vec3(1e-7));
		transmittance *= step_t;
	}
	return lum;
}

float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

#endif

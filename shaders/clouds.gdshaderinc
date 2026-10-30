// Volumetric cloud layer (Schneider, "The real-time volumetric cloudscapes of
// Horizon Zero Dawn") on a spherical shell, plus a 2D cirrus layer.
// Distances in km. Requires atmosphere.gdshaderinc.

#ifndef CLOUDS_INC
#define CLOUDS_INC

global uniform float cloud_coverage;
global uniform float cloud_type;
global uniform float cloud_density;
global uniform float cloud_bottom;
global uniform float cloud_thickness;
global uniform vec2 cloud_wind;
global uniform float cloud_evolve;
global uniform float cirrus_coverage;
global uniform vec2 cirrus_offset;

uniform sampler3D cloud_shape : filter_linear, repeat_enable;
uniform sampler3D cloud_detail : filter_linear, repeat_enable;
uniform sampler2D cloud_weather : filter_linear_mipmap, repeat_enable;

const float CLOUD_EXTINCTION = 62.0; // per km at density 1
const float SHAPE_TILE = 5.5;
const float DETAIL_TILE = 0.85;
const float WEATHER_TILE = 46.0;
const float CIRRUS_ALT = 8.5;

float cloud_height_profile(float hf, float type, float cov) {
	float top = mix(0.22, 1.0, type) * mix(0.45, 1.0, cov);
	float bottom = smoothstep(0.0, mix(0.04, 0.12, type), hf);
	float cap = 1.0 - smoothstep(top * mix(0.35, 0.65, type), top, hf);
	return bottom * cap;
}

vec4 cloud_weather_at(vec2 xz) {
	return textureLod(cloud_weather, (xz + cloud_wind * 0.55) / WEATHER_TILE, 0.0);
}

float cloud_local_coverage(vec4 w) {
	float c = cloud_coverage;
	return smoothstep(1.0 - 1.12 * c, 1.32 - 1.12 * c, w.r) * clamp(c * 3.0, 0.0, 1.0);
}

// wp: (x, altitude, z) in km.
float cloud_density_at(vec3 wp, float hf, bool detail) {
	vec4 w = cloud_weather_at(wp.xz);
	float cov = cloud_local_coverage(w);
	float type = clamp(cloud_type + (w.g - 0.5) * 0.5, 0.0, 1.0);
	float prof = cloud_height_profile(hf, type, cov);
	if (cov * prof < 0.01) {
		return 0.0;
	}
	vec3 sp = vec3(wp.x + cloud_wind.x, wp.y * 1.1 - cloud_evolve * 0.15, wp.z + cloud_wind.y) / SHAPE_TILE;
	vec4 n = textureLod(cloud_shape, sp, 0.0);
	float fbm = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
	float base = clamp((n.r - (fbm - 1.0)) / (2.0 - fbm), 0.0, 1.0);
	base = clamp((base - 0.32) / 0.68, 0.0, 1.0) * prof;
	base = clamp((base - (1.0 - cov)) / max(cov, 1e-3), 0.0, 1.0) * cov;
	if (base <= 0.0) {
		return 0.0;
	}
	if (detail) {
		vec3 dp = (vec3(wp.x + cloud_wind.x * 1.25, wp.y + cloud_evolve * 0.3, wp.z + cloud_wind.y * 1.25)) / DETAIL_TILE;
		vec3 dn = textureLod(cloud_detail, dp, 0.0).rgb;
		float dfbm = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
		float dmod = mix(dfbm, 1.0 - dfbm, clamp(hf * 5.0, 0.0, 1.0));
		base = clamp((base - dmod * 0.55) / max(1.0 - dmod * 0.55, 1e-3), 0.0, 1.0);
	}
	return base * cloud_density;
}

float cloud_phase(float c) {
	return mix(phase_hg(c, 0.78), phase_hg(c, -0.22), 0.32) + phase_hg(c, 0.97) * 0.08;
}

// Marches the cumulus layer. Returns (luminance, transmittance).
// ro: camera relative to planet centre, cam_xz: camera horizontal km.
vec4 march_clouds(sampler2D t_lut, sampler2D amb_lut, vec3 ro, vec2 cam_xz, vec3 rd,
		int steps, int light_steps, bool detail, float jitter, out float mean_dist) {
	mean_dist = 1e6;
	if (cloud_coverage < 0.01) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float r_in = R_GROUND + cloud_bottom;
	float r_out = r_in + cloud_thickness;
	float rc = length(ro);
	vec2 hin = ray_sphere(ro, rd, r_in);
	vec2 hout = ray_sphere(ro, rd, r_out);
	vec2 gnd = ray_sphere(ro, rd, R_GROUND);
	float t0;
	float t1;
	if (rc < r_in) {
		if (gnd.x > 0.0) {
			return vec4(0.0, 0.0, 0.0, 1.0);
		}
		t0 = hin.y;
		t1 = hout.y;
	} else if (rc < r_out) {
		t0 = 0.0;
		t1 = hin.x > 0.0 ? hin.x : hout.y;
	} else {
		if (hout.y < 0.0) {
			return vec4(0.0, 0.0, 0.0, 1.0);
		}
		t0 = max(hout.x, 0.0);
		t1 = hin.x > 0.0 ? hin.x : hout.y;
	}
	if (t0 > 90.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	t1 = min(t1, t0 + 35.0);

	// Light and ambient for this view (sun and moon handled as one light).
	bool use_moon = sun_direction.y < -0.08;
	vec3 ldir = use_moon ? moon_direction : sun_direction;
	vec3 lillum = use_moon ? moon_illuminance : sun_illuminance;
	float mu_amb = sun_direction.y * 0.5 + 0.5;
	vec3 amb_top = texture(amb_lut, vec2(mu_amb, 0.75)).rgb * sun_illuminance;
	vec3 amb_low = texture(amb_lut, vec2(mu_amb, 0.25)).rgb * sun_illuminance;
	// Thick decks scatter light many times: greyer, brighter undersides.
	float deck = smoothstep(0.55, 0.95, cloud_coverage);
	amb_top = mix(amb_top, vec3(luminance(amb_top)), 0.35 + 0.5 * deck);
	amb_low = mix(amb_low, vec3(luminance(amb_low)), 0.35 + 0.5 * deck);
	vec3 deck_light = light_transmittance(t_lut, r_out, sun_direction.y) * sun_illuminance
			* max(sun_direction.y, 0.0) * 0.06 * deck;
	amb_top += deck_light;
	amb_low += deck_light * 0.6;
	if (use_moon) {
		amb_top += moon_illuminance * vec3(0.04, 0.05, 0.08);
		amb_low += moon_illuminance * vec3(0.03, 0.035, 0.05);
	}

	float cos_t = dot(rd, ldir);
	float ph0 = cloud_phase(cos_t);
	float ph1 = mix(phase_hg(cos_t, 0.39), phase_hg(cos_t, -0.11), 0.32);
	float ph2 = mix(phase_hg(cos_t, 0.19), phase_hg(cos_t, -0.05), 0.32);
	float dt = (t1 - t0) / float(steps);
	vec3 lum = vec3(0.0);
	float trans = 1.0;
	float dist_acc = 0.0;
	float w_acc = 0.0;
	for (int i = 0; i < steps; i++) {
		float t = t0 + (float(i) + jitter) * dt;
		vec3 p = ro + rd * t;
		float r = length(p);
		float hf = (r - r_in) / cloud_thickness;
		vec3 wp = vec3(cam_xz.x + p.x, r - R_GROUND, cam_xz.y + p.z);
		float d = cloud_density_at(wp, hf, detail);
		if (d > 0.003) {
			vec3 up = p / r;
			float mu_l = dot(up, ldir);
			vec3 lcol = light_transmittance(t_lut, r, mu_l) * lillum;
			float od = 0.0;
			float ls = cloud_thickness * 0.06;
			vec3 lp = p;
			for (int j = 0; j < light_steps; j++) {
				lp += ldir * ls;
				float lr = length(lp);
				float lhf = (lr - r_in) / cloud_thickness;
				if (lhf > 1.0) {
					break;
				}
				od += cloud_density_at(vec3(cam_xz.x + lp.x, lr - R_GROUND, cam_xz.y + lp.z), lhf, false) * ls;
				ls *= 1.9;
			}
			float tau = od * CLOUD_EXTINCTION;
			float sun_term = ph0 * exp(-tau) + ph1 * 0.5 * exp(-tau * 0.25) + ph2 * 0.25 * exp(-tau * 0.0625);
			float powder = 1.0 - exp(-d * 6.0);
			sun_term *= mix(1.0, powder * 1.6, 0.45 * (1.0 - cos_t * 0.5));
			vec3 amb = mix(amb_low * 0.6, amb_top, clamp(hf * 1.4, 0.0, 1.0));
			vec3 s = lcol * sun_term * 1.6 + amb * (0.4 + 0.5 * hf);
			float ext = d * CLOUD_EXTINCTION;
			float step_t = exp(-ext * dt);
			float contrib = trans * (1.0 - step_t);
			lum += s * contrib;
			dist_acc += t * contrib;
			w_acc += contrib;
			trans *= step_t;
			if (trans < 0.015) {
				break;
			}
		}
	}
	if (w_acc > 0.0) {
		mean_dist = dist_acc / w_acc;
	}
	return vec4(lum, trans);
}

// High thin ice-cloud layer. Returns (luminance, alpha).
vec4 cirrus_layer(sampler2D t_lut, sampler2D amb_lut, vec3 ro, vec2 cam_xz, vec3 rd) {
	if (cirrus_coverage < 0.01 || rd.y < -0.02) {
		return vec4(0.0);
	}
	float rc = R_GROUND + CIRRUS_ALT;
	vec2 h = ray_sphere(ro, rd, rc);
	if (h.y < 0.0) {
		return vec4(0.0);
	}
	vec3 p = ro + rd * h.y;
	vec2 xz = cam_xz + p.xz;
	vec2 uv = (xz + cirrus_offset) / 38.0;
	float c = textureLod(cloud_weather, uv, 0.0).b;
	float c2 = textureLod(cloud_weather, uv * 3.1 + 0.37, 0.0).b;
	float dens = smoothstep(1.0 - cirrus_coverage, 1.0 - cirrus_coverage * 0.35, c * 0.75 + c2 * 0.35);
	dens *= smoothstep(0.0, 0.08, rd.y + 0.02);
	if (dens <= 0.0) {
		return vec4(0.0);
	}
	vec3 up = p / length(p);
	bool use_moon = sun_direction.y < -0.08;
	vec3 ldir = use_moon ? moon_direction : sun_direction;
	vec3 lillum = use_moon ? moon_illuminance : sun_illuminance;
	vec3 lcol = light_transmittance(t_lut, rc, dot(up, ldir)) * lillum;
	float cos_t = dot(rd, ldir);
	float ph = mix(phase_hg(cos_t, 0.7), phase_hg(cos_t, -0.1), 0.4) * 4.0 * PI;
	vec3 amb = texture(amb_lut, vec2(sun_direction.y * 0.5 + 0.5, 0.75)).rgb * sun_illuminance;
	float alpha = dens * 0.55;
	vec3 lum = (lcol * ph * 0.16 + amb * 0.5) * alpha;
	return vec4(lum, alpha);
}

#endif

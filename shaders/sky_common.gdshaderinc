// Full sky: atmosphere, sun, moon, stars, cirrus and cumulus clouds.
// Shared by the visible sky dome and the environment (radiance) sky shader.

#ifndef SKY_COMMON_INC
#define SKY_COMMON_INC

#include "res://shaders/atmosphere.gdshaderinc"
#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
uniform sampler2D multiscatter_lut : filter_linear, repeat_disable;
uniform sampler2D ambient_lut : filter_linear, repeat_disable;
uniform float sun_disk_radius = 0.0075;
uniform float sun_disk_intensity = 70.0;
uniform int cloud_steps = 42;
uniform int cloud_light_steps = 4;

global uniform float star_rotation;
global uniform float night_factor;

const float LATITUDE = 0.8727; // 50 degrees, matches TimeOfDay.LATITUDE

uvec3 sky_pcg(uvec3 v) {
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

vec3 sky_hash(vec3 c) {
	return vec3(sky_pcg(uvec3(ivec3(c) + ivec3(65536)))) / 4294967295.0;
}

// World direction -> celestial (equatorial) frame rotating with the hour angle.
vec3 to_celestial(vec3 d) {
	// Tilt so the celestial pole (north = -Z, elevated by latitude) becomes +Y.
	float a = PI * 0.5 - LATITUDE;
	vec3 t = vec3(d.x, d.y * cos(a) - d.z * sin(a), d.y * sin(a) + d.z * cos(a));
	float s = sin(star_rotation);
	float c = cos(star_rotation);
	return vec3(t.x * c - t.z * s, t.y, t.x * s + t.z * c);
}

vec3 star_field(vec3 rd, float px_angle) {
	vec3 d = to_celestial(rd);
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 220.0 : 520.0;
		vec3 p = d * scale;
		vec3 id = floor(p);
		vec3 f = p - id;
		vec3 h = sky_hash(id + float(layer) * 977.0);
		float threshold = layer == 0 ? 0.955 : 0.93;
		if (h.x > threshold) {
			vec3 centre = 0.2 + 0.6 * sky_hash(id + 31.0);
			float dist = length(f - centre) / scale;
			float size = max(px_angle * 0.9, 0.00035);
			float b = pow((h.x - threshold) / (1.0 - threshold), 5.0) * (layer == 0 ? 0.05 : 0.012);
			float twinkle = 0.75 + 0.25 * sin(h.y * 400.0 + star_rotation * 900.0 * (0.5 + h.z));
			vec3 tint = mix(vec3(1.0, 0.72, 0.5), vec3(0.65, 0.78, 1.0), h.z);
			col += tint * b * twinkle * exp(-dist * dist / (size * size)) * (0.00035 * 0.00035) / (size * size);
		}
	}
	// Milky Way: soft band with dust lanes along a tilted great circle.
	vec3 gal_n = normalize(vec3(0.35, 0.45, 0.82));
	float b = dot(d, gal_n);
	float band = exp(-b * b / 0.018);
	float dust = textureLod(cloud_shape, d * 1.7, 0.0).g;
	float grain = textureLod(cloud_detail, d * 6.0, 0.0).r;
	float core = exp(-b * b / 0.004);
	float lanes = smoothstep(0.42, 0.72, dust) * exp(-b * b / 0.002);
	col += vec3(0.62, 0.64, 0.78) * (band * 0.5 + core) * (0.35 + 0.65 * smoothstep(0.3, 0.85, grain)) * (1.0 - 0.8 * lanes) * 0.00022;
	return col;
}

vec3 moon_disk(vec3 rd, vec3 mdir, vec3 sdir) {
	const float MOON_R = 0.0085;
	float c = dot(rd, mdir);
	if (c < cos(MOON_R * 1.05)) {
		return vec3(0.0);
	}
	// Reconstruct the visible hemisphere normal.
	vec3 right = normalize(cross(mdir, vec3(0.0, 1.0, 0.0)));
	vec3 upv = cross(right, mdir);
	vec2 q = vec2(dot(rd, right), dot(rd, upv)) / MOON_R;
	float rr = dot(q, q);
	if (rr > 1.0) {
		return vec3(0.0);
	}
	vec3 n = normalize(q.x * right + q.y * upv - sqrt(1.0 - rr) * mdir);
	float lit = clamp(dot(n, sdir) * 1.2 + 0.05, 0.0, 1.0);
	float maria = textureLod(cloud_shape, n * 0.9 + 0.3, 0.0).r;
	float albedo = mix(0.55, 1.0, smoothstep(0.35, 0.65, maria));
	return vec3(1.0, 0.97, 0.92) * lit * albedo * 0.9 + vec3(0.02, 0.025, 0.035);
}

vec3 sun_disk(vec3 rd, vec3 sdir) {
	float c = dot(rd, sdir);
	float cr = cos(sun_disk_radius);
	if (c < cos(sun_disk_radius * 1.6)) {
		return vec3(0.0);
	}
	float ang = acos(clamp(c, -1.0, 1.0)) / sun_disk_radius;
	float disk = 1.0 - smoothstep(0.92, 1.0, ang);
	float mu = sqrt(max(0.0, 1.0 - ang * ang));
	vec3 limb = pow(vec3(max(mu, 0.0)), vec3(0.397, 0.503, 0.652));
	float corona = exp(-max(ang - 1.0, 0.0) * 6.0) * 0.04;
	return sun_illuminance * (limb * disk * sun_disk_intensity + corona * sun_disk_intensity);
}

// rd: world view direction, cam: camera world position in metres.
// quality: 0 = environment/radiance, 1 = visible dome.
vec3 render_sky(vec3 rd, vec3 cam, float jitter, float px_angle, int quality) {
	float alt = max(cam.y, 2.0) * 0.001;
	vec3 ro = vec3(0.0, R_GROUND + alt, 0.0);
	vec2 cam_xz = cam.xz * 0.001;
	int steps = quality == 1 ? 28 : 14;

	vec3 tr;
	vec3 sky = integrate_sky(transmittance_lut, multiscatter_lut, ro, rd, sun_direction, 1e9, steps, tr) * sun_illuminance;
	if (night_factor > 0.001) {
		vec3 tr_m;
		sky += integrate_sky(transmittance_lut, multiscatter_lut, ro, rd, moon_direction, 1e9, steps / 2, tr_m) * moon_illuminance;
	}

	vec2 gnd = ray_sphere(ro, rd, R_GROUND);
	if (gnd.x > 0.0) {
		// Ground seen below the horizon (only shows in reflections / ambient).
		vec3 gp = ro + rd * gnd.x;
		vec3 n = normalize(gp);
		float mu_s = dot(n, sun_direction);
		vec3 irr = light_transmittance(transmittance_lut, R_GROUND, mu_s) * max(mu_s, 0.0) * sun_illuminance
				+ texture(ambient_lut, vec2(sun_direction.y * 0.5 + 0.5, 0.25)).rgb * sun_illuminance * PI;
		sky += tr * irr * GROUND_ALBEDO / PI;
		return sky;
	}

	vec3 view_t = tr;
	if (quality == 1) {
		sky += sun_disk(rd, sun_direction) * view_t;
	}
	if (night_factor > 0.001) {
		sky += (star_field(rd, px_angle) + moon_disk(rd, moon_direction, sun_direction) * moon_illuminance * 25.0)
				* view_t * night_factor;
	}

	vec4 ci = cirrus_layer(transmittance_lut, ambient_lut, ro, cam_xz, rd);
	float cirrus_fade = smoothstep(-0.01, 0.12, rd.y);
	sky = sky * (1.0 - ci.a * cirrus_fade) + ci.rgb * cirrus_fade * mix(vec3(1.0), view_t, 0.35);

	if (quality == 2) {
		return sky;
	}
	float md;
	vec4 cl = march_clouds(transmittance_lut, ambient_lut, ro, cam_xz, rd,
			quality == 1 ? cloud_steps : 18, quality == 1 ? cloud_light_steps : 2, quality == 1, jitter, md);
	// Aerial perspective: distant clouds dissolve into the sky.
	float fade = exp(-md / mix(32.0, 12.0, clamp((mie_scale - 1.0) / 4.0, 0.0, 1.0)));
	float cloud_alpha = (1.0 - cl.a) * fade;
	sky = sky * (1.0 - cloud_alpha) + cl.rgb * fade;
	return sky;
}

#endif

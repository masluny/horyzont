// Ocean on a camera-centred clipmap. Gerstner swells near the camera, scrolling
// ripple normals, depth-based colour from the terrain heightmap (turquoise
// shallows, dark deep water), shore foam, rain rings and sun glitter.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/terrain_common.gdshaderinc"

uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;

global uniform vec2 world_wind;
global uniform float rain_amount;
global uniform vec3 sun_direction;
global uniform float night_factor;

instance uniform vec2 center;
instance uniform float spacing = 1.5;
instance uniform vec2 inner_center;
instance uniform float inner_half = 0.0;

varying vec3 world_pos;
varying vec3 wave_normal;
varying float crest;

// Direction, wavelength (m), steepness.
const int WAVES = 5;
const vec4 WAVE[5] = vec4[](
	vec4(0.94, 0.34, 46.0, 0.16),
	vec4(0.71, -0.70, 27.0, 0.14),
	vec4(0.99, 0.12, 15.0, 0.13),
	vec4(0.32, 0.95, 9.0, 0.11),
	vec4(0.83, -0.56, 5.3, 0.09)
);

void gerstner(vec2 p, float t, float amp_scale, inout vec3 offset, inout vec3 tangent, inout vec3 binormal) {
	for (int i = 0; i < WAVES; i++) {
		vec2 d = normalize(WAVE[i].xy);
		float wl = WAVE[i].z;
		float k = 2.0 * PI / wl;
		float c = sqrt(9.81 / k);
		float a = WAVE[i].w / k * amp_scale;
		float f = k * (dot(d, p) - c * t);
		float s = sin(f);
		float co = cos(f);
		offset += vec3(d.x * a * co, a * s, d.y * a * co);
		tangent += vec3(-d.x * d.x * WAVE[i].w * s * amp_scale, d.x * WAVE[i].w * co * amp_scale, -d.x * d.y * WAVE[i].w * s * amp_scale);
		binormal += vec3(-d.x * d.y * WAVE[i].w * s * amp_scale, d.y * WAVE[i].w * co * amp_scale, -d.y * d.y * WAVE[i].w * s * amp_scale);
	}
}

void vertex() {
	vec2 wxz = center + VERTEX.xz * spacing;
	vec2 dd = abs(wxz - CAMERA_POSITION_WORLD.xz) / spacing;
	float m = clamp((max(dd.x, dd.y) - 46.0) / 13.0, 0.0, 1.0);
	vec2 g = round(wxz / spacing);
	vec2 odd = g - 2.0 * floor(g * 0.5);
	wxz -= odd * spacing * m;
	float dist = length(wxz - CAMERA_POSITION_WORLD.xz);
	float depth = -terrain_height(wxz);
	float wind = clamp(length(world_wind) / 12.0, 0.4, 1.6);
	// Waves shrink in the shallows and fade out far away (normals take over).
	float amp = wind * smoothstep(0.0, 6.0, depth) * (1.0 - smoothstep(600.0, 2500.0, dist));
	vec3 off = vec3(0.0);
	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	gerstner(wxz, TIME, amp, off, tan, bin);
	VERTEX = vec3(wxz.x + off.x, off.y, wxz.y + off.z);
	world_pos = VERTEX;
	wave_normal = normalize(cross(bin, tan));
	crest = clamp(off.y / (0.9 * wind) * 0.5 + 0.5, 0.0, 1.0) * amp;
}

void fragment() {
	if (inner_half > 0.0) {
		vec2 dd = abs(world_pos.xz - inner_center);
		if (max(dd.x, dd.y) < inner_half - 0.01) {
			discard;
		}
	}
	float t = TIME;
	vec2 wdir = normalize(world_wind + vec2(1e-3));
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 uv1 = world_pos.xz / 11.0 + wdir * t * 0.035;
	vec2 uv2 = world_pos.xz / 4.3 - wdir.yx * t * 0.05;
	vec3 r1 = texture(ripple_a, uv1).rgb * 2.0 - 1.0;
	vec3 r2 = texture(ripple_b, uv2).rgb * 2.0 - 1.0;
	vec3 r3 = texture(ripple_a, world_pos.xz / 63.0 + wdir * t * 0.012).rgb * 2.0 - 1.0;
	float ripple_k = mix(1.0, 0.35, smoothstep(50.0, 1500.0, dist));
	vec3 n = wave_normal;
	n += (vec3(r1.x, 0.0, -r1.y) * 0.35 + vec3(r2.x, 0.0, -r2.y) * 0.22) * ripple_k + vec3(r3.x, 0.0, -r3.y) * 0.25;

	// Rain: expanding rings on a grid of random drops.
	if (rain_amount > 0.01 && dist < 60.0) {
		vec2 cell = floor(world_pos.xz * 1.6);
		vec2 f = fract(world_pos.xz * 1.6) - 0.5;
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float ph = fract(t * 0.9 + h);
		float ring = sin((length(f) - ph * 0.5) * 60.0) * (1.0 - ph) * smoothstep(0.5, 0.0, length(f));
		n.xz += normalize(f + 1e-4) * ring * 0.25 * rain_amount;
	}
	n = normalize(n);

	float depth = max(world_pos.y - terrain_height(world_pos.xz), 0.0);
	vec3 deep = vec3(0.004, 0.018, 0.03);
	vec3 shallow = vec3(0.05, 0.25, 0.24);
	vec3 sand = vec3(0.32, 0.28, 0.2);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 14.0, depth));
	col = mix(sand * 0.55, col, smoothstep(0.0, 1.6, depth));
	col *= mix(1.0, 0.25, night_factor);

	// Shore foam: bands that move in with the swell, broken up by noise.
	float fn = texture(foam_noise, world_pos.xz / 7.0 + vec2(t * 0.02, 0.0)).r;
	float shore = smoothstep(2.2, 0.0, depth);
	float band = smoothstep(0.55, 0.9, sin(depth * 3.0 - t * 1.3) * 0.5 + 0.5);
	float foam = shore * clamp(band * 0.8 + smoothstep(0.6, 0.0, depth), 0.0, 1.0) * smoothstep(0.35, 0.7, fn);
	foam += smoothstep(0.86, 1.0, crest) * smoothstep(0.62, 0.85, fn) * clamp(length(world_wind) / 14.0 - 0.6, 0.0, 1.0);
	foam = clamp(foam, 0.0, 1.0);

	// Light shining through wave crests.
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float sss = pow(clamp(dot(v, -vec3(sun_direction.x, 0.0, sun_direction.z)) * 0.5 + 0.5, 0.0, 1.0), 4.0) * crest;
	col += vec3(0.02, 0.09, 0.07) * sss * clamp(sun_direction.y * 4.0 + 0.2, 0.0, 1.0);

	ALBEDO = mix(col, vec3(0.85), foam);
	ROUGHNESS = mix(mix(0.03, 0.09, smoothstep(100.0, 3000.0, dist)), 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.28, 0.5, foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

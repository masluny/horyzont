// Island terrain on a geometry clipmap. Heights come from the CPU-carved
// heightmap; normals and masks from a baked texture. Custom sun lighting so
// moving cloud shadows only affect direct light.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain_common.gdshaderinc"

uniform sampler2D normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D maskmap : filter_linear_mipmap, repeat_disable;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_arm : filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D cloud_weather : filter_linear_mipmap, repeat_enable;

global uniform vec3 sun_direction;
global uniform float cloud_coverage;
global uniform float cloud_density;
global uniform float cloud_bottom;
global uniform vec2 cloud_wind;
global uniform float wetness;

uniform int debug_mode = 0;
instance uniform vec2 center;
instance uniform float spacing = 1.5;
instance uniform vec2 inner_center;
instance uniform float inner_half = 0.0;

varying vec3 world_pos;
varying float cloud_light;

void vertex() {
	vec2 wxz = center + VERTEX.xz * spacing;
	vec2 d = abs(wxz - CAMERA_POSITION_WORLD.xz) / spacing;
	float k = max(d.x, d.y);
	float m = clamp((k - 46.0) / 13.0, 0.0, 1.0);
	vec2 g = round(wxz / spacing);
	vec2 odd = g - 2.0 * floor(g * 0.5);
	wxz -= odd * spacing * m;
	float h = terrain_height(wxz);
	VERTEX = vec3(wxz.x, h, wxz.y);
	world_pos = VERTEX;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

// The grass texture is used for detail only; colour comes from a meadow palette.
vec3 meadow_color(float macro, float ridge) {
	float dry = clamp(macro * 1.2 - 0.25 + ridge * 0.8, 0.0, 1.0);
	return mix(vec3(0.062, 0.115, 0.026), vec3(0.17, 0.165, 0.055), dry);
}

vec3 meadow_tint(vec3 tex, float macro, float ridge) {
	float l = dot(tex, vec3(0.2126, 0.7152, 0.0722)) / 0.23;
	return mix(tex, meadow_color(macro, ridge) * l, 0.82);
}

// Two rotated/scaled lookups blended by noise to hide tiling.
vec4 sample_mix(sampler2D tex, vec2 uv, float n) {
	vec2 uv2 = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * uv * 0.61 + 0.37;
	return mix(texture(tex, uv), texture(tex, uv2), n);
}

void fragment() {
	if (inner_half > 0.0) {
		vec2 dd = abs(world_pos.xz - inner_center);
		if (max(dd.x, dd.y) < inner_half - 0.01) {
			discard;
		}
	}
	vec2 tuv = (world_pos.xz + WORLD_SIZE * 0.5) / WORLD_SIZE;
	vec4 nm = texture(normalmap, tuv);
	vec2 nxz = nm.rg * 2.0 - 1.0;
	vec3 n_geo = normalize(vec3(nxz.x, sqrt(max(0.0, 1.0 - dot(nxz, nxz))), nxz.y));
	float road = texture(maskmap, tuv).r;
	float cavity = nm.b - 0.5;
	float ridge = nm.a - 0.5;
	float h = world_pos.y;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);

	float macro = vnoise(world_pos.xz * 0.004) * 0.6 + vnoise(world_pos.xz * 0.017) * 0.4;
	float tile_n = smoothstep(0.3, 0.7, vnoise(world_pos.xz * 0.02 + 7.0));
	float slope = 1.0 - n_geo.y;

	float w_rock = smoothstep(0.24, 0.42, slope + (macro - 0.5) * 0.12 - ridge * 0.25);
	w_rock = max(w_rock, smoothstep(330.0, 430.0, h + macro * 60.0) * smoothstep(0.08, 0.2, slope));
	float w_sand = (1.0 - smoothstep(2.0, 5.5, h + (macro - 0.5) * 3.0)) * (1.0 - w_rock);
	float w_gravel = clamp(road * 1.6 - 0.25 + max(cavity, 0.0) * 0.6, 0.0, 1.0) * (1.0 - w_sand) * (1.0 - w_rock * 0.6);
	float w_grass = max(0.0, 1.0 - w_rock - w_sand - w_gravel);

	vec3 alb = vec3(0.0);
	vec3 arm = vec3(1.0, 0.8, 0.0);
	vec3 n = n_geo;
	if (dist < 900.0) {
		vec2 uv_g = world_pos.xz / 3.2;
		vec2 uv_s = world_pos.xz / 3.5;
		vec2 uv_v = world_pos.xz / 2.6;
		vec4 ga = sample_mix(grass_albedo, uv_g, tile_n);
		ga.rgb = meadow_tint(ga.rgb, macro, ridge);
		vec4 sa = sample_mix(sand_albedo, uv_s, tile_n);
		vec4 va = sample_mix(gravel_albedo, uv_v, tile_n) * vec4(0.55, 0.55, 0.55, 1.0);
		// Rock: biplanar on the two dominant side planes + top.
		vec3 bw = pow(abs(n_geo), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec2 uv_rx = world_pos.zy / 7.0;
		vec2 uv_rz = world_pos.xy / 7.0;
		vec2 uv_ry = world_pos.xz / 7.0;
		vec4 ra = texture(rock_albedo, uv_rx) * bw.x + texture(rock_albedo, uv_rz) * bw.z + texture(rock_albedo, uv_ry) * bw.y;

		// Height-aware blending using albedo luminance as a height proxy.
		float hg = dot(ga.rgb, vec3(0.33)) + w_grass;
		float hs = dot(sa.rgb, vec3(0.33)) + w_sand;
		float hv = dot(va.rgb, vec3(0.33)) + w_gravel;
		float hr = dot(ra.rgb, vec3(0.33)) + w_rock;
		float hmax = max(max(hg, hs), max(hv, hr)) - 0.18;
		vec4 bwt = max(vec4(hg, hs, hv, hr) - hmax, 0.0) * vec4(w_grass, w_sand, w_gravel, w_rock);
		bwt /= max(bwt.x + bwt.y + bwt.z + bwt.w, 1e-4);

		alb = ga.rgb * bwt.x + sa.rgb * bwt.y + va.rgb * bwt.z + ra.rgb * bwt.w;
		arm = sample_mix(grass_arm, uv_g, tile_n).rgb * bwt.x + sample_mix(sand_arm, uv_s, tile_n).rgb * bwt.y
				+ sample_mix(gravel_arm, uv_v, tile_n).rgb * bwt.z
				+ (texture(rock_arm, uv_rx).rgb * bw.x + texture(rock_arm, uv_rz).rgb * bw.z + texture(rock_arm, uv_ry).rgb * bw.y) * bwt.w;
		vec3 tn = (sample_mix(grass_normal, uv_g, tile_n).rgb * bwt.x + sample_mix(sand_normal, uv_s, tile_n).rgb * bwt.y
				+ sample_mix(gravel_normal, uv_v, tile_n).rgb * bwt.z) * 2.0 - 1.0;
		vec3 rn_x = texture(rock_normal, uv_rx).rgb * 2.0 - 1.0;
		vec3 rn_z = texture(rock_normal, uv_rz).rgb * 2.0 - 1.0;
		vec3 rn_y = texture(rock_normal, uv_ry).rgb * 2.0 - 1.0;
		float fade = 1.0 - smoothstep(300.0, 900.0, dist);
		// Whiteout-style perturbation in world space.
		vec3 pert = vec3(tn.x, 0.0, -tn.y) * (1.0 - bwt.w)
				+ (vec3(0.0, rn_x.y, rn_x.x) * bw.x + vec3(rn_z.x, rn_z.y, 0.0) * bw.z + vec3(rn_y.x, 0.0, -rn_y.y) * bw.y) * bwt.w;
		n = normalize(n_geo + pert * 0.9 * fade);
		float far_k = smoothstep(500.0, 900.0, dist);
		vec3 far_alb = meadow_color(macro, ridge) * w_grass + textureLod(sand_albedo, uv_s, 9.0).rgb * w_sand
				+ textureLod(gravel_albedo, uv_v, 9.0).rgb * w_gravel + textureLod(rock_albedo, uv_ry, 9.0).rgb * w_rock;
		alb = mix(alb, far_alb, far_k);
	} else {
		vec2 uv = world_pos.xz / 3.2;
		alb = meadow_color(macro, ridge) * w_grass + textureLod(sand_albedo, uv, 9.0).rgb * w_sand
				+ textureLod(gravel_albedo, uv, 9.0).rgb * w_gravel + textureLod(rock_albedo, uv, 9.0).rgb * w_rock;
		arm = vec3(1.0, 0.85, 0.0);
	}

	// Macro variation: dry patches, lush hollows.
	alb *= mix(vec3(1.08, 1.02, 0.86), vec3(0.86, 0.95, 0.88), macro) * (1.0 + cavity * 0.25 * (1.0 - w_rock));
	alb = mix(alb, alb * vec3(0.9, 1.0, 0.8), w_grass * smoothstep(0.0, -0.25, ridge));

	// Rain: darker, glossier, puddles in hollows and on flat ground.
	float porous = 1.0 - w_rock * 0.5;
	float puddle = smoothstep(0.55, 0.8, vnoise(world_pos.xz * 0.15) + max(cavity, 0.0) * 2.0 + (1.0 - slope) * 0.2) * smoothstep(0.92, 0.98, n_geo.y);
	float wet = wetness * (0.6 + 0.4 * puddle);
	alb *= mix(1.0, 0.55, wet * porous);
	float rough = mix(arm.g, 0.08, wet * mix(0.5, 1.0, puddle));
	n = normalize(mix(n, n_geo, wetness * puddle));

	ALBEDO = alb;
	if (debug_mode == 1) { ALBEDO = vec3(w_grass, w_sand, w_rock); }
	if (debug_mode == 2) { ALBEDO = vec3(fract(h / 50.0), road, cavity + 0.5); }
	if (debug_mode == 3) { ALBEDO = n_geo * 0.5 + 0.5; }
	if (debug_mode == 4) { ALBEDO = texture(grass_albedo, world_pos.xz / 3.2).rgb; }
	if (debug_mode == 5) { ALBEDO = texture(rock_albedo, world_pos.xz / 3.2).rgb; }
	if (debug_mode == 6) { ALBEDO = texture(gravel_arm, world_pos.xz / 3.2).rgb; }
	ROUGHNESS = rough;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Cloud shadow sampled where the sun ray meets the cloud base.
	vec2 off = sun_direction.xz / max(sun_direction.y, 0.1) * (cloud_bottom + 0.8);
	vec2 cuv = (world_pos.xz * 0.001 + off + cloud_wind * 0.55) / 46.0;
	float cw = textureLod(cloud_weather, cuv, 2.0).r;
	float c = cloud_coverage;
	float cov = smoothstep(1.0 - 1.12 * c, 1.32 - 1.12 * c, cw) * clamp(c * 3.0, 0.0, 1.0);
	cloud_light = 1.0 - clamp(cov * 1.5 * cloud_density, 0.0, 0.9);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float shadow = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_light : 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ndl * shadow / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float kk = (ROUGHNESS + 1.0) * (ROUGHNESS + 1.0) / 8.0;
	float G = (ndl / (ndl * (1.0 - kk) + kk)) * (ndv / (ndv * (1.0 - kk) + kk));
	float F = 0.04 + 0.96 * pow(1.0 - clamp(dot(VIEW, hv), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * shadow * D * G * F / (4.0 * ndv);
}

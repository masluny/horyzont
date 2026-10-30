// Island terrain on a geometry clipmap. Heights come from the CPU-carved
// heightmap; normals and masks from a baked texture. Custom sun lighting so
// moving cloud shadows only affect direct light.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain_common.gdshaderinc"
#include "res://shaders/atmosphere.gdshaderinc"
#include "res://shaders/clouds.gdshaderinc"

uniform sampler2D normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D maskmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D eco_map : filter_linear_mipmap, repeat_disable;

uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock2_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock2_arm : filter_linear_mipmap_anisotropic, repeat_enable;
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

// Same palette as the grass blades, so far meadows melt into the near ones.
vec3 meadow_color(float dry) {
	return mix(vec3(0.075, 0.17, 0.034), vec3(0.2, 0.19, 0.085), dry * dry);
}

vec3 meadow_tint(vec3 tex, float dry) {
	float l = dot(tex, vec3(0.2126, 0.7152, 0.0722)) / 0.2;
	return mix(tex * 0.7, meadow_color(dry) * l, 0.7);
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
	vec4 eco = texture(eco_map, tuv);
	float dry = clamp(eco.a * 0.95 + (macro - 0.5) * 0.5, 0.0, 1.0);

	float edge_n = vnoise(world_pos.xz * 0.11) * 0.6 + vnoise(world_pos.xz * 0.55) * 0.4;
	float w_rock = smoothstep(0.17, 0.3, slope + (edge_n - 0.5) * 0.14 - ridge * 0.25);
	w_rock = max(w_rock, smoothstep(330.0, 430.0, h + macro * 60.0) * smoothstep(0.08, 0.2, slope));
	float w_sand = (1.0 - smoothstep(2.0, 5.5, h + (edge_n - 0.5) * 3.5)) * (1.0 - w_rock);
	float w_gravel = clamp((road + (edge_n - 0.5) * 0.5) * 2.2 - 1.1, 0.0, 1.0) * (1.0 - w_sand) * (1.0 - w_rock * 0.6);
	float w_forest = smoothstep(0.25, 0.7, eco.g + (edge_n - 0.5) * 0.4) * (1.0 - w_rock) * (1.0 - w_sand) * (1.0 - w_gravel);
	float w_grass = max(0.0, 1.0 - w_rock - w_sand - w_gravel - w_forest);

	vec3 alb = vec3(0.0);
	vec3 arm = vec3(1.0, 0.8, 0.0);
	vec3 n = n_geo;
	if (dist < 700.0) {
		vec2 uv_g = world_pos.xz / 4.6;
		vec2 uv_f = world_pos.xz / 5.4;
		vec2 uv_s = world_pos.xz / 4.0;
		vec2 uv_v = world_pos.xz / 2.3;
		vec3 a_g = vec3(0.0), a_s = vec3(0.0), a_v = vec3(0.0), a_r = vec3(0.0), a_f = vec3(0.0);
		vec3 m_g = vec3(1.0, 0.8, 0.0), m_s = m_g, m_v = m_g, m_r = m_g, m_f = m_g;
		vec3 t_g = vec3(0.0, 0.0, 1.0), t_s = t_g, t_v = t_g, t_f = t_g;
		vec3 p_r = vec3(0.0);
		// Only sample the materials that are actually present here.
		if (w_grass > 0.003) {
			a_g = meadow_tint(sample_mix(grass_albedo, uv_g, tile_n).rgb, dry);
			m_g = texture(grass_arm, uv_g).rgb;
			t_g = texture(grass_normal, uv_g).rgb * 2.0 - 1.0;
		}
		if (w_forest > 0.003) {
			a_f = sample_mix(forest_albedo, uv_f, tile_n).rgb * 0.8;
			m_f = texture(forest_arm, uv_f).rgb;
			t_f = texture(forest_normal, uv_f).rgb * 2.0 - 1.0;
		}
		if (w_sand > 0.003) {
			a_s = sample_mix(sand_albedo, uv_s, tile_n).rgb;
			m_s = texture(sand_arm, uv_s).rgb;
			t_s = texture(sand_normal, uv_s).rgb * 2.0 - 1.0;
		}
		if (w_gravel > 0.003) {
			a_v = sample_mix(gravel_albedo, uv_v, tile_n).rgb;
			a_v = mix(a_v, vec3(dot(a_v, vec3(0.33))), 0.65) * 0.8;
			m_v = texture(gravel_arm, uv_v).rgb;
			t_v = texture(gravel_normal, uv_v).rgb * 2.0 - 1.0;
		}
		if (w_rock > 0.003) {
			// Biplanar: the two dominant projections only.
			vec3 bw = pow(abs(n_geo), vec3(4.0));
			bool side_x = bw.x > bw.z;
			vec2 uv_side = side_x ? world_pos.zy / 9.0 : world_pos.xy / 9.0;
			vec2 uv_top = world_pos.xz / 9.0;
			float ws = side_x ? bw.x : bw.z;
			float wt = bw.y;
			float sum = ws + wt;
			ws /= sum;
			wt /= sum;
			float which = smoothstep(0.42, 0.58, macro + (edge_n - 0.5) * 0.3);
			vec3 alb_a = vec3(0.0), arm_a = vec3(0.0), nor_s = vec3(0.0), nor_t = vec3(0.0);
			if (which < 0.99) {
				float k = 1.0 - which;
				alb_a += (texture(rock_albedo, uv_side).rgb * ws + texture(rock_albedo, uv_top).rgb * wt) * k;
				arm_a += (texture(rock_arm, uv_side).rgb * ws + texture(rock_arm, uv_top).rgb * wt) * k;
				nor_s += texture(rock_normal, uv_side).rgb * k;
				nor_t += texture(rock_normal, uv_top).rgb * k;
			}
			if (which > 0.01) {
				alb_a += (texture(rock2_albedo, uv_side).rgb * ws + texture(rock2_albedo, uv_top).rgb * wt) * which * 0.72;
				arm_a += (texture(rock2_arm, uv_side).rgb * ws + texture(rock2_arm, uv_top).rgb * wt) * which;
				nor_s += texture(rock2_normal, uv_side).rgb * which;
				nor_t += texture(rock2_normal, uv_top).rgb * which;
			}
			// Sedimentary banding across the cliffs.
			float strata = sin(world_pos.y * 0.42 + vnoise(world_pos.xz * 0.012) * 5.0) * 0.5 + 0.5;
			a_r = alb_a * mix(0.82, 1.1, strata) * vec3(1.02, 0.98, 0.93);
			m_r = arm_a;
			vec3 rs = nor_s * 2.0 - 1.0;
			vec3 rt = nor_t * 2.0 - 1.0;
			p_r = (side_x ? vec3(0.0, rs.y, rs.x) : vec3(rs.x, rs.y, 0.0)) * ws + vec3(rt.x, 0.0, -rt.y) * wt;
		}
		// Height-aware blending using albedo luminance as a height proxy.
		vec4 hgt = vec4(dot(a_g, vec3(0.33)), dot(a_s, vec3(0.33)), dot(a_v, vec3(0.33)), dot(a_r, vec3(0.33)))
				+ vec4(w_grass, w_sand, w_gravel, w_rock);
		float hf = dot(a_f, vec3(0.33)) + w_forest;
		float hmax = max(max(max(hgt.x, hgt.y), max(hgt.z, hgt.w)), hf) - 0.18;
		vec4 bwt = max(hgt - hmax, 0.0) * vec4(w_grass, w_sand, w_gravel, w_rock);
		float bwf = max(hf - hmax, 0.0) * w_forest;
		float bsum = max(bwt.x + bwt.y + bwt.z + bwt.w + bwf, 1e-4);
		bwt /= bsum;
		bwf /= bsum;
		alb = a_g * bwt.x + a_s * bwt.y + a_v * bwt.z + a_r * bwt.w + a_f * bwf;
		arm = m_g * bwt.x + m_s * bwt.y + m_v * bwt.z + m_r * bwt.w + m_f * bwf;
		vec3 tn = t_g * bwt.x + t_s * bwt.y + t_v * bwt.z + t_f * bwf;
		float fade = 1.0 - smoothstep(250.0, 700.0, dist);
		vec3 pert = vec3(tn.x, 0.0, -tn.y) * (1.0 - bwt.z * 0.6) + p_r * bwt.w;
		n = normalize(n_geo + pert * 0.9 * fade);
		float far_k = smoothstep(400.0, 700.0, dist);
		vec3 far_alb = meadow_color(dry) * w_grass + textureLod(sand_albedo, uv_s, 9.0).rgb * w_sand
				+ textureLod(gravel_albedo, uv_v, 9.0).rgb * 0.72 * w_gravel
				+ textureLod(rock_albedo, uv_g, 9.0).rgb * w_rock + textureLod(forest_albedo, uv_f, 9.0).rgb * 0.8 * w_forest;
		alb = mix(alb, far_alb, far_k);
	} else {
		vec2 uv = world_pos.xz / 4.6;
		alb = meadow_color(dry) * w_grass + textureLod(sand_albedo, uv, 9.0).rgb * w_sand
				+ textureLod(gravel_albedo, uv, 9.0).rgb * 0.72 * w_gravel + textureLod(rock_albedo, uv, 9.0).rgb * w_rock
				+ textureLod(forest_albedo, uv, 9.0).rgb * 0.8 * w_forest;
		arm = vec3(1.0, 0.85, 0.0);
	}

	// Macro variation: dry patches, lush hollows.
	alb *= mix(vec3(1.08, 1.02, 0.9), vec3(0.88, 0.95, 0.9), macro) * (1.0 + cavity * 0.25 * (1.0 - w_rock));
	// Trees too far for real shadows still darken the ground under them.
	alb *= mix(1.0, 0.5, eco.g * smoothstep(190.0, 320.0, dist));
	// Wet sand at the waterline.
	alb *= mix(0.62, 1.0, smoothstep(0.4, 2.2, h + (edge_n - 0.5)) + (1.0 - w_sand));

	// Rain: darker, glossier, puddles in hollows and on flat ground.
	float porous = 1.0 - w_rock * 0.5;
	float puddle = smoothstep(0.75, 0.95, vnoise(world_pos.xz * 0.15) * 0.8 + max(cavity, 0.0) * 3.0) * smoothstep(0.96, 0.995, n_geo.y) * smoothstep(0.5, 0.9, wetness);
	float wet = wetness * (0.6 + 0.4 * puddle);
	alb *= mix(1.0, 0.55, wet * porous);
	float rough = mix(arm.g, 0.08, wet * mix(0.5, 1.0, puddle));
	n = normalize(mix(n, n_geo, wetness * puddle));

	ALBEDO = alb;
	if (debug_mode == 1) { ALBEDO = vec3(w_grass, w_sand, w_rock); }
	if (debug_mode == 2) { ALBEDO = vec3(fract(h / 50.0), road, cavity + 0.5); }
	if (debug_mode == 3) { ALBEDO = n_geo * 0.5 + 0.5; }
	ROUGHNESS = rough;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Cloud shadow from the same density field as the visible clouds.
	cloud_light = dist < 2500.0 ? mix(0.12, 1.0, cloud_shadow_at(world_pos.xz * 0.001, sun_direction)) : 1.0;
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

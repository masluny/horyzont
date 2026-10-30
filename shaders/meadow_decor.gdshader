// Things standing in the meadow: scanned seed heads on tall stems and small
// flowers growing in drifts. Uses the same tile table as the grass.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;

#include "res://shaders/terrain_common.gdshaderinc"

uniform sampler2D eco_map : filter_linear, repeat_disable;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D patch_table : filter_nearest, repeat_disable;
uniform sampler2D seeds_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int lod_row = 0;
uniform float tile_size = 4.0;
uniform float fade_far = 62.0;

global uniform vec2 world_wind;
global uniform float wetness;

varying flat float v_kind;
varying vec3 v_col;
varying vec2 v_q;
varying vec3 v_normal;

void vertex() {
	vec4 cell = texelFetch(patch_table, ivec2(INSTANCE_ID, lod_row), 0);
	vec2 tile_id = floor(cell.xy / tile_size + 0.5);
	float turn = mod(tile_id.x * 3.0 + tile_id.y * 7.0 + floor(tile_id.x / 3.0) + floor(tile_id.y / 5.0), 4.0);
	vec2 q = CUSTOM0.xy;
	if (turn >= 2.0) {
		q = q.yx;
	}
	if (mod(turn, 2.0) >= 1.0) {
		q.x = tile_size - q.x;
	}
	vec2 root = cell.xy + q;
	float d = length(root - CAMERA_POSITION_WORLD.xz);
	vec2 tuv = (root + WORLD_SIZE * 0.5) / WORLD_SIZE;
	vec4 eco = textureLod(eco_map, tuv, 0.0);
	eco.r = smoothstep(0.1, 0.4, eco.r);
	float drift = textureLod(wind_noise, root * 0.0037 + COLOR.g * 0.37, 0.0).r;
	float kind = CUSTOM0.z;
	float species = floor(COLOR.g * 4.0);
	// Seed heads like dry ground; each flower species keeps to its own drifts.
	float want = kind < 0.5 ? mix(0.22, 1.0, eco.a) : smoothstep(0.5, 0.66, drift);
	float keep = step(COLOR.r, want * eco.r) * (1.0 - smoothstep(fade_far * 0.78, fade_far, d));
	vec3 local = VERTEX * keep * mix(0.75, 1.15, COLOR.a);
	float yaw = COLOR.b * 6.2831;
	vec3 cam_to = normalize(vec3(root.x, 0.0, root.y) - vec3(CAMERA_POSITION_WORLD.x, 0.0, CAMERA_POSITION_WORLD.z));
	vec2 across = normalize(mix(vec2(cos(yaw), sin(yaw)), vec2(-cam_to.z, cam_to.x), 0.6));
	vec3 placed = vec3(across.x * local.x, local.y, across.y * local.x) + vec3(-across.y * local.z, 0.0, across.x * local.z);
	vec2 wd = normalize(world_wind + vec2(1e-3));
	float ws = clamp(length(world_wind) / 12.0, 0.2, 1.8);
	float gust = textureLod(wind_noise, root * 0.011 - wd * TIME * 0.11, 0.0).r;
	float sway = ((gust * 0.8 - 0.1) * ws + sin(TIME * 2.3 + COLOR.b * 30.0) * 0.08) * local.y * local.y * 0.75;
	placed.xz += wd * sway;
	placed.y -= sway * sway * 0.3 * local.y;
	VERTEX = vec3(root.x, terrain_height(root) - 0.03, root.y) + placed;
	v_kind = kind;
	v_q = UV2;
	vec3 ground_n = normalize(vec3(cell.z, sqrt(max(0.05, 1.0 - dot(cell.zw, cell.zw))), cell.w));
	v_normal = normalize(ground_n + vec3(-cam_to.x, 0.0, -cam_to.z) * 0.3);
	if (kind > 1.5) {
		v_col = vec3(0.05, 0.11, 0.025);
	} else if (kind > 0.5) {
		vec3 p0 = vec3(0.82, 0.62, 0.05);
		vec3 p1 = vec3(0.85, 0.85, 0.8);
		vec3 p2 = vec3(0.36, 0.14, 0.52);
		vec3 p3 = vec3(0.7, 0.07, 0.04);
		v_col = species < 1.0 ? p0 : (species < 2.0 ? p1 : (species < 3.0 ? p2 : p3));
	} else {
		v_col = mix(vec3(1.0), vec3(0.72, 0.78, 0.5), COLOR.g);
	}
}

void fragment() {
	vec3 c = v_col;
	float a = 1.0;
	if (v_kind < 0.5) {
		vec4 t = texture(seeds_albedo, UV);
		c *= t.rgb * 0.62;
		a = t.a;
	} else if (v_kind < 1.5) {
		float r = length(v_q);
		float ang = atan(v_q.y, v_q.x);
		float petal = 0.68 + 0.32 * cos(ang * 7.0);
		a = step(r, petal);
		c = mix(vec3(0.75, 0.5, 0.05), c, smoothstep(0.16, 0.26, r));
		c *= mix(0.72, 1.0, smoothstep(0.1, 0.6, r));
	}
	ALBEDO = c * mix(1.0, 0.7, wetness);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.6;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.5) / 1.5, 0.0, 1.0);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.6);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrap + through * 0.9) / PI;
}

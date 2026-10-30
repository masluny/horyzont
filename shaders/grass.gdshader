// Meadow blades. Each instance is one tile of pre-placed blades; the tile origin
// comes from a table texture (see GrassField). Colour follows the eco map, so
// the far grass melts into the terrain, and backlit blades glow at low sun.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/terrain_common.gdshaderinc"
#include "res://shaders/cloud_shadow.gdshaderinc"

uniform sampler2D eco_map : filter_linear, repeat_disable;
uniform sampler2D wind_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D patch_table : filter_nearest, repeat_disable;
uniform int lod_row = 0;
uniform float tile_size = 4.0;
uniform float near_radius = 24.0;
uniform float mid_radius = 68.0;
uniform float far_radius = 170.0;

global uniform vec2 world_wind;
global uniform float wetness;
global uniform vec3 sun_direction;

varying float tip;
varying float side_u;
varying vec3 base_col;
varying vec3 v_normal;
varying float v_cloud;

// Fraction of blades alive at a distance; the survivors widen to compensate.
float blade_density(float d) {
	float a = 1.0 - 0.8 * smoothstep(near_radius * 0.5, mid_radius, d);
	return a * (1.0 - 0.72 * smoothstep(mid_radius, far_radius, d));
}

void vertex() {
	vec4 cell = texelFetch(patch_table, ivec2(INSTANCE_ID, lod_row), 0);
	// Each tile is turned or mirrored by its position so the layout never lines up.
	vec2 tile_id = floor(cell.xy / tile_size + 0.5);
	float turn = mod(tile_id.x * 3.0 + tile_id.y * 7.0 + floor(tile_id.x / 3.0) + floor(tile_id.y / 5.0), 4.0);
	vec2 q = VERTEX.xz;
	if (turn >= 2.0) {
		q = q.yx;
	}
	if (mod(turn, 2.0) >= 1.0) {
		q.x = tile_size - q.x;
	}
	vec2 root = cell.xy + q;
	float t = VERTEX.y;
	float rank = UV.y;
	float side = UV.x;
	float d = length(root - CAMERA_POSITION_WORLD.xz);

	vec2 tuv = (root + WORLD_SIZE * 0.5) / WORLD_SIZE;
	vec4 eco = textureLod(eco_map, tuv, 0.0);
	eco.r = smoothstep(0.04, 0.3, eco.r);
	float dens = blade_density(d);
	float keep = smoothstep(0.0, 0.05, eco.r * dens - rank);
	keep *= 1.0 - smoothstep(far_radius * 0.82, far_radius, d);

	float patchy = textureLod(wind_noise, root * 0.0041, 0.0).r;
	float r_h = COLOR.r;
	float tuft = textureLod(wind_noise, root * 0.027, 0.0).r;
	float height = mix(0.16, 0.78, r_h * r_h) * (0.32 + 1.3 * patchy * patchy + 0.55 * tuft) * mix(0.75, 1.1, eco.r) * keep;
	float widen = sqrt(1.0 / max(dens, 0.05));
	float width = mix(0.009, 0.017, COLOR.g) * widen * keep;

	float yaw = COLOR.b * 6.2831;
	vec2 facing = vec2(cos(yaw), sin(yaw));
	vec3 cam_to = normalize(vec3(root.x, 0.0, root.y) - vec3(CAMERA_POSITION_WORLD.x, 0.0, CAMERA_POSITION_WORLD.z));
	// Blades turn a little towards the viewer so they never go edge-on.
	vec2 across = normalize(mix(vec2(-facing.y, facing.x), vec2(-cam_to.z, cam_to.x), 0.55));

	float lean = mix(0.12, 0.62, COLOR.a);
	vec2 wd = normalize(world_wind + vec2(1e-3));
	float ws = clamp(length(world_wind) / 12.0, 0.2, 1.8);
	float gust = textureLod(wind_noise, root * 0.011 - wd * TIME * 0.11, 0.0).r;
	float sway = (gust * 0.85 - 0.12) * ws + sin(TIME * 2.7 + COLOR.r * 40.0) * 0.05;
	vec2 bend = facing * lean + wd * sway;
	float t2 = t * t;
	vec3 local = vec3(bend.x * t2 * height, t * height * (1.0 - 0.32 * dot(bend, bend) * t), bend.y * t2 * height);
	float taper = 1.0 - t2 * 0.72;
	local.xz += across * side * width * taper;

	float h = terrain_height(root);
	VERTEX = vec3(root.x, h - 0.04, root.y) + local;

	vec3 ground_n = normalize(vec3(cell.z, sqrt(max(0.05, 1.0 - dot(cell.zw, cell.zw))), cell.w));
	vec3 blade_n = normalize(vec3(-bend.x, 1.0, -bend.y) + vec3(across.y, 0.0, -across.x) * (0.8 + side * 0.5));
	float toward_ground = mix(0.45, 0.9, smoothstep(6.0, mid_radius, d));
	v_normal = normalize(mix(blade_n, ground_n, toward_ground));

	v_cloud = cloud_shadow(root);
	tip = t;
	side_u = side;
	float dry = clamp(eco.a * 0.95 + (COLOR.g - 0.5) * 0.42 + (patchy - 0.5) * 0.6 + (tuft - 0.5) * 0.5, 0.0, 1.0);
	vec3 lush = mix(vec3(0.03, 0.095, 0.02), vec3(0.058, 0.125, 0.024), COLOR.b);
	vec3 straw = mix(vec3(0.115, 0.125, 0.04), vec3(0.25, 0.205, 0.09), COLOR.a);
	base_col = mix(lush, straw, dry * dry * 0.85) * mix(0.72, 1.2, COLOR.r);
}

void fragment() {
	float rib = 1.0 - 0.22 * exp(-side_u * side_u * 22.0);
	float root_shade = mix(0.32, 1.0, smoothstep(0.0, 0.62, tip));
	vec3 c = base_col * mix(vec3(0.82), vec3(1.42, 1.38, 0.95), tip) * rib * root_shade;
	ALBEDO = c * mix(1.0, 0.68, wetness);
	ROUGHNESS = mix(0.52, 0.28, wetness);
	SPECULAR = 0.36;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	AO = mix(0.5, 1.0, tip);
	AO_LIGHT_AFFECT = 0.35;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.4) / 1.4, 0.0, 1.0);
	// Light through the blade when looking towards the sun.
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.6) * smoothstep(0.1, 0.7, tip);
	float shadow = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? v_cloud : 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow * (wrap + through * vec3(1.0, 1.25, 0.5)) / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	SPECULAR_LIGHT += LIGHT_COLOR * shadow * pow(ndh, 24.0) * 0.1 * (1.0 - ROUGHNESS);
}

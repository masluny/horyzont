// Grass blades placed procedurally around the camera: every instance maps to a
// world-space grid cell (stable as the field recentres), height from the
// terrain heightmap, culled on roads, sand and rock. Backlit tips glow.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/terrain_common.gdshaderinc"

uniform sampler2D normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D maskmap : filter_linear_mipmap, repeat_disable;
uniform vec2 field_center;
uniform float cell = 0.42;
uniform int side = 220;
uniform float radius = 42.0;

global uniform vec2 world_wind;
global uniform vec3 sun_direction;
global uniform float wetness;

varying float tip;
varying vec3 base_col;
varying float glow;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	int id = INSTANCE_ID;
	vec2 g = vec2(float(id % side), float(id / side)) - float(side) * 0.5;
	vec2 cell_id = floor(field_center / cell) + g;
	vec2 jit = vec2(hash12(cell_id), hash12(cell_id + 17.3)) - 0.5;
	vec2 wxz = (cell_id + 0.5 + jit * 0.9) * cell;
	float d = length(wxz - CAMERA_POSITION_WORLD.xz);

	vec2 tuv = (wxz + WORLD_SIZE * 0.5) / WORLD_SIZE;
	vec4 nm = textureLod(normalmap, tuv, 0.0);
	vec2 nxz = nm.rg * 2.0 - 1.0;
	float ny = sqrt(max(0.0, 1.0 - dot(nxz, nxz)));
	float road = textureLod(maskmap, tuv, 0.0).r;
	float h = terrain_height(wxz);
	float macro = vnoise(wxz * 0.004) * 0.6 + vnoise(wxz * 0.017) * 0.4;
	float patchy = vnoise(wxz * 0.11 + 3.0);
	// Density: none on roads, beaches, steep rock; thinning with distance.
	float dens = smoothstep(0.6, 0.78, ny) * (1.0 - smoothstep(0.02, 0.2, road)) * smoothstep(5.0, 8.0, h);
	dens *= smoothstep(0.05, 0.3, patchy + 0.4);
	float keep = step(hash12(cell_id + 5.1), dens) * (1.0 - smoothstep(radius * 0.6, radius, d + hash12(cell_id + 8.0) * 6.0));
	float r = hash12(cell_id + 9.7);
	float height = mix(0.32, 0.85, r * r) * (0.6 + 0.6 * patchy) * keep;
	float width = mix(0.045, 0.075, hash12(cell_id + 2.2));
	float yaw = hash12(cell_id + 4.4) * 6.2831;

	tip = UV.y;
	// COLOR: rg = blade offset in the clump, b = height factor, a = yaw offset.
	float by = yaw + COLOR.a * 6.2831;
	vec3 local = vec3(VERTEX.x * width * (1.0 - tip * 0.85), VERTEX.y * height * COLOR.b, 0.0);
	local.xz = mat2(vec2(cos(by), sin(by)), vec2(-sin(by), cos(by))) * local.xz;
	local.xz += (COLOR.rg - 0.5) * cell * 1.1 * keep;
	// Wind: gusts travelling across the field plus a little per-blade flutter.
	vec2 wd = normalize(world_wind + vec2(1e-3));
	float ws = clamp(length(world_wind) / 12.0, 0.2, 1.8);
	float gust = vnoise(wxz * 0.08 - wd * TIME * 1.6) * 0.8 + 0.2;
	float bend = (gust * 0.55 * ws + sin(TIME * 3.3 + r * 20.0) * 0.06) * tip * tip;
	local.xz += wd * bend * height;
	local.y -= bend * bend * height * 0.35;
	VERTEX = vec3(wxz.x, h - 0.03, wxz.y) + local;
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), vec3(-sin(yaw), 0.0, cos(yaw)), 0.25));

	float dry = clamp(macro * 1.2 - 0.25 + (nm.a - 0.5) * 0.8, 0.0, 1.0);
	base_col = mix(vec3(0.055, 0.16, 0.025), vec3(0.16, 0.18, 0.05), dry) * mix(0.8, 1.15, r);
	// Translucency toward a low sun behind the blade.
	vec3 v = normalize(CAMERA_POSITION_WORLD - VERTEX);
	glow = pow(clamp(dot(-v, sun_direction), 0.0, 1.0), 6.0) * clamp(sun_direction.y * 6.0 + 0.4, 0.0, 1.0);
}

void fragment() {
	vec3 c = mix(base_col * 0.7, base_col * vec3(1.5, 1.45, 0.9), tip);
	ALBEDO = c * mix(1.0, 0.65, wetness);
	ROUGHNESS = mix(0.7, 0.3, wetness);
	BACKLIGHT = vec3(0.35, 0.45, 0.12) * tip;
	EMISSION = vec3(0.6, 0.55, 0.15) * glow * tip * tip * 0.0;
	AO = mix(0.55, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
}

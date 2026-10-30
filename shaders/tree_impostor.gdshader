// Far trees: camera-facing quads showing a baked view of the tree from eight
// directions. Baked normals keep the sun and sky lighting right.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;

#include "res://shaders/cloud_shadow.gdshaderinc"

uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_normal : filter_linear_mipmap, repeat_disable;
uniform float rows = 12.0;
uniform float views = 8.0;
uniform vec2 atlas_size = vec2(2048.0, 3072.0);
uniform float fade_near = 215.0;
uniform float fade_far = 240.0;

global uniform float dither_jitter;

varying float v_view;
varying float v_row;
varying float v_fade;
varying vec3 v_right;
varying vec3 v_back;
varying float v_hue;
varying float v_cloud;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	float d = length(to_cam);
	to_cam /= max(d, 1e-3);
	vec3 right = vec3(to_cam.z, 0.0, -to_cam.x);
	float az = atan(to_cam.x, to_cam.z) - INSTANCE_CUSTOM.z;
	v_view = fract(az / 6.28318) * views;
	v_row = INSTANCE_CUSTOM.y;
	v_right = right;
	v_back = to_cam;
	v_hue = INSTANCE_CUSTOM.w;
	v_cloud = cloud_shadow(origin.xz);
	v_fade = smoothstep(fade_near, fade_far, d);
	float size = INSTANCE_CUSTOM.x;
	VERTEX = right * (UV.x - 0.5) * size + vec3(0.0, (1.0 - UV.y) * size, 0.0);
	if (d < fade_near - 1.0) {
		VERTEX = vec3(0.0 / 0.0);
	}
	NORMAL = to_cam;
}

void fragment() {
	vec2 q = FRAGCOORD.xy + dither_jitter * vec2(5.588, 2.113);
	float ign = fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
	if (v_fade < ign) {
		discard;
	}
	float view = floor(v_view + ign);
	view = mod(view, views);
	vec2 uv = (vec2(view, v_row) + UV) / vec2(views, rows);
	// Past a few mips one texel would cover the whole tree and the quad turns solid.
	vec2 dx = dFdx(uv) * atlas_size;
	vec2 dy = dFdy(uv) * atlas_size;
	float lod = min(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0)), 3.0);
	vec4 a = textureLod(atlas_albedo, uv, lod);
	vec3 n = textureLod(atlas_normal, uv, lod).xyz * 2.0 - 1.0;
	vec3 wn = v_right * n.x + vec3(0.0, 1.0, 0.0) * n.y + v_back * n.z;
	ALBEDO = a.rgb * mix(0.86, 1.1, v_hue);
	ALPHA = a.a * (1.0 + lod * 0.14);
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.6;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float front = clamp((ndl + 0.32) / 1.32, 0.0, 1.0);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.4);
	float shadow = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? v_cloud : 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow * (front + vec3(1.1, 1.35, 0.42) * through * 0.7) / PI;
}

// Leaf-spray cards. Normals are bent to the crown shape so the canopy shades as a
// soft volume; the scan's normal map adds leaf detail close up.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx, depth_draw_opaque;

#include "res://shaders/tree_common.gdshaderinc"

uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec3 tint_a = vec3(0.8, 0.95, 0.62);
uniform vec3 tint_b = vec3(0.62, 0.78, 0.44);

global uniform float wetness;

varying vec3 v_n;
varying vec3 v_col;
varying float v_ao;

varying float v_fade;

void vertex() {
	vec3 t = TANGENT;
	v_fade = tree_place(INSTANCE_ID, VERTEX, NORMAL, t, COLOR.a, UV2.x, UV2.y, CAMERA_POSITION_WORLD);
	TANGENT = t;
	v_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = mix(tint_a, tint_b, COLOR.g) * COLOR.r;
	v_ao = COLOR.r;
}

void fragment() {
	tree_dither(FRAGCOORD.xy, v_fade);
	vec4 a = texture(leaf_albedo, UV);
	vec3 nm = texture(leaf_normal, UV).xyz * 2.0 - 1.0;
	ALBEDO = a.rgb * v_col * mix(1.0, 0.72, wetness);
	ALPHA = tree_alpha(a.a, UV, 2048.0);
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	NORMAL = normalize(v_n + (TANGENT * nm.x + BINORMAL * nm.y) * 0.55);
	ROUGHNESS = mix(0.46, 0.25, wetness);
	SPECULAR = 0.38;
	AO = clamp(v_ao + 0.35, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.2;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float front = clamp((ndl + 0.32) / 1.32, 0.0, 1.0);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.4);
	vec3 trans = vec3(1.1, 1.35, 0.42) * through * 0.85 * v_ao;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (front + trans) / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(ndh, 28.0) * 0.12;
}

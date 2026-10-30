// Trunks and branches.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/tree_common.gdshaderinc"

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_arm : filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float wetness;

varying float v_moss;

varying float v_fade;

void vertex() {
	vec3 t = TANGENT;
	v_fade = tree_place(INSTANCE_ID, VERTEX, NORMAL, t, COLOR.a, UV2.x, 0.0, CAMERA_POSITION_WORLD);
	TANGENT = t;
	v_moss = clamp(NORMAL.y * 0.6 + 0.2 - VERTEX.y * 0.0, 0.0, 1.0);
}

void fragment() {
	tree_dither(FRAGCOORD.xy, v_fade);
	vec3 arm = texture(bark_arm, UV).rgb;
	vec3 c = texture(bark_albedo, UV).rgb;
	c = mix(c, c * vec3(0.5, 0.72, 0.36), v_moss * 0.7);
	ALBEDO = c * mix(1.0, 0.55, wetness);
	NORMAL_MAP = texture(bark_normal, UV).xyz;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = mix(arm.g, 0.3, wetness);
	AO = arm.r;
	SPECULAR = 0.3;
}

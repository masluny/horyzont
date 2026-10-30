// Renders scanned leaves for the foliage atlases. mode 0 = albedo, 1 = normal.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_opaque;

uniform sampler2D leaf_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_opacity : filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform int mode = 0;

varying vec3 v_t;
varying vec3 v_b;
varying vec3 v_n;

void vertex() {
	v_n = NORMAL;
	v_t = TANGENT;
	v_b = BINORMAL;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec3 n = normalize(v_n);
	if (UV.x >= 0.0) {
		if (texture(leaf_opacity, UV).r < 0.5) {
			discard;
		}
		col *= texture(leaf_color, UV).rgb;
		vec3 t = texture(leaf_normal, UV).rgb * 2.0 - 1.0;
		n = normalize(normalize(v_t) * t.x + normalize(v_b) * t.y + n * t.z);
	}
	n = n.z < 0.0 ? -n : n;
	if (mode == 0) {
		ALBEDO = col * COLOR.a;
	} else {
		// The viewport encodes to sRGB on output, so undo that to store raw values.
		ALBEDO = srgb_to_linear(n * 0.5 + 0.5);
	}
}

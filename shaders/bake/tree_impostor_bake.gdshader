// Writes a tree into the impostor atlas. mode 0 = colour, 1 = view-space normal.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform int mode = 0;
uniform bool leaf = true;

varying vec3 v_n;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void vertex() {
	v_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV, -1.0);
	if (leaf && a.a < 0.2) {
		discard;
	}
	vec3 n = normalize(v_n);
	if (mode == 0) {
		ALBEDO = a.rgb * (leaf ? tint * COLOR.r : vec3(0.8));
	} else {
		ALBEDO = srgb_to_linear(n * 0.5 + 0.5);
	}
}

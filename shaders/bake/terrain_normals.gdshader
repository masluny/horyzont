// Terrain normals + shading masks from the heightmap.
// R,G: normal.xz * 0.5 + 0.5, B: small-scale cavity, A: large-scale ridge/valley.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform float texel = 5.0;

float h(ivec2 p) {
	ivec2 s = textureSize(heightmap, 0);
	return texelFetch(heightmap, clamp(p, ivec2(0), s - 1), 0).r;
}

void fragment() {
	ivec2 p = ivec2(floor(FRAGCOORD.xy));
	float hl = h(p + ivec2(-1, 0));
	float hr = h(p + ivec2(1, 0));
	float hd = h(p + ivec2(0, -1));
	float hu = h(p + ivec2(0, 1));
	float hc = h(p);
	vec3 n = normalize(vec3(hl - hr, 2.0 * texel, hd - hu));
	float lap = (hl + hr + hd + hu) * 0.25 - hc;
	float wide = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		wide += h(p + ivec2(round(vec2(cos(a), sin(a)) * 9.0)));
	}
	wide = wide / 8.0 - hc;
	COLOR = vec4(n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, clamp(lap * 0.25 + 0.5, 0.0, 1.0), clamp(wide * 0.02 + 0.5, 0.0, 1.0));
}

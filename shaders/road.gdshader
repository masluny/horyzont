// Asphalt road with painted markings, gravel shoulders and rain wetness.
// UV.x = lateral offset in metres (0 = centre), UV.y = distance along road.
shader_type spatial;
render_mode cull_back;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_width = 3.6;

global uniform float wetness;

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

void fragment() {
	float x = UV.x;
	float ax = abs(x);
	float y = UV.y;
	vec2 tuv = vec2(x, y) / 4.2;
	vec3 alb = texture(asphalt_albedo, tuv).rgb * 0.74;
	float macro_tar = vnoise(vec2(x * 0.3, y * 0.04)) * 0.6 + vnoise(vec2(x * 1.3, y * 0.21)) * 0.4;
	alb *= mix(0.84, 1.12, macro_tar);
	vec3 arm = texture(asphalt_arm, tuv).rgb;
	vec3 tn = texture(asphalt_normal, tuv).rgb * 2.0 - 1.0;
	float wear = vnoise(vec2(x * 0.8, y * 0.05));
	// Tyre tracks are slightly polished and darker.
	float track = exp(-pow((ax - half_width * 0.5) / 0.55, 2.0));
	alb *= 1.0 - track * 0.12;
	float rough = mix(arm.g, arm.g * 0.75, track);

	// Markings: dashed centre line and solid edge lines.
	float paint = 0.0;
	float centre = (1.0 - smoothstep(0.06, 0.08, ax)) * step(fract(y / 12.0), 0.45);
	float edge = 1.0 - smoothstep(0.07, 0.09, abs(ax - (half_width - 0.3)));
	paint = max(centre, edge) * (0.65 + 0.35 * smoothstep(0.3, 0.7, vnoise(vec2(x * 4.0, y * 0.7))));
	alb = mix(alb, vec3(0.82, 0.82, 0.78), paint);
	rough = mix(rough, 0.55, paint);

	// Shoulders.
	float ragged = (vnoise(vec2(y * 0.55, sign(x) * 3.0)) - 0.5) * 0.34 + (vnoise(vec2(y * 2.7, sign(x) * 9.0)) - 0.5) * 0.14;
	float shoulder = smoothstep(half_width - 0.02, half_width + 0.1, ax + ragged);
	vec3 galb = texture(gravel_albedo, vec2(x, y) / 2.3).rgb;
	vec3 gn = (texture(gravel_normal, vec2(x, y) / 2.3).rgb * 2.0 - 1.0) * vec3(0.5, 0.5, 1.0);
	vec3 gcol = mix(galb, vec3(dot(galb, vec3(0.33))), 0.68) * 0.72;
	// Outer shoulder: soil and a green tint where the verge takes over.
	float verge = smoothstep(half_width + 0.5, half_width + 1.6, ax + ragged * 1.8 + vnoise(vec2(x * 2.0, y * 0.9)) * 0.4);
	gcol = mix(gcol, galb * vec3(0.26, 0.28, 0.14), verge);
	alb = mix(alb, gcol, shoulder);
	tn = mix(tn, gn, shoulder);
	rough = mix(rough, 0.9, shoulder);

	// Rain: puddles collect along the edges and in worn patches.
	float puddle = smoothstep(0.5, 0.75, vnoise(vec2(x * 0.7, y * 0.12)) + smoothstep(1.5, 3.4, ax) * 0.25 + wear * 0.2);
	float wet = wetness * mix(0.75, 1.0, puddle);
	alb *= mix(1.0, 0.5, wet * (1.0 - paint * 0.5));
	rough = mix(rough, mix(0.22, 0.04, puddle), wet);
	tn = mix(tn, vec3(0.0, 0.0, 1.0), wet * puddle);

	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = arm.r;
	SPECULAR = 0.5;
	NORMAL_MAP = tn * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}

shader_type canvas_item;

// Frosted panel. Rounded in the shader so it survives the screen-texture pass.
// Radius matches StyleBoxFlat (14, scaled from script).
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 5.0) = 2.15;
uniform vec4 tint : source_color = vec4(0.05, 0.06, 0.08, 0.55);
uniform float radius = 14.0;

void fragment() {
	vec2 size = 1.0 / max(fwidth(UV), vec2(0.00001));
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(0.0, max(fwidth(d), 0.75), d);

	vec3 blurred = textureLod(screen_texture, SCREEN_UV, lod).rgb;
	float luma = dot(blurred, vec3(0.2126, 0.7152, 0.0722));
	blurred = mix(vec3(luma), blurred, 0.8);
	COLOR = vec4(mix(blurred, tint.rgb, tint.a), mask);
}

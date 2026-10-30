// Contrast-adaptive sharpening after the upscaler (AMD CAS, simplified): pulls
// fine detail back without ringing on hard edges.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float amount = 0.55;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 n = texture(screen, SCREEN_UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen, SCREEN_UV + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen, SCREEN_UV + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
	vec3 lo = min(c, min(min(n, s), min(e, w)));
	vec3 hi = max(c, max(max(n, s), max(e, w)));
	vec3 k = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-4)), 0.0, 1.0));
	vec3 weight = k * -mix(0.125, 0.2, amount);
	vec3 col = (c + (n + s + e + w) * weight) / (1.0 + 4.0 * weight);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}

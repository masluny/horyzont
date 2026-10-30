shader_type canvas_item;

// Soft dark wash. The rect covers the left half; the falloff lands near the left third.
void fragment() {
	float t = smoothstep(0.02, 1.0, UV.x);
	float a = pow(1.0 - t, 1.2) * 0.82;
	COLOR = vec4(0.015, 0.02, 0.03, a);
}

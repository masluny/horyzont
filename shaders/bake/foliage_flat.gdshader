// Colour scan + opacity scan into one RGBA image.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D color_tex : filter_linear;
uniform sampler2D opacity_tex : filter_linear;

void fragment() {
	COLOR = vec4(texture(color_tex, UV).rgb, texture(opacity_tex, UV).r);
}

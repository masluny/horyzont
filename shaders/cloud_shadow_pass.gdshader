// Sunlight reaching the ground through the cumulus layer, in a square around the
// camera. Every material reads this instead of marching the clouds itself.
shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/atmosphere.gdshaderinc"
#include "res://shaders/clouds.gdshaderinc"

uniform vec2 center_km = vec2(0.0);
uniform float extent_km = 8.0;

void fragment() {
	vec2 xz = center_km + (UV - 0.5) * extent_km;
	COLOR = vec4(vec3(cloud_shadow_at(xz, sun_direction)), 1.0);
}

// Environment sky: feeds ambient light and reflections (radiance cubemap).
shader_type sky;

#include "res://shaders/sky_common.gdshaderinc"

void sky() {
	// TIME keeps the radiance map updating as the globals change.
	COLOR = render_sky(EYEDIR, POSITION, 0.5, 0.002, 0) + vec3(TIME * 1e-12);
}

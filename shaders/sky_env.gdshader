// Environment sky: feeds ambient light and reflections (radiance cubemap).
shader_type sky;

#include "res://shaders/sky_common.gdshaderinc"

// Poked from SkySystem so the radiance map follows the globals.
uniform float env_tick = 0.0;

void sky() {
	COLOR = render_sky(EYEDIR, POSITION, 0.5, 0.002, 0) + vec3(env_tick * 1e-12);
}

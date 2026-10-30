extends Node3D
## Builds the world: environment, sky, clock, weather, lights and the island.

var env: Environment
var attributes: CameraAttributesPractical
var sky: SkySystem
var clock: TimeOfDay
var weather: Weather
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var camera: Camera3D


func _ready() -> void:
	Game.world = self
	_build_environment()
	sky = SkySystem.new(env)
	sky.name = "Sky"
	add_child(sky)
	weather = Weather.new()
	weather.name = "Weather"
	weather.env = env
	add_child(weather)
	clock = TimeOfDay.new()
	clock.name = "Clock"
	weather.clock = clock
	add_child(clock)
	sun = _make_light("Sun", true)
	moon = _make_light("Moon", false)
	clock.setup(env, attributes, sun, moon, weather, sky)
	Game.sky = sky
	Game.clock = clock
	Game.weather = weather

	camera = Camera3D.new()
	camera.name = "DevCamera"
	camera.far = 40000.0
	camera.near = 0.1
	camera.fov = 62.0
	add_child(camera)
	camera.global_position = Game.vec3_arg("cam", Vector3(0, 3, 0))
	camera.look_at(Game.vec3_arg("look", Vector3(-100, 8, 0)))
	camera.make_current()

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	ocean.mesh = plane
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.01, 0.025, 0.035)
	om.roughness = 0.08
	om.metallic_specular = 0.5
	ocean.material_override = om
	add_child(ocean)

	if Game.args.has("time"):
		clock.time = float(Game.arg("time"))
	if Game.args.has("weather"):
		weather.set_preset(Game.arg("weather"), true)
	if Game.args.has("shots"):
		var runner := ShotRunner.new()
		runner.camera = camera
		add_child(runner)
		runner.run(Game.arg("shots"))


func _build_environment() -> void:
	env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.4
	env.glow_hdr_luminance_cap = 10.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0001
	env.fog_aerial_perspective = 0.85
	env.fog_sky_affect = 0.0
	env.fog_height = 25.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.02
	attributes = CameraAttributesPractical.new()
	attributes.auto_exposure_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	we.camera_attributes = attributes
	add_child(we)


func _make_light(light_name: String, shadows: bool) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = light_name
	l.shadow_enabled = shadows
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	l.directional_shadow_max_distance = 450.0
	l.shadow_blur = 1.2
	l.light_angular_distance = 0.6
	add_child(l)
	return l

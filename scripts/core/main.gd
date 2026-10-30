extends Node3D
## Builds the world: environment, sky, clock, weather, lights and the island.

var env: Environment
var attributes: CameraAttributesPractical
var sky: SkySystem
var clock: TimeOfDay
var weather: Weather
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var camera: CameraRig
var car: Car
var cinema := false
var terrain: TerrainData
var road: RoadBuilder


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

	camera = CameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	camera.global_position = Game.vec3_arg("cam", Vector3(0, 3, 0))
	camera.look_at(Game.vec3_arg("look", Vector3(-100, 8, 0)))
	camera.make_current()


	if Game.args.has("stats"):
		add_child(load("res://dev/terrain_stats.gd").new())
	terrain = TerrainData.new()
	terrain.name = "TerrainData"
	add_child(terrain)
	Game.terrain = terrain
	await terrain.generate()
	var tr := TerrainRenderer.new()
	tr.name = "Terrain"
	add_child(tr)
	tr.setup(terrain, sky)
	var water := WaterRenderer.new()
	water.name = "Water"
	add_child(water)
	water.setup(terrain, sky)
	_build_terrain_collision()
	road = RoadBuilder.new()
	road.name = "Road"
	add_child(road)
	road.build(terrain, sky)
	car = Car.new()
	car.name = "Car"
	car.terrain = terrain
	add_child(car)
	car.place_on_road(terrain.nearest_road_index(Vector3(-3200, 0, 600)))
	camera.target = car
	camera.terrain = terrain
	camera.snap()
	if Game.args.has("cinema"):
		set_cinema(true)

	if Game.args.has("time"):
		clock.time = float(Game.arg("time"))
	if Game.args.has("weather"):
		weather.set_preset(Game.arg("weather"), true)
	if Game.args.has("shots"):
		var runner := ShotRunner.new()
		runner.camera = camera
		add_child(runner)
		runner.run(Game.arg("shots"))


func set_cinema(on: bool) -> void:
	cinema = on
	car.autopilot = on
	camera.set_mode(CameraRig.Mode.CINEMATIC if on else CameraRig.Mode.CHASE)
	camera.snap()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_C:
				if not cinema:
					camera.cycle_mode()
			KEY_K:
				set_cinema(not cinema)
			KEY_T:
				clock.time_scale = 12.0 if clock.time_scale > 12.0 else 240.0
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_terrain_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = TerrainData.SIZE
	shape.map_depth = TerrainData.SIZE
	shape.map_data = terrain.heights
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface", "terrain")
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(TerrainData.TEXEL, 1.0, TerrainData.TEXEL)
	body.add_child(cs)
	add_child(body)


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

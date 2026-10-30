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
var ui: UIRoot
var postcards: Postcards
var photo_mode := false
var quality := "wysoka"
var ambient: AmbientAudio
var _sea_timer := 0.0
var _ssr_timer := 0.0
var _scale_before_photo := 0.58
var terrain: TerrainData
var road: RoadBuilder
var grass: GrassField
var forest: Forest
var sharpen: ColorRect


func _ready() -> void:
	if Game.args.has("bake_foliage"):
		var baker := FoliageBaker.new()
		add_child(baker)
		baker.run()
		return
	if Game.args.has("bake_models"):
		var model_baker := ModelBaker.new()
		add_child(model_baker)
		model_baker.run()
		return
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


	if Game.args.has("drive_test"):
		add_child(load("res://dev/drive_test.gd").new())
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
	grass = GrassField.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(terrain)
	var rain := Rain.new()
	rain.name = "Rain"
	add_child(rain)
	_build_terrain_collision()
	road = RoadBuilder.new()
	road.name = "Road"
	add_child(road)
	road.build(terrain, sky)
	var props := Props.new()
	props.name = "Props"
	add_child(props)
	props.build(terrain, sky)
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	await forest.build(terrain, props.tree_spots)
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
	_build_sharpen()
	var headless_run := Game.args.has("shots") or Game.args.has("bench")
	if not headless_run:
		ui = UIRoot.new()
		ui.name = "UI"
		add_child(ui)
		ui.drive_requested.connect(_start_drive)
		ui.cinema_requested.connect(func(): set_cinema(true); _release_mouse())
		ui.main_menu_requested.connect(_to_menu)
		ui.photo_overlay.closed.connect(func(): if photo_mode: toggle_photo_mode())
		postcards = Postcards.new()
		postcards.name = "Postcards"
		add_child(postcards)
		postcards.setup(terrain, ui)
		ambient = AmbientAudio.new()
		ambient.name = "Ambient"
		add_child(ambient)
		_to_menu()
		if Game.args.has("ui_shot"):
			_ui_shot(Game.arg("ui_shot"))

	if Game.args.has("time"):
		clock.time = float(Game.arg("time"))
	if Game.args.has("weather"):
		weather.set_preset(Game.arg("weather"), true)
	if Game.args.has("perf_off"):
		var off: PackedStringArray = Game.arg("perf_off").split(",")
		_apply_perf_off.call_deferred(off, water, tr)
	if Game.args.has("bench"):
		var bench := BenchRunner.new()
		add_child(bench)
		bench.run(float(Game.arg("bench")))
	if Game.args.has("shots"):
		var runner := ShotRunner.new()
		runner.camera = camera
		add_child(runner)
		runner.run(Game.arg("shots"))


func _apply_perf_off(what: PackedStringArray, water: Node3D, tr: Node3D) -> void:
	for w in what:
		match w:
			"ssr": env.ssr_enabled = false
			"ssao": env.ssao_enabled = false
			"glow": env.glow_enabled = false
			"shadow": sun.shadow_enabled = false; sun.set_meta("force_no_shadow", true)
			"water": water.visible = false
			"terrain": tr.visible = false
			"dome": sky.dome.visible = false
			"envsky": env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
			"clouds": sky.set_sky_debug(2)
			"scale50": get_viewport().scaling_3d_scale = 0.5
			"grass": grass.visible = false
			"trees": forest.visible = false
			"split2": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			"split1": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			"fsr2": get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			"fsr1": get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			"mfxs": get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
			"bilinear": get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			"taa": get_viewport().use_taa = true
			"fxaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			"smaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			"scale66": get_viewport().scaling_3d_scale = 0.66
			"scale70": get_viewport().scaling_3d_scale = 0.7
			"sharpen": sharpen.visible = false
			"treeshadow":
				forest.shadow_range = 0.0
				forest.shadow_near = 0.0
			"lod0": forest.lod_r0 = 10.0
			"impostors": forest.get_node("Impostors").visible = false
			"radiance64": env.sky.radiance_size = Sky.RADIANCE_SIZE_64
			"envinc": env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			"radiance128": env.sky.radiance_size = Sky.RADIANCE_SIZE_128
			"noupscale": get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			"noglow": env.glow_enabled = false


func apply_quality(q: String) -> void:
	quality = q
	var vp := get_viewport()
	match q:
		"niska":
			env.ssr_enabled = false
			env.ssao_enabled = false
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 180.0
			sky.set_cloud_quality(24, 3)
			if grass: grass.set_density(85)
			if forest: forest.set_quality(0.65)
		"srednia":
			env.ssr_enabled = false
			env.ssao_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 230.0
			sky.set_cloud_quality(26, 3)
			if grass: grass.set_density(105)
			if forest: forest.set_quality(0.68)
		"wysoka":
			env.ssr_enabled = true
			env.ssr_max_steps = 28
			env.ssao_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 230.0
			sky.set_cloud_quality(28, 4)
			if grass: grass.set_density(135)
			if forest: forest.set_quality(1.0)
		"ultra":
			env.ssr_enabled = true
			env.ssr_max_steps = 56
			env.ssao_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 420.0
			sky.set_cloud_quality(56, 6)
			if grass: grass.set_density(162)
			if forest: forest.set_quality(1.6)
	# Temporal upscaling looks best but costs about 6 ms at this resolution, so the
	# lower presets use the spatial upscaler with SMAA and stable dithering instead.
	var temporal := q == "wysoka" or q == "ultra"
	if OS.get_name() == "macOS":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if temporal else Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if temporal else Viewport.SCALING_3D_MODE_FSR
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if temporal else Viewport.SCREEN_SPACE_AA_SMAA
	sky.temporal_dither = temporal


func _ui_shot(path: String) -> void:
	# Dev helper: menu screenshot, then drive with HUD and screenshot again.
	if Game.args.has("time"):
		clock.time = float(Game.arg("time"))
	await get_tree().create_timer(6.0).timeout
	get_viewport().get_texture().get_image().save_png(path.replace(".png", "_menu.png"))
	ui._on_drive()
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(path.replace(".png", "_hud.png"))
	ui.open_pause()
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(path.replace(".png", "_pause.png"))
	get_tree().quit()


func _start_drive() -> void:
	set_cinema(false)
	photo_mode = false
	car.controls_enabled = true
	_capture_mouse()


func _to_menu() -> void:
	# The menu sits on top of the cinematic autopilot.
	set_cinema(true)
	car.controls_enabled = false
	_release_mouse()


func _playing() -> bool:
	return ui != null and ui.hud.visible and not get_tree().paused


func toggle_photo_mode() -> void:
	photo_mode = not photo_mode
	var vp := get_viewport()
	if photo_mode:
		# Nothing moves in a photo, so render every pixel.
		_scale_before_photo = vp.scaling_3d_scale
		vp.scaling_3d_scale = 1.0
		car.controls_enabled = false
		camera.set_mode(CameraRig.Mode.PHOTO)
		ui.hud.visible = false
		ui.photo_overlay.visible = true
		_capture_mouse()
	else:
		vp.scaling_3d_scale = _scale_before_photo
		ui.photo_overlay.visible = false
		ui.hud.visible = true
		camera.set_mode(CameraRig.Mode.CINEMATIC if cinema else CameraRig.Mode.CHASE)
		camera.snap()
		car.controls_enabled = not cinema


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_cinema(on: bool) -> void:
	cinema = on
	car.autopilot = on
	camera.set_mode(CameraRig.Mode.CINEMATIC if on else CameraRig.Mode.CHASE)
	camera.snap()


func _unhandled_input(event: InputEvent) -> void:
	# Keys pressed while the world is still loading.
	if car == null:
		return
	if ui and not _playing() and not photo_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_C:
				if not cinema and not photo_mode:
					camera.cycle_mode()
			KEY_K:
				if not photo_mode:
					set_cinema(not cinema)
					car.controls_enabled = not cinema
			KEY_P:
				if ui:
					toggle_photo_mode()
			KEY_F:
				if postcards and not photo_mode:
					postcards.take_photo()
			KEY_SPACE:
				if postcards and photo_mode:
					postcards.take_photo()
			KEY_TAB:
				if postcards:
					postcards.next_card()
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()


func _process(delta: float) -> void:
	_ssr_timer -= delta
	if _ssr_timer <= 0.0 and terrain and terrain.is_ready and quality != "niska" and quality != "srednia" and not Game.args.has("perf_off"):
		_ssr_timer = 0.5
		_update_ssr()
	_sea_timer -= delta
	if ambient and terrain and _sea_timer <= 0.0:
		# How much open sea surrounds the camera drives the wave sounds.
		_sea_timer = 0.5
		var p := camera.global_position
		var wet := 0
		for k in 12:
			var d := Vector2.from_angle(TAU * k / 12.0) * 260.0
			if terrain.height_at(p.x + d.x, p.z + d.y) < 0.0:
				wet += 1
		ambient.sea_amount = lerpf(ambient.sea_amount, (wet / 12.0) * clampf(1.0 - p.y / 150.0, 0.2, 1.0), 0.5)
	# Hold T to let time fly (sunsets come faster).
	if clock and (ui == null or _playing() or photo_mode):
		var fast := Input.is_physical_key_pressed(KEY_T)
		var base: float = Settings.time_scale if ui else 12.0
		clock.time_scale = lerpf(clock.time_scale, 360.0 if fast else base, 1.0 - exp(-delta * 4.0))
	if ui:
		camera.mouse_sensitivity = Settings.mouse_sensitivity


## Reflections of the land only matter on wet ground and near the sea, so
## screen-space reflections stay off the rest of the time.
func _update_ssr() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var want := weather.wetness > 0.05
	if not want:
		for i in 8:
			var a := TAU * i / 8.0
			if terrain.height_at(p.x + cos(a) * 180.0, p.z + sin(a) * 180.0) < 0.5:
				want = true
				break
	env.ssr_enabled = want


func _build_sharpen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Sharpen"
	layer.layer = -1
	sharpen = ColorRect.new()
	sharpen.set_anchors_preset(Control.PRESET_FULL_RECT)
	sharpen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sharpen.gdshader")
	sharpen.material = mat
	layer.add_child(sharpen)
	add_child(layer)


func _build_terrain_collision() -> void:
	# Every second row and column: 5 m is plenty for wheels leaving the road.
	var shape := HeightMapShape3D.new()
	var n := TerrainData.SIZE / 2
	var data := PackedFloat32Array()
	data.resize(n * n)
	for z in n:
		var row := z * 2 * TerrainData.SIZE
		for x in n:
			data[z * n + x] = terrain.heights[row + x * 2]
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface", "terrain")
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(TerrainData.TEXEL * 2.0, 1.0, TerrainData.TEXEL * 2.0)
	body.add_child(cs)
	add_child(body)


func _build_environment() -> void:
	env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	for i in 7:
		env.set_glow_level(i, 1.0 if i == 3 else 0.0)
	env.glow_normalized = false
	env.glow_intensity = 0.42
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
	env.ambient_light_sky_contribution = 0.66
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 28
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
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
	l.directional_shadow_max_distance = 320.0
	l.shadow_blur = 1.2
	l.light_angular_distance = 0.6
	add_child(l)
	return l

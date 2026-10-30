class_name ShotRunner
extends Node
## Renders a list of shots from a JSON file and quits. Used to check the look
## from the command line:  godot --path . -- --shots=res://dev/shots.json
## Each shot: {"time": 19.5, "weather": "pogodnie", "cam": [x,y,z],
##             "look": [x,y,z], "fov": 60, "out": "/abs/path.png", "frames": 40}

var camera: CameraRig


func run(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var shots: Array = JSON.parse_string(text)
	if not Game.sky.is_baked:
		await Game.sky.baked
	for shot in shots:
		await _render(shot)
	get_tree().quit()


func _render(shot: Dictionary) -> void:
	if shot.has("weather"):
		Game.weather.set_preset(shot["weather"], true)
	if shot.has("time"):
		Game.clock.time = float(shot["time"])
	Game.clock.paused = true
	if shot.has("drive"):
		# Let the car drive itself for a while, then shoot with the given camera mode.
		var world = Game.world
		world.set_cinema(true)
		if shot.has("road_index"):
			world.car.place_on_road(int(shot["road_index"]))
		camera.set_process(true)
		var mode_name: String = shot.get("mode", "chase")
		var modes := {"chase": CameraRig.Mode.CHASE, "far": CameraRig.Mode.CHASE_FAR, "bonnet": CameraRig.Mode.BONNET, "cinema": CameraRig.Mode.CINEMATIC}
		camera.set_mode(modes.get(mode_name, CameraRig.Mode.CHASE))
		camera.snap()
		var t_end := Time.get_ticks_msec() + int(float(shot["drive"]) * 1000.0)
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
		if shot.has("car_cam"):
			var cc: Array = shot["car_cam"]
			camera.set_process(false)
			var xf: Transform3D = world.car.global_transform
			camera.global_position = xf * Vector3(cc[0], cc[1], cc[2])
			camera.look_at(xf * Vector3(0, 0.4, 0))
			camera.fov = 40.0
			for k in 8:
				await get_tree().process_frame
		print("drive: speed %.1f km/h gear %d rpm %.0f pos %s" % [world.car.speed_kmh, world.car.gear, world.car.rpm, world.car.global_position])
	elif shot.has("cam") and camera:
		camera.set_process(false)
		var c: Array = shot["cam"]
		var l: Array = shot.get("look", [c[0], c[1], float(c[2]) - 10.0])
		camera.global_position = Vector3(c[0], c[1], c[2])
		camera.look_at(Vector3(l[0], l[1], l[2]))
		camera.fov = float(shot.get("fov", 62.0))
	Game.clock.set("_exposure_initialised", false)
	for i in int(shot.get("frames", 45)):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var w := int(shot.get("width", 1280))
	if img.get_width() > w:
		img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_png(shot["out"])
	print("shot saved ", shot["out"])


func _process(_delta: float) -> void:
	if Game.args.has("debug_sky") and Engine.get_process_frames() % 30 == 0 and Game.clock:
		print("t=%.2f sun=%s moon=%s night=%.2f exp=%.1f sun_e=%.3f" % [Game.clock.time, Game.clock.sun_dir, Game.clock.moon_dir,
				Game.clock.night, Game.clock.exposure, Game.clock.sun_light.light_energy])

extends Node
## Cycles the interface and writes res://dev/out/ui_*.png.

const BG := """shader_type canvas_item;
void fragment() {
	vec3 zenith = vec3(0.10, 0.16, 0.32);
	vec3 gold = vec3(0.95, 0.58, 0.28);
	vec3 ground = vec3(0.04, 0.04, 0.05);
	float y = UV.y;
	vec3 c = mix(zenith, gold, smoothstep(0.05, 0.58, y));
	c = mix(c, ground, smoothstep(0.60, 0.80, y));
	float sun = smoothstep(0.16, 0.0, length(UV - vec2(0.74, 0.55)));
	c = mix(c, vec3(1.0, 0.88, 0.62), sun * 0.9);
	COLOR = vec4(c, 1.0);
}
"""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	await _go()


func _go() -> void:
	_prepare_world()
	_prepare_album()
	get_tree().set_meta(&"horyzont_keep_window", true)
	var ui := UIRoot.new()
	add_child(ui)
	_force_window()
	for i in 4:
		await get_tree().process_frame
	_force_window()
	await get_tree().process_frame
	var view := get_viewport().get_visible_rect().size
	print("UI window ", get_window().size, " view ", view)

	ui.show_main_menu()
	await _wait(0.75)
	await _shot("ui_main_menu")

	_place_golden_hour()
	var game: Variant = _game()
	if game.weather != null:
		game.weather.set_preset("zlota_mgielka", true)
	Settings.show_fps = true
	ui.show_hud()
	ui.hud.show_toast("Skręć w stronę cypla", 4.0)
	ui.hud.set_objective("Latarnia na cyplu", Vector3(-400, 2, -900))
	await _wait(0.6)
	await _shot("ui_hud")

	Settings.show_fps = false
	ui.open_pause()
	await _wait(0.5)
	await _shot("ui_pause")

	ui.open_settings()
	await _wait(0.5)
	await _shot("ui_settings")

	ui.open_album()
	await _wait(0.45)
	await _shot("ui_album")

	ui.show_hud()
	ui.photo_overlay.visible = true
	await _wait(0.35)
	await _shot("ui_photo")
	ui.photo_overlay.flash()
	await _wait(0.45)
	var card := Image.create(640, 400, false, Image.FORMAT_RGB8)
	card.fill_rect(Rect2i(0, 0, 640, 230), Color(0.22, 0.32, 0.48))
	card.fill_rect(Rect2i(0, 230, 640, 170), Color(0.86, 0.48, 0.24))
	ui.photo_overlay.show_result(ImageTexture.create_from_image(card), "Cypel o zachodzie", 2)
	await _wait(0.45)
	await _shot("ui_photo_result")

	_cleanup_album()
	print("UI test done")
	get_tree().quit()


func _prepare_world() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = BG
	var mat := ShaderMaterial.new()
	mat.shader = shader
	bg.material = mat
	layer.add_child(bg)

	var game: Variant = _game()
	# Real TimeOfDay / Weather. Loaded by path so --check-only does not compile the sky autoload uses.
	if game.clock == null:
		var clock: Node = load("res://scripts/sky/time_of_day.gd").new()
		clock.name = "Clock"
		add_child(clock)
		game.clock = clock
	if game.weather == null:
		var weather: Node = load("res://scripts/sky/weather.gd").new()
		weather.name = "Weather"
		add_child(weather)
		game.weather = weather
	if game.clock != null and game.weather != null:
		game.clock.weather = game.weather
		game.weather.clock = game.clock

	var cam := Camera3D.new()
	cam.position = Vector3(10, 3, 20)
	add_child(cam)
	cam.current = true
	cam.look_at(Vector3(10, 2, -40))


func _place_golden_hour() -> void:
	var clock: Variant = _game().clock
	if clock == null:
		return
	var best := 19.5
	var prev := 90.0
	for i in 240:
		clock.time = 12.0 + float(i) * 0.05
		clock.update_sky(0.0)
		var elev: float = clock.sun_elevation_deg()
		if prev > 3.0 and elev <= 3.0:
			best = clock.time
			break
		prev = elev
	clock.time = best
	clock.update_sky(0.0)
	print("UI golden hour ", UIStyle.format_clock(best), " elev ", snappedf(clock.sun_elevation_deg(), 0.1))


func _game() -> Variant:
	return get_tree().root.get_node("Game")


func _prepare_album() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://album"))
	_write_shot("uitest_cypel.png", Color(0.86, 0.5, 0.28), Color(0.16, 0.22, 0.38), "Cypel", 3)
	_write_shot("uitest_wydmy.png", Color(0.93, 0.72, 0.42), Color(0.45, 0.32, 0.22), "Droga przez wydmy", 2)
	_write_shot("uitest_deszcz.png", Color(0.35, 0.4, 0.46), Color(0.12, 0.14, 0.16), "Po deszczu", 1)
	_write_shot("uitest_latarnia.png", Color(0.95, 0.78, 0.55), Color(0.2, 0.16, 0.22), "Latarnia", 0)


func _write_shot(file_name: String, sky: Color, ground: Color, title: String, stars: int) -> void:
	var image := Image.create(480, 300, false, Image.FORMAT_RGB8)
	image.fill_rect(Rect2i(0, 0, 480, 170), sky)
	image.fill_rect(Rect2i(0, 170, 480, 130), ground)
	var path := "user://album".path_join(file_name)
	image.save_png(path)
	var file := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"title": title,
		"stars": stars,
		"time": "19:24",
		"weather": "Złota mgiełka",
	}))


func _cleanup_album() -> void:
	var dir := DirAccess.open("user://album")
	if dir == null:
		return
	for file_name in dir.get_files():
		var name := str(file_name)
		if not name.begins_with("uitest_"):
			continue
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://album".path_join(name)))


func _force_window() -> void:
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(1280, 800)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - Vector2i(1280, 800)) / 2)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://dev/out/%s.png" % name
	var err := image.save_png(path)
	print("UI shot %s %dx%d err=%s" % [name, image.get_width(), image.get_height(), error_string(err)])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true, false).timeout

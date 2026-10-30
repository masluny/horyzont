class_name Settings
extends RefCounted
## Preferences persisted in user://settings.cfg and pushed onto the running game.

const PATH := "user://settings.cfg"
const QUALITY_IDS: PackedStringArray = ["niska", "srednia", "wysoka", "ultra"]
const QUALITY_LABELS: PackedStringArray = ["Niska", "Średnia", "Wysoka", "Ultra"]

static var quality := "wysoka"
static var render_scale := 0.62
static var fullscreen := true
static var vsync := true
static var max_fps := 0
static var master_volume := 0.8
static var mouse_sensitivity := 1.0
static var show_fps := false
static var time_scale := 12.0
static var auto_weather := true
static var help_seen := false


@warning_ignore("shadowed_global_identifier")
static func load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var stored := str(cfg.get_value("video", "quality", quality))
	quality = stored if QUALITY_IDS.has(stored) else "wysoka"
	render_scale = clampf(float(cfg.get_value("video", "render_scale", render_scale)), 0.5, 1.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	max_fps = maxi(int(cfg.get_value("video", "max_fps", max_fps)), 0)
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 3.0)
	show_fps = bool(cfg.get_value("game", "show_fps", show_fps))
	time_scale = clampf(float(cfg.get_value("game", "time_scale", time_scale)), 1.0, 240.0)
	auto_weather = bool(cfg.get_value("game", "auto_weather", auto_weather))
	help_seen = bool(cfg.get_value("game", "help_seen", help_seen))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("game", "show_fps", show_fps)
	cfg.set_value("game", "time_scale", time_scale)
	cfg.set_value("game", "auto_weather", auto_weather)
	cfg.set_value("game", "help_seen", help_seen)
	cfg.save(PATH)


## Window, vsync, 3D scale, master bus, clock, weather, and world quality.
static func apply(tree: SceneTree) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var sync := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(sync)
	Engine.max_fps = maxi(max_fps, 0)
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		var volume := clampf(master_volume, 0.0, 1.0)
		var db := linear_to_db(volume) if volume > 0.0001 else -80.0
		AudioServer.set_bus_volume_db(bus, db)
	var game: Variant = _autoload(tree)
	if game == null:
		return
	if game.clock != null:
		game.clock.time_scale = time_scale
	if game.weather != null:
		game.weather.auto_cycle = auto_weather
	if game.world != null and game.world.has_method("apply_quality"):
		game.world.call("apply_quality", quality)


## Autoload is not in scope for `godot --check-only --script`, so resolve it from the tree.
static func _autoload(tree: SceneTree) -> Variant:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Game")

class_name UIRoot
extends CanvasLayer
## Owns every screen. Esc pauses, H hides the HUD, F1 toggles the control card.

signal drive_requested
signal cinema_requested
signal main_menu_requested

var hud: Hud
var pause_menu: PauseMenu
var main_menu: MainMenu
var settings_menu: SettingsMenu
var photo_overlay: PhotoOverlay
var album: Album
var help_overlay: HelpOverlay

var _root: Control
var _playing := false
var _settings_back := "main"
var _album_back := "main"
var _splash: Control
var _splash_title: Label
var _splash_rule: ColorRect
var _splash_line: Label
var _splash_pulse := 0.0
var _boot_done := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10


func _ready() -> void:
	Settings.load()
	if get_tree().has_meta(&"horyzont_keep_window"):
		Settings.fullscreen = false
	Settings.apply(get_tree())

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	hud = Hud.new()
	pause_menu = PauseMenu.new()
	main_menu = MainMenu.new()
	settings_menu = SettingsMenu.new()
	photo_overlay = PhotoOverlay.new()
	album = Album.new()
	help_overlay = HelpOverlay.new()
	for screen in [hud, photo_overlay, help_overlay, main_menu, pause_menu, settings_menu, album]:
		_mount(screen)
	_build_splash()

	main_menu.drive_pressed.connect(_on_drive)
	main_menu.cinema_pressed.connect(_on_cinema)
	main_menu.album_pressed.connect(open_album)
	main_menu.settings_pressed.connect(open_settings)
	pause_menu.resume_pressed.connect(show_hud)
	pause_menu.settings_pressed.connect(open_settings)
	pause_menu.main_menu_pressed.connect(_on_main_menu)
	settings_menu.closed.connect(_close_settings)
	album.closed.connect(_close_album)

	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()
	# The UI harness has no island to wait on.
	if get_tree().has_meta(&"horyzont_keep_window"):
		_splash.visible = false
		_boot_done = true
		show_main_menu()
	else:
		main_menu.visible = false
		_splash.visible = true
		_splash.modulate.a = 1.0


func _process(delta: float) -> void:
	if _boot_done:
		return
	_splash_pulse += delta
	var wave := 0.38 + 0.62 * (0.5 + 0.5 * sin(_splash_pulse * 2.4))
	_splash_line.modulate.a = wave
	if _world_ready():
		_reveal_menu()


func show_main_menu(menu_fade: float = 0.4) -> void:
	_playing = false
	get_tree().paused = false
	hud.visible = false
	help_overlay.close()
	pause_menu.visible = false
	settings_menu.visible = false
	album.visible = false
	photo_overlay.visible = false
	main_menu.visible = true
	main_menu.fade_in(menu_fade)


func show_hud() -> void:
	var fresh := not _playing
	_playing = true
	get_tree().paused = false
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	album.visible = false
	hud.visible = true
	hud.fade_in()
	if fresh:
		hud.start_hint()


func open_pause() -> void:
	if not _playing:
		return
	help_overlay.close()
	main_menu.visible = false
	settings_menu.visible = false
	album.visible = false
	hud.visible = false
	pause_menu.open()


func open_settings() -> void:
	if pause_menu.visible:
		_settings_back = "pause"
	elif _playing:
		_settings_back = "hud"
	else:
		_settings_back = "main"
	help_overlay.close()
	main_menu.visible = false
	hud.visible = false
	pause_menu.visible = false
	album.visible = false
	settings_menu.open()


func open_album() -> void:
	if pause_menu.visible:
		_album_back = "pause"
	elif _playing:
		_album_back = "hud"
	else:
		_album_back = "main"
	help_overlay.close()
	main_menu.visible = false
	hud.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	album.open()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_ESCAPE:
		_on_escape()
		get_viewport().set_input_as_handled()
	elif code == KEY_F1:
		_on_f1()
		get_viewport().set_input_as_handled()
	elif code == KEY_H and not key.alt_pressed and not key.command_or_control_autoremap:
		_on_h()
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if settings_menu.visible:
		_close_settings()
	elif album.visible:
		album.go_back()
	elif help_overlay.visible:
		help_overlay.close()
	elif photo_overlay.visible:
		photo_overlay.dismiss()
	elif pause_menu.visible:
		show_hud()
	elif main_menu.visible:
		return
	elif _playing:
		open_pause()


func _on_f1() -> void:
	if help_overlay.visible:
		help_overlay.close()
		return
	if not _playing or _blocked():
		return
	help_overlay.open(false)


func _on_h() -> void:
	if main_menu.visible or pause_menu.visible or settings_menu.visible or album.visible or help_overlay.visible:
		return
	hud.visible = not hud.visible
	if hud.visible:
		hud.wake()


func _on_drive() -> void:
	show_hud()
	if not Settings.help_seen:
		Settings.help_seen = true
		Settings.save()
		help_overlay.open(true)
	drive_requested.emit()


func _on_cinema() -> void:
	show_hud()
	cinema_requested.emit()


func _on_main_menu() -> void:
	main_menu_requested.emit()
	show_main_menu()


func _close_settings() -> void:
	settings_menu.visible = false
	if _settings_back == "pause":
		pause_menu.visible = true
		pause_menu.sync()
		get_tree().paused = true
	elif _settings_back == "hud":
		show_hud()
	else:
		show_main_menu()


func _close_album() -> void:
	album.visible = false
	if _album_back == "pause":
		pause_menu.visible = true
		pause_menu.sync()
		get_tree().paused = true
	elif _album_back == "hud":
		show_hud()
	else:
		show_main_menu()


func _apply_scale() -> void:
	var height := get_viewport().get_visible_rect().size.y
	if height < 64.0:
		return
	var s := UIStyle.scale_from(height)
	_root.theme = UIStyle.make_theme(s)
	UIStyle.set_panel_radius(s)
	main_menu.apply_scale(s)
	hud.apply_scale(s)
	pause_menu.apply_scale(s)
	settings_menu.apply_scale(s)
	photo_overlay.apply_scale(s)
	album.apply_scale(s)
	help_overlay.apply_scale(s)
	_apply_splash_scale(s)


func _mount(screen: Control) -> void:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(screen)


func _blocked() -> bool:
	return main_menu.visible or pause_menu.visible or settings_menu.visible or album.visible or photo_overlay.visible


func _build_splash() -> void:
	_splash = Control.new()
	_splash.mouse_filter = Control.MOUSE_FILTER_STOP
	_splash.visible = false
	_mount(_splash)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.016, 0.02)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_splash.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	_splash_title = Label.new()
	_splash_title.text = "HORYZONT"
	_splash_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_splash_title)

	_splash_rule = ColorRect.new()
	_splash_rule.color = Color(1, 1, 1, 0.55)
	_splash_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_splash_rule)

	_splash_line = Label.new()
	_splash_line.text = "Generowanie wyspy…"
	_splash_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_splash_line)


func _apply_splash_scale(scale: float) -> void:
	var column := _splash_line.get_parent() as VBoxContainer
	column.add_theme_constant_override("separation", int(round(14.0 * scale)))
	_splash_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(14.0 * scale))))
	_splash_title.add_theme_font_size_override("font_size", int(round(60.0 * scale)))
	_splash_title.add_theme_constant_override("shadow_outline_size", int(round(12.0 * scale)))
	_splash_rule.custom_minimum_size = Vector2(42.0 * scale, maxf(1.0, scale))
	_splash_line.add_theme_font_override("font", UIStyle.tracked_font(int(round(1.0 * scale))))
	_splash_line.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	_splash_line.add_theme_color_override("font_color", Color(1, 0.97, 0.92, 0.72))


func _world_ready() -> bool:
	var game: Variant = get_tree().root.get_node_or_null("Game")
	if game == null:
		return false
	var terrain: Variant = game.terrain
	var sky: Variant = game.sky
	if terrain == null or sky == null:
		return false
	return bool(terrain.is_ready) and bool(sky.is_baked)


func _reveal_menu() -> void:
	_boot_done = true
	_splash_line.modulate.a = 1.0
	show_main_menu(1.2)
	var tw := UIStyle.tween(self)
	tw.tween_property(_splash, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func() -> void: _splash.visible = false, CONNECT_ONE_SHOT)

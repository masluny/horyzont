class_name UIRoot
extends CanvasLayer
## Owns every screen. Esc pauses, H hides the HUD.

signal drive_requested
signal cinema_requested
signal main_menu_requested

var hud: Hud
var pause_menu: PauseMenu
var main_menu: MainMenu
var settings_menu: SettingsMenu
var photo_overlay: PhotoOverlay
var album: Album

var _root: Control
var _playing := false
var _settings_back := "main"
var _album_back := "main"


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
	for screen in [hud, photo_overlay, main_menu, pause_menu, settings_menu, album]:
		_mount(screen)

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
	show_main_menu()


func show_main_menu() -> void:
	_playing = false
	get_tree().paused = false
	hud.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	album.visible = false
	photo_overlay.visible = false
	main_menu.visible = true
	main_menu.fade_in()


func show_hud() -> void:
	_playing = true
	get_tree().paused = false
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	album.visible = false
	hud.visible = true
	hud.fade_in()


func open_pause() -> void:
	if not _playing:
		return
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
	elif code == KEY_H and not key.alt_pressed and not key.command_or_control_autoremap:
		_on_h()
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if settings_menu.visible:
		_close_settings()
	elif album.visible:
		album.go_back()
	elif photo_overlay.visible:
		photo_overlay.dismiss()
	elif pause_menu.visible:
		show_hud()
	elif main_menu.visible:
		return
	elif _playing:
		open_pause()


func _on_h() -> void:
	if main_menu.visible or pause_menu.visible or settings_menu.visible or album.visible:
		return
	hud.visible = not hud.visible
	if hud.visible:
		hud.wake()


func _on_drive() -> void:
	show_hud()
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


func _mount(screen: Control) -> void:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(screen)

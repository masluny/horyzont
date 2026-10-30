class_name MainMenu
extends Control
## Title card over the live world.

signal drive_pressed
signal cinema_pressed
signal album_pressed
signal settings_pressed

var _column: VBoxContainer
var _title: Label
var _subtitle: Label
var _rule: ColorRect
var _gap: Control
var _exit_gap: Control
var _drive: Button
var _cinema: Button
var _album: Button
var _settings: Button
var _quit: Button
var _scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.anchor_right = 0.52
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.color = Color.WHITE
	wash.material = UIStyle.vignette_material()
	add_child(wash)

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_title = Label.new()
	_title.text = "HORYZONT"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_title)

	var rule_row := HBoxContainer.new()
	rule_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule = ColorRect.new()
	_rule.color = Color(1, 1, 1, 0.55)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_row.add_child(_rule)
	_column.add_child(rule_row)

	_subtitle = Label.new()
	_subtitle.text = "road trip w złotej godzinie"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_subtitle)

	_gap = Control.new()
	_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_gap)

	_drive = _button("Jedź")
	_cinema = _button("Kino")
	_album = _button("Album")
	_settings = _button("Ustawienia")
	_exit_gap = Control.new()
	_exit_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit = _button("Wyjdź")
	_quit.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	for node in [_drive, _cinema, _album, _settings, _exit_gap, _quit]:
		_column.add_child(node)

	_drive.pressed.connect(func() -> void: drive_pressed.emit())
	_cinema.pressed.connect(func() -> void: cinema_pressed.emit())
	_album.pressed.connect(func() -> void: album_pressed.emit())
	_settings.pressed.connect(func() -> void: settings_pressed.emit())
	_quit.pressed.connect(func() -> void: get_tree().quit())


func apply_scale(scale: float) -> void:
	_scale = scale
	var margin := 84.0 * scale
	_column.anchor_left = 0.0
	_column.anchor_right = 0.0
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.offset_left = margin
	_column.offset_right = margin
	_column.offset_top = 0.0
	_column.offset_bottom = 0.0
	_column.grow_horizontal = Control.GROW_DIRECTION_END
	_column.grow_vertical = Control.GROW_DIRECTION_BOTH
	_column.add_theme_constant_override("separation", int(round(8.0 * scale)))
	_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(14.0 * scale))))
	_title.add_theme_font_size_override("font_size", int(round(60.0 * scale)))
	_title.add_theme_constant_override("shadow_outline_size", int(round(12.0 * scale)))
	_subtitle.add_theme_font_override("font", UIStyle.tracked_font(int(round(1.0 * scale))))
	_subtitle.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
	_subtitle.add_theme_color_override("font_color", Color(1, 0.97, 0.92, 0.7))
	_rule.custom_minimum_size = Vector2(42.0 * scale, maxf(1.0, scale))
	_gap.custom_minimum_size = Vector2(0, 28.0 * scale)
	_exit_gap.custom_minimum_size = Vector2(0, 10.0 * scale)
	var button_px := int(round(22.0 * scale))
	for b in [_drive, _cinema, _album, _settings, _quit]:
		b.add_theme_font_size_override("font_size", button_px)
		b.custom_minimum_size.y = 36.0 * scale


func fade_in(duration: float = 0.4) -> void:
	UIStyle.fade_in(self, duration)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

class_name PauseMenu
extends Control
## Esc menu. The tree stays paused; dragging the clock updates the sky directly.

signal resume_pressed
signal settings_pressed
signal main_menu_pressed

var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _time: HSlider
var _time_value: Label
var _weather: OptionButton
var _auto: CheckBox
var _scale_slider: HSlider
var _scale_value: Label
var _quit: Button
var _preset_ids: Array[String] = []
var _scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.025, 0.035, 0.38)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.material = UIStyle.blur_material()
	center.add_child(_panel)

	_body = VBoxContainer.new()
	_panel.add_child(_body)

	_title = Label.new()
	_title.text = "Pauza"
	_body.add_child(_title)

	var resume := _text_button("Wznów")
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	_body.add_child(resume)

	_body.add_child(_caption("Pora dnia"))
	_time = HSlider.new()
	_time.min_value = 0.0
	_time.max_value = 24.0
	_time.step = 0.05
	_time_value = _value_label("00:00")
	_body.add_child(_slider_row(_time, _time_value))
	_time.value_changed.connect(_on_time)

	_body.add_child(_caption("Pogoda"))
	_weather = OptionButton.new()
	_weather.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_body.add_child(_weather)
	_weather.item_selected.connect(_on_weather)

	_auto = CheckBox.new()
	_auto.text = "Automatyczna pogoda"
	_body.add_child(_auto)
	_auto.toggled.connect(_on_auto)

	_body.add_child(_caption("Tempo czasu"))
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 1.0
	_scale_slider.max_value = 240.0
	_scale_slider.step = 1.0
	_scale_value = _value_label("12×")
	_body.add_child(_slider_row(_scale_slider, _scale_value))
	_scale_slider.value_changed.connect(_on_time_scale)

	var settings := _text_button("Ustawienia")
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	var main := _text_button("Menu główne")
	main.pressed.connect(func() -> void: main_menu_pressed.emit())
	_quit = _text_button("Wyjdź z gry")
	_quit.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_quit.pressed.connect(func() -> void: get_tree().quit())
	_body.add_child(settings)
	_body.add_child(main)
	_body.add_child(_quit)


func apply_scale(scale: float) -> void:
	_scale = scale
	var width := minf(560.0 * scale, get_viewport_rect().size.x - 64.0 * scale)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(scale))
	_body.add_theme_constant_override("separation", int(round(8.0 * scale)))
	_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(6.0 * scale))))
	_title.add_theme_font_size_override("font_size", int(round(28.0 * scale)))
	for child in _body.get_children():
		if child is Button:
			(child as Button).add_theme_font_size_override("font_size", int(round(18.0 * scale)))
		elif child is CheckBox:
			(child as CheckBox).add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_time.custom_minimum_size.y = 22.0 * scale
	_scale_slider.custom_minimum_size.y = 22.0 * scale
	_weather.custom_minimum_size.y = 34.0 * scale
	_time_value.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_scale_value.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	UIStyle.style_popup(_weather)


func open() -> void:
	visible = true
	sync()
	get_tree().paused = true
	UIStyle.fade_in(self, 0.28)


func sync() -> void:
	_fill_weather()
	_time.set_block_signals(true)
	_scale_slider.set_block_signals(true)
	_weather.set_block_signals(true)
	_auto.set_block_signals(true)
	var game: Variant = _game()
	if game.clock != null:
		_time.value = clampf(game.clock.time, 0.0, 24.0)
		_scale_slider.value = clampf(game.clock.time_scale, 1.0, 240.0)
	_time_value.text = UIStyle.format_clock(_time.value)
	_scale_value.text = "%d×" % int(round(_scale_slider.value))
	if game.weather != null:
		var idx := _preset_ids.find(str(game.weather.current_id))
		if idx >= 0:
			_weather.select(idx)
		_auto.button_pressed = bool(game.weather.auto_cycle)
	_time.set_block_signals(false)
	_scale_slider.set_block_signals(false)
	_weather.set_block_signals(false)
	_auto.set_block_signals(false)


func _on_time(value: float) -> void:
	_time_value.text = UIStyle.format_clock(value)
	var clock: Variant = _game().clock
	if clock == null:
		return
	clock.time = value
	clock.update_sky(0.0)


func _on_time_scale(value: float) -> void:
	_scale_value.text = "%d×" % int(round(value))
	Settings.time_scale = value
	var clock: Variant = _game().clock
	if clock != null:
		clock.time_scale = value


func _on_weather(index: int) -> void:
	var weather: Variant = _game().weather
	if weather == null or index < 0 or index >= _preset_ids.size():
		return
	weather.set_preset(_preset_ids[index], true)


func _on_auto(on: bool) -> void:
	Settings.auto_weather = on
	var weather: Variant = _game().weather
	if weather != null:
		weather.auto_cycle = on


func _fill_weather() -> void:
	_weather.clear()
	_preset_ids.clear()
	var weather: Variant = _game().weather
	if weather == null:
		return
	var presets: Dictionary = weather.PRESETS
	for key in presets:
		var id := str(key)
		var entry: Dictionary = presets[key]
		_preset_ids.append(id)
		_weather.add_item(str(entry.get("name", id)))


func _game() -> Variant:
	return get_tree().root.get_node("Game")


func _caption(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return lab


func _value_label(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.custom_minimum_size.x = 72
	return lab


func _slider_row(slider: HSlider, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	row.add_child(value)
	return row


func _text_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

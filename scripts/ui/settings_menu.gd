class_name SettingsMenu
extends Control
## Edits every Settings field. Nothing is written until Zastosuj.

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _quality: OptionButton
var _render: HSlider
var _render_value: Label
var _fullscreen: CheckBox
var _vsync: CheckBox
var _fps: HSlider
var _fps_value: Label
var _volume: HSlider
var _volume_value: Label
var _sensitivity: HSlider
var _sensitivity_value: Label
var _show_fps: CheckBox
var _time_scale: HSlider
var _time_value: Label
var _auto: CheckBox
var _apply: Button
var _apply_token := 0
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
	_title.text = "Ustawienia"
	_body.add_child(_title)

	_quality = OptionButton.new()
	_quality.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for i in Settings.QUALITY_LABELS.size():
		_quality.add_item(Settings.QUALITY_LABELS[i])
	_body.add_child(_row("Jakość", _quality))

	_render = _slider(0.5, 1.0, 0.01)
	_render_value = _value()
	_render.value_changed.connect(func(v: float) -> void: _render_value.text = "%d%%" % int(round(v * 100.0)))
	_body.add_child(_row("Skala renderowania", _pair(_render, _render_value)))

	_fullscreen = _check("Pełny ekran")
	_vsync = _check("Synchronizacja pionowa")
	_body.add_child(_fullscreen)
	_body.add_child(_vsync)

	_fps = _slider(0.0, 360.0, 1.0)
	_fps_value = _value()
	_fps.value_changed.connect(func(v: float) -> void: _fps_value.text = _fps_text(v))
	_body.add_child(_row("Limit klatek", _pair(_fps, _fps_value)))

	_volume = _slider(0.0, 1.0, 0.01)
	_volume_value = _value()
	_volume.value_changed.connect(func(v: float) -> void: _volume_value.text = "%d%%" % int(round(v * 100.0)))
	_body.add_child(_row("Głośność", _pair(_volume, _volume_value)))

	_sensitivity = _slider(0.2, 3.0, 0.05)
	_sensitivity_value = _value()
	_sensitivity.value_changed.connect(func(v: float) -> void: _sensitivity_value.text = "%.2f" % v)
	_body.add_child(_row("Czułość myszy", _pair(_sensitivity, _sensitivity_value)))

	_show_fps = _check("Licznik klatek")
	_body.add_child(_show_fps)

	_time_scale = _slider(1.0, 240.0, 1.0)
	_time_value = _value()
	_time_scale.value_changed.connect(func(v: float) -> void: _time_value.text = "%d×" % int(round(v)))
	_body.add_child(_row("Tempo czasu", _pair(_time_scale, _time_value)))

	_auto = _check("Automatyczna pogoda")
	_body.add_child(_auto)

	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.y = 8
	_body.add_child(gap)

	var buttons := HBoxContainer.new()
	var back := Button.new()
	back.text = "Wstecz"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.pressed.connect(func() -> void: closed.emit())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply = Button.new()
	_apply.text = "Zastosuj"
	_apply.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply.pressed.connect(_on_apply)
	buttons.add_child(back)
	buttons.add_child(spacer)
	buttons.add_child(_apply)
	_body.add_child(buttons)


func apply_scale(scale: float) -> void:
	_scale = scale
	var width := minf(680.0 * scale, get_viewport_rect().size.x - 48.0 * scale)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(scale, 26.0, 20.0))
	_body.add_theme_constant_override("separation", int(round(8.0 * scale)))
	_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(4.0 * scale))))
	_title.add_theme_font_size_override("font_size", int(round(28.0 * scale)))
	var label_w := 210.0 * scale
	for child in _body.get_children():
		if child is HBoxContainer and child.get_child_count() > 0 and child.get_child(0) is Label:
			var lab := child.get_child(0) as Label
			lab.custom_minimum_size.x = label_w
			lab.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	for slider in [_render, _fps, _volume, _sensitivity, _time_scale]:
		slider.custom_minimum_size.y = 20.0 * scale
	for value in [_render_value, _fps_value, _volume_value, _sensitivity_value, _time_value]:
		value.custom_minimum_size.x = 108.0 * scale
		value.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	_quality.custom_minimum_size.y = 32.0 * scale
	for box in [_fullscreen, _vsync, _show_fps, _auto]:
		box.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	UIStyle.style_popup(_quality)


func open() -> void:
	visible = true
	sync()
	UIStyle.fade_in(self, 0.28)


func sync() -> void:
	var controls: Array[Control] = [
		_quality, _render, _fps, _volume, _sensitivity, _time_scale,
		_fullscreen, _vsync, _show_fps, _auto,
	]
	for c in controls:
		c.set_block_signals(true)
	var idx := Settings.QUALITY_IDS.find(Settings.quality)
	_quality.select(idx if idx >= 0 else 2)
	_render.value = Settings.render_scale
	_fps.value = clampf(float(Settings.max_fps), 0.0, 360.0)
	_volume.value = Settings.master_volume
	_sensitivity.value = Settings.mouse_sensitivity
	_time_scale.value = Settings.time_scale
	_fullscreen.button_pressed = Settings.fullscreen
	_vsync.button_pressed = Settings.vsync
	_show_fps.button_pressed = Settings.show_fps
	_auto.button_pressed = Settings.auto_weather
	_render_value.text = "%d%%" % int(round(_render.value * 100.0))
	_fps_value.text = _fps_text(_fps.value)
	_volume_value.text = "%d%%" % int(round(_volume.value * 100.0))
	_sensitivity_value.text = "%.2f" % _sensitivity.value
	_time_value.text = "%d×" % int(round(_time_scale.value))
	for c in controls:
		c.set_block_signals(false)


func _on_apply() -> void:
	var idx := clampi(_quality.selected, 0, Settings.QUALITY_IDS.size() - 1)
	Settings.quality = Settings.QUALITY_IDS[idx]
	Settings.render_scale = clampf(_render.value, 0.5, 1.0)
	Settings.fullscreen = _fullscreen.button_pressed
	Settings.vsync = _vsync.button_pressed
	Settings.max_fps = int(round(_fps.value))
	Settings.master_volume = clampf(_volume.value, 0.0, 1.0)
	Settings.mouse_sensitivity = clampf(_sensitivity.value, 0.2, 3.0)
	Settings.show_fps = _show_fps.button_pressed
	Settings.time_scale = clampf(_time_scale.value, 1.0, 240.0)
	Settings.auto_weather = _auto.button_pressed
	Settings.apply(get_tree())
	Settings.save()
	_apply_token += 1
	var token := _apply_token
	_apply.text = "Zapisano"
	await get_tree().create_timer(0.9, true).timeout
	if token == _apply_token:
		_apply.text = "Zastosuj"


func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = caption
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	row.add_child(control)
	return row


func _pair(slider: HSlider, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	row.add_child(value)
	return row


func _slider(min_v: float, max_v: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	return slider


func _value() -> Label:
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lab


func _check(text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	return box


func _fps_text(value: float) -> String:
	if value < 0.5:
		return "bez limitu"
	return str(int(round(value)))

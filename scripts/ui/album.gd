class_name Album
extends Control
## Grid of user://album/*.png with a sidecar json {title, stars, time, weather}.

signal closed

var _title: Label
var _back: Button
var _empty: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _viewer: Control
var _view_tex: TextureRect
var _view_title: Label
var _view_stars: Label
var _view_meta: Label
var _header: HBoxContainer
var _scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.035, 0.045, 0.62)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_header = HBoxContainer.new()
	_title = Label.new()
	_title.text = "Album"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back = Button.new()
	_back.text = "Wstecz"
	_back.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_back.pressed.connect(go_back)
	_header.add_child(_title)
	_header.add_child(_back)
	column.add_child(_header)

	_empty = Label.new()
	_empty.text = "Brak zdjęć"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_empty)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	_build_viewer()


func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_RESIZED and _grid != null:
		_update_columns()


func apply_scale(scale: float) -> void:
	_scale = scale
	var margin := get_child(1) as MarginContainer
	var m := int(round(40.0 * scale))
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_top", int(round(28.0 * scale)))
	margin.add_theme_constant_override("margin_bottom", m)
	_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(6.0 * scale))))
	_title.add_theme_font_size_override("font_size", int(round(34.0 * scale)))
	_back.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_empty.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
	_empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_grid.add_theme_constant_override("h_separation", int(round(16.0 * scale)))
	_grid.add_theme_constant_override("v_separation", int(round(18.0 * scale)))
	_view_title.add_theme_font_size_override("font_size", int(round(22.0 * scale)))
	_view_stars.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
	_view_meta.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	_update_columns()


func open() -> void:
	_viewer.visible = false
	visible = true
	refresh()
	UIStyle.fade_in(self, 0.28)


func go_back() -> void:
	if _viewer.visible:
		_viewer.visible = false
		return
	closed.emit()


func refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	var shots := _load_shots()
	_empty.visible = shots.is_empty()
	_scroll.visible = not shots.is_empty()
	var thumb_w := 220.0 * _scale
	var thumb_h := 146.0 * _scale
	for shot in shots:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", int(round(6.0 * _scale)))
		var button := TextureButton.new()
		button.texture_normal = shot["texture"]
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		button.custom_minimum_size = Vector2(thumb_w, thumb_h)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_open_viewer.bind(shot))
		var caption := Label.new()
		caption.text = str(shot["title"])
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", int(round(14.0 * _scale)))
		var stars := Label.new()
		stars.text = UIStyle.stars(int(shot["stars"]))
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars.add_theme_font_size_override("font_size", int(round(13.0 * _scale)))
		stars.add_theme_color_override("font_color", Color(0.93, 0.82, 0.45, 0.95))
		cell.add_child(button)
		cell.add_child(caption)
		cell.add_child(stars)
		_grid.add_child(cell)
	_update_columns()


func _open_viewer(shot: Dictionary) -> void:
	var texture := shot["texture"] as Texture2D
	_view_tex.texture = texture
	if texture != null:
		var tex_size := texture.get_size()
		var max_w := get_viewport_rect().size.x * 0.68
		var max_h := get_viewport_rect().size.y * 0.62
		var aspect := tex_size.x / maxf(tex_size.y, 1.0)
		var h := max_h
		var w := h * aspect
		if w > max_w:
			w = max_w
			h = w / maxf(aspect, 0.001)
		_view_tex.custom_minimum_size = Vector2(w, h)
	_view_title.text = str(shot["title"])
	_view_stars.text = UIStyle.stars(int(shot["stars"]))
	var meta := ""
	if str(shot["time"]) != "":
		meta = str(shot["time"])
	if str(shot["weather"]) != "":
		if meta != "":
			meta += "    ·    "
		meta += str(shot["weather"])
	_view_meta.text = meta
	_viewer.visible = true
	UIStyle.fade_in(_viewer, 0.25)


func _update_columns() -> void:
	if _scroll == null:
		return
	var avail := _scroll.size.x
	if avail < 20.0:
		avail = get_viewport_rect().size.x - 120.0 * _scale
	var cell := 250.0 * _scale
	_grid.columns = maxi(int(avail / cell), 2)


func _load_shots() -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var dir := DirAccess.open("user://album")
	if dir == null:
		return shots
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not str(file_name).ends_with(".png"):
			continue
		var path := "user://album".path_join(str(file_name))
		var image := Image.load_from_file(path)
		if image == null:
			continue
		var texture := ImageTexture.create_from_image(image)
		var meta := _read_meta(path.get_basename() + ".json")
		var when: Variant = meta.get("time", "")
		var time_text: String = UIStyle.format_clock(float(when)) if when is float or when is int else str(when)
		shots.append({
			"texture": texture,
			"title": str(meta.get("title", path.get_file().get_basename())),
			"stars": int(meta.get("stars", 0)),
			"time": time_text,
			"weather": str(meta.get("weather", "")),
		})
	return shots


func _read_meta(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _build_viewer() -> void:
	_viewer = Control.new()
	_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.visible = false
	_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.012, 0.016, 0.82)
	dim.gui_input.connect(_on_viewer_input)
	_viewer.add_child(dim)

	var back := Button.new()
	back.text = "Wstecz"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 36
	back.offset_top = 24
	back.grow_horizontal = Control.GROW_DIRECTION_END
	back.grow_vertical = Control.GROW_DIRECTION_END
	back.pressed.connect(func() -> void: _viewer.visible = false)
	_viewer.add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewer.add_child(center)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	_view_tex = TextureRect.new()
	_view_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_view_tex)
	_view_title = Label.new()
	_view_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_view_title)
	_view_stars = Label.new()
	_view_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_stars.add_theme_color_override("font_color", Color(0.93, 0.82, 0.45, 1))
	box.add_child(_view_stars)
	_view_meta = Label.new()
	_view_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_meta.add_theme_color_override("font_color", Color(1, 1, 1, 0.66))
	box.add_child(_view_meta)


func _on_viewer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_viewer.visible = false

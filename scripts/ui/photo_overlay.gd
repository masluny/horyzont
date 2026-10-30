class_name PhotoOverlay
extends Control
## Viewfinder chrome: thirds, hints, shutter flash and a short polaroid.

signal closed

var _grid: Thirds
var _hints: PanelContainer
var _hints_label: Label
var _flash: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _card: PanelContainer
var _photo: TextureRect
var _card_title: Label
var _card_stars: Label
var _card_host: CenterContainer
var _flash_tween: Tween
var _card_tween: Tween
var _scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_grid = Thirds.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_grid)

	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(stack)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_SHRINK_END
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(center)
	_hints = PanelContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.material = UIStyle.blur_material()
	_hints_label = Label.new()
	_hints_label.text = "Spacja — zdjęcie, Esc — wyjdź, Q/E — ogniskowa, Z/X — przysłona, scroll — ekspozycja"
	_hints_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hints_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_child(_hints_label)
	center.add_child(_hints)

	_bar_top = _bar()
	_bar_bottom = _bar()
	_bar_top.anchor_top = 0.0
	_bar_top.anchor_bottom = 0.0
	_bar_bottom.anchor_top = 1.0
	_bar_bottom.anchor_bottom = 1.0
	add_child(_bar_top)
	add_child(_bar_bottom)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color.WHITE
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_card_host = CenterContainer.new()
	_card_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_host)
	_card = PanelContainer.new()
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_host.add_child(_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_photo)
	_card_title = Label.new()
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_title.add_theme_color_override("font_color", Color(0.15, 0.14, 0.12, 1))
	_card_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	box.add_child(_card_title)
	_card_stars = Label.new()
	_card_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_stars.add_theme_color_override("font_color", Color(0.55, 0.42, 0.18, 1))
	_card_stars.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	box.add_child(_card_stars)


func apply_scale(scale: float) -> void:
	_scale = scale
	_hints.add_theme_stylebox_override("panel", UIStyle.panel_style(scale, 16.0, 8.0))
	_hints_label.add_theme_font_size_override("font_size", int(round(14.0 * scale)))
	_card.add_theme_stylebox_override("panel", UIStyle.paper_style(scale))
	_card_title.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
	_card_stars.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	var bottom := get_child(1) as MarginContainer
	var m := int(round(28.0 * scale))
	bottom.add_theme_constant_override("margin_bottom", m)
	bottom.add_theme_constant_override("margin_left", m)
	bottom.add_theme_constant_override("margin_right", m)


func flash() -> void:
	visible = true
	var half := size.y * 0.5
	_bar_top.offset_bottom = 0.0
	_bar_bottom.offset_top = 0.0
	_flash.modulate.a = 0.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = UIStyle.tween(self)
	_flash_tween.tween_property(_flash, "modulate:a", 0.92, 0.04)
	_flash_tween.parallel().tween_property(_bar_top, "offset_bottom", half, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.parallel().tween_property(_bar_bottom, "offset_top", -half, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.22)
	_flash_tween.parallel().tween_property(_bar_top, "offset_bottom", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flash_tween.parallel().tween_property(_bar_bottom, "offset_top", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func show_result(texture: Texture2D, title: String, stars: int) -> void:
	visible = true
	_photo.texture = texture
	_card_title.text = title
	_card_stars.text = UIStyle.stars(stars)
	if texture != null:
		var tex_size := texture.get_size()
		var max_w := minf(get_viewport_rect().size.x * 0.42, 440.0 * _scale)
		var aspect := tex_size.y / maxf(tex_size.x, 1.0)
		_photo.custom_minimum_size = Vector2(max_w, max_w * aspect)
	_card.visible = true
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.96, 0.96)
	_card.pivot_offset = _card.get_combined_minimum_size() * 0.5
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = UIStyle.tween(self)
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_card_tween.parallel().tween_property(_card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_card_tween.tween_interval(3.0)
	_card_tween.tween_property(_card, "modulate:a", 0.0, 0.35)
	_card_tween.finished.connect(func() -> void: _card.visible = false, CONNECT_ONE_SHOT)


func dismiss() -> void:
	if not visible:
		return
	visible = false
	_card.visible = false
	closed.emit()


func _bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	return bar


class Thirds extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.32)
		var w := size.x
		var h := size.y
		draw_line(Vector2(w / 3.0, 0), Vector2(w / 3.0, h), c, 1.0)
		draw_line(Vector2(w * 2.0 / 3.0, 0), Vector2(w * 2.0 / 3.0, h), c, 1.0)
		draw_line(Vector2(0, h / 3.0), Vector2(w, h / 3.0), c, 1.0)
		draw_line(Vector2(0, h * 2.0 / 3.0), Vector2(w, h * 2.0 / 3.0), c, 1.0)

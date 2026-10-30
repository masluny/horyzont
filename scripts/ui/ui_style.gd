class_name UIStyle
extends RefCounted
## Shared type, glass panels and theme for the in-game interface.

const PANEL := Color(0.05, 0.06, 0.08, 0.55)
const BLUR := preload("res://shaders/ui/backdrop_blur.gdshader")
const VIGNETTE := preload("res://shaders/ui/vignette.gdshader")

static var active_theme: Theme
static var _blur: ShaderMaterial


static func scale_from(height: float) -> float:
	if height < 64.0:
		return 1.0
	return clampf(height / 800.0, 0.85, 2.4)


static func blur_material() -> ShaderMaterial:
	if _blur == null:
		_blur = ShaderMaterial.new()
		_blur.shader = BLUR
	return _blur


static func set_panel_radius(scale: float) -> void:
	blur_material().set_shader_parameter("radius", 14.0 * scale)


static func vignette_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE
	return mat


static func panel_style(scale: float, pad_h: float = 28.0, pad_v: float = 22.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.set_corner_radius_all(int(round(14.0 * scale)))
	box.anti_aliasing = true
	var x := int(round(pad_h * scale))
	var y := int(round(pad_v * scale))
	box.content_margin_left = x
	box.content_margin_right = x
	box.content_margin_top = y
	box.content_margin_bottom = y
	return box


static func paper_style(scale: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.95, 0.94, 0.91, 0.98)
	box.set_corner_radius_all(maxi(int(round(4.0 * scale)), 2))
	box.shadow_color = Color(0, 0, 0, 0.38)
	box.shadow_size = int(round(22.0 * scale))
	box.shadow_offset = Vector2(0, 8.0 * scale)
	var side := int(round(16.0 * scale))
	box.content_margin_left = side
	box.content_margin_right = side
	box.content_margin_top = side
	box.content_margin_bottom = int(round(18.0 * scale))
	return box


static func tracked_font(spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = spacing
	return font


static func format_clock(hours: float) -> String:
	if hours >= 23.999:
		return "24:00"
	var wrapped := fposmod(hours, 24.0)
	var total := int(round(wrapped * 60.0)) % (24 * 60)
	return "%02d:%02d" % [int(float(total) / 60.0), total % 60]


static func format_distance(meters: float) -> String:
	var m := maxf(meters, 0.0)
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % int(round(m))


static func stars(count: int) -> String:
	var n := clampi(count, 0, 3)
	var out := ""
	for i in 3:
		out += "★" if i < n else "☆"
	return out


static func fade_in(node: CanvasItem, duration: float = 0.35) -> void:
	if node.has_meta(&"ui_fade"):
		var previous: Variant = node.get_meta(&"ui_fade")
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	node.set_meta(&"ui_fade", tw)


static func tween(node: Node) -> Tween:
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tw


static func make_theme(scale: float) -> Theme:
	var theme := Theme.new()
	var s := scale
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = int(round(16.0 * s))
	active_theme = theme

	var shadow := Color(0, 0, 0, 0.5)
	var shadow_px := mini(int(round(4.0 * s)), 8)
	theme.set_color("font_color", "Label", Color(1, 1, 1, 0.94))
	theme.set_color("font_shadow_color", "Label", shadow)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", maxi(int(round(s)), 1))
	theme.set_constant("shadow_outline_size", "Label", shadow_px)
	theme.set_constant("outline_size", "Label", 0)

	var pad_x := int(round(10.0 * s))
	var pad_y := int(round(8.0 * s))
	var hover := _box_fill(Color(1, 1, 1, 0.07), int(round(8.0 * s)), pad_x, pad_y)
	var pressed := _box_fill(Color(1, 1, 1, 0.12), int(round(8.0 * s)), pad_x, pad_y)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBox = hover if state == "hover" or state == "focus" else pressed if state == "pressed" else _box_empty(pad_x, pad_y)
		theme.set_stylebox(state, "Button", box)
	theme.set_color("font_color", "Button", Color(1, 1, 1, 0.92))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color(1, 1, 1, 0.78))
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	theme.set_color("font_shadow_color", "Button", shadow)
	theme.set_constant("shadow_offset_x", "Button", 0)
	theme.set_constant("shadow_offset_y", "Button", 1)
	theme.set_font_size("font_size", "Button", int(round(18.0 * s)))
	# Checkboxes stay text plus the default icon — no pill behind the label.
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		theme.set_stylebox(state, "CheckBox", _box_empty(pad_x, pad_y))
	theme.set_color("font_color", "CheckBox", Color(1, 1, 1, 0.9))
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckBox", Color.WHITE)
	theme.set_color("font_focus_color", "CheckBox", Color.WHITE)
	theme.set_color("font_disabled_color", "CheckBox", Color(1, 1, 1, 0.35))
	theme.set_color("font_shadow_color", "CheckBox", shadow)
	theme.set_font_size("font_size", "CheckBox", int(round(16.0 * s)))

	var field := _box_fill(Color(1, 1, 1, 0.08), int(round(8.0 * s)), int(round(12.0 * s)), int(round(6.0 * s)))
	var field_hover := _box_fill(Color(1, 1, 1, 0.14), int(round(8.0 * s)), int(round(12.0 * s)), int(round(6.0 * s)))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "OptionButton", field_hover if state == "hover" or state == "pressed" else field)
	theme.set_color("font_color", "OptionButton", Color(1, 1, 1, 0.94))
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	theme.set_color("font_focus_color", "OptionButton", Color.WHITE)
	theme.set_font_size("font_size", "OptionButton", int(round(16.0 * s)))

	var popup := _box_fill(Color(0.07, 0.08, 0.1, 0.96), int(round(10.0 * s)), int(round(8.0 * s)), int(round(6.0 * s)))
	var popup_hover := _box_fill(Color(1, 1, 1, 0.08), int(round(6.0 * s)), int(round(8.0 * s)), int(round(4.0 * s)))
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", Color(1, 1, 1, 0.92))
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_accelerator_color", "PopupMenu", Color(1, 1, 1, 0.45))
	theme.set_font_size("font_size", "PopupMenu", int(round(15.0 * s)))
	theme.set_constant("v_separation", "PopupMenu", int(round(4.0 * s)))

	var grab := int(round(16.0 * s))
	var track := _box_fill(Color(1, 1, 1, 0.16), int(round(3.0 * s)), 0, int(round(6.0 * s)))
	var fill := _box_fill(Color(1, 1, 1, 0.55), int(round(3.0 * s)), 0, int(round(6.0 * s)))
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme.set_icon("grabber", "HSlider", _circle(grab, Color(1, 1, 1, 0.95)))
	theme.set_icon("grabber_highlight", "HSlider", _circle(grab, Color.WHITE))
	theme.set_icon("grabber_disabled", "HSlider", _circle(grab, Color(1, 1, 1, 0.35)))
	theme.set_constant("center_grabber", "HSlider", 1)

	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "TextureButton", empty)

	theme.set_constant("separation", "VBoxContainer", int(round(10.0 * s)))
	theme.set_constant("separation", "HBoxContainer", int(round(12.0 * s)))
	return theme


static func style_popup(option: OptionButton) -> void:
	if active_theme == null:
		return
	var popup := option.get_popup()
	popup.theme = active_theme
	popup.transparent_bg = true


static func _box_empty(pad_x: int, pad_y: int) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


static func _box_fill(color: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


static func _circle(diameter: int, color: Color) -> ImageTexture:
	var d := maxi(diameter, 4)
	var image := Image.create(d, d, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := d * 0.5 - 0.75
	var center := Vector2(d * 0.5, d * 0.5)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var a := clampf(radius - dist + 0.85, 0.0, 1.0)
			if a <= 0.0:
				continue
			var px := color
			px.a *= a
			image.set_pixel(x, y, px)
	return ImageTexture.create_from_image(image)

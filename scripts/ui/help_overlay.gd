class_name HelpOverlay
extends Control
## Control card. F1 toggles it; the first drive opens it until W, Up, or 20 s.

const AUTO_SECONDS := 20.0
const ROWS := [
	["W / S", "lub strzałki — gaz / hamulec (przytrzymaj S na postoju = wsteczny)"],
	["A / D", "skręt"],
	["Spacja", "ręczny"],
	["C", "zmiana kamery (pościg, daleko, maska)"],
	["K", "tryb Kino (autopilot + filmowe ujęcia)"],
	["T", "przytrzymaj — przyspieszenie czasu, czekanie na zachód słońca"],
	["F", "zdjęcie (pocztówka, jeśli jesteś w miejscu i światło się zgadza)"],
	["Tab", "następna pocztówka"],
	["P", "tryb foto (wolna kamera: WASD, Q/E góra-dół, Shift szybciej, Spacja zdjęcie)"],
	["L", "światła ręcznie (domyślnie same się włączają o zmroku)"],
	["R", "powrót na drogę"],
	["H", "ukryj HUD, Esc — pauza (pora dnia, pogoda, tempo czasu)"],
]

var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _grid: GridContainer
var _post_title: Label
var _post: Label
var _chips: Array[PanelContainer] = []
var _keys: Array[Label] = []
var _descs: Array[Label] = []
var _automatic := false
var _left := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.025, 0.035, 0.28)
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
	_title.text = "Sterowanie"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_grid)
	for row in ROWS:
		var pair: Array = row
		_add_row(str(pair[0]), str(pair[1]))

	_post_title = Label.new()
	_post_title.text = "Pocztówki"
	_post_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_post_title)

	_post = Label.new()
	_post.text = "Dziewięć miejsc na wyspie wymaga konkretnego światła albo pogody, np. złotej godziny na klifach, niebieskiej godziny albo mgły w dolinie. Na miejsce prowadzi świetlny słup i kompas w HUD. 3 gwiazdki dostajesz, gdy warunki się zgadzają, a słońce jest w kadrze. Zdjęcia trafiają do albumu (menu → Album)."
	_post.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_post)


func apply_scale(scale: float) -> void:
	var view := get_viewport_rect().size
	var width := minf(740.0 * scale, view.x - 72.0 * scale)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(scale, 26.0, 18.0))
	_body.add_theme_constant_override("separation", int(round(8.0 * scale)))
	_title.add_theme_font_override("font", UIStyle.tracked_font(int(round(6.0 * scale))))
	_title.add_theme_font_size_override("font_size", int(round(28.0 * scale)))
	_grid.add_theme_constant_override("h_separation", int(round(14.0 * scale)))
	_grid.add_theme_constant_override("v_separation", int(round(5.0 * scale)))
	var chip_box := _chip_style(scale)
	var key_px := int(round(14.0 * scale))
	var desc_px := int(round(15.0 * scale))
	for chip in _chips:
		chip.add_theme_stylebox_override("panel", chip_box)
	for key in _keys:
		key.add_theme_font_size_override("font_size", key_px)
	for desc in _descs:
		desc.add_theme_font_size_override("font_size", desc_px)
		desc.custom_minimum_size.x = maxf(width - 210.0 * scale, 180.0 * scale)
	_post_title.add_theme_font_size_override("font_size", int(round(13.0 * scale)))
	_post_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_post.add_theme_font_size_override("font_size", int(round(14.5 * scale)))
	_post.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_post.custom_minimum_size.x = maxf(width - 52.0 * scale, 220.0 * scale)


## `automatic` closes on the first throttle key or after 20 s.
func open(automatic: bool = false) -> void:
	_automatic = automatic
	_left = AUTO_SECONDS
	visible = true
	UIStyle.fade_in(self, 0.28)


func close() -> void:
	if not visible:
		_automatic = false
		return
	_automatic = false
	if has_meta(&"ui_fade"):
		var previous: Variant = get_meta(&"ui_fade")
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	visible = false
	modulate.a = 1.0


func toggle() -> void:
	if visible:
		close()
	else:
		open(false)


func _process(delta: float) -> void:
	if not visible or not _automatic:
		return
	_left -= delta
	if _left <= 0.0:
		close()


func _input(event: InputEvent) -> void:
	if not visible or not _automatic or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_W or code == KEY_UP or key.physical_keycode == KEY_W or key.physical_keycode == KEY_UP:
		close()


func _add_row(key_text: String, desc_text: String) -> void:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := Label.new()
	key.text = key_text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(key)
	var desc := Label.new()
	desc.text = desc_text
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(chip)
	_grid.add_child(desc)
	_chips.append(chip)
	_keys.append(key)
	_descs.append(desc)


func _chip_style(scale: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.1)
	box.set_corner_radius_all(maxi(int(round(6.0 * scale)), 3))
	box.anti_aliasing = true
	var x := int(round(10.0 * scale))
	var y := int(round(3.0 * scale))
	box.content_margin_left = x
	box.content_margin_right = x
	box.content_margin_top = y
	box.content_margin_bottom = y
	return box

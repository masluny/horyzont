class_name Hud
extends Control
## Driving readout. Dims itself when the player leaves it alone.

var _speed: Label
var _unit: Label
var _gear: Label
var _clock: Label
var _phase: Label
var _weather: Label
var _objective: HBoxContainer
var _objective_label: Label
var _distance: Label
var _arrow: Arrow
var _fps: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _dim_tween: Tween
var _speed_box: VBoxContainer
var _clock_box: VBoxContainer

var _target := Vector3.ZERO
var _has_target := false
var _prev_elev := 0.0
var _have_elev := false
var _rising := false
var _idle := 0.0
var _dimmed := false
var _scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_speed_box = VBoxContainer.new()
	_speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_box.add_theme_constant_override("separation", 0)
	_speed = _make_label("0")
	_unit = _make_label("km/h")
	_gear = _make_label("N")
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_constant_override("separation", 14)
	_unit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_unit)
	meta.add_child(_gear)
	_speed_box.add_child(_speed)
	_speed_box.add_child(meta)
	add_child(_speed_box)

	_clock_box = VBoxContainer.new()
	_clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_box.add_theme_constant_override("separation", 2)
	_clock = _make_label("00:00")
	_phase = _make_label("")
	_weather = _make_label("")
	for lab in [_clock, _phase, _weather]:
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_clock_box.add_child(lab)
	add_child(_clock_box)

	_objective = HBoxContainer.new()
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.visible = false
	_arrow = Arrow.new()
	_objective_label = _make_label("")
	_distance = _make_label("")
	_objective.add_child(_arrow)
	_objective.add_child(_objective_label)
	_objective.add_child(_distance)
	add_child(_objective)

	_fps = _make_label("")
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.visible = false
	add_child(_fps)

	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.material = UIStyle.blur_material()
	_toast.visible = false
	_toast_label = _make_label("")
	_toast.add_child(_toast_label)
	add_child(_toast)


func apply_scale(scale: float) -> void:
	_scale = scale
	var margin := 44.0 * scale
	_pin(_speed_box, 0.0, 1.0, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN, margin)
	_pin(_clock_box, 1.0, 1.0, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN, margin)
	_pin(_objective, 0.0, 0.0, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END, margin)
	_pin(_fps, 1.0, 0.0, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END, margin)
	_pin_top_center(_toast, margin)

	_speed.add_theme_font_size_override("font_size", int(round(80.0 * scale)))
	_speed.add_theme_constant_override("shadow_outline_size", int(round(10.0 * scale)))
	_unit.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	_unit.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_gear.add_theme_font_size_override("font_size", int(round(26.0 * scale)))
	_clock.add_theme_font_size_override("font_size", int(round(32.0 * scale)))
	_phase.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_phase.add_theme_color_override("font_color", Color(1, 0.96, 0.9, 0.9))
	_weather.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
	_weather.add_theme_color_override("font_color", Color(1, 1, 1, 0.66))
	_objective_label.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_distance.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_distance.add_theme_color_override("font_color", Color(1, 1, 1, 0.66))
	_fps.add_theme_font_size_override("font_size", int(round(13.0 * scale)))
	_fps.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_toast_label.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
	_toast.add_theme_stylebox_override("panel", UIStyle.panel_style(scale, 18.0, 10.0))
	_objective.add_theme_constant_override("separation", int(round(12.0 * scale)))
	_speed_box.add_theme_constant_override("separation", int(round(2.0 * scale)))
	_arrow.set_box(22.0 * scale)


func show_toast(text: String, seconds: float = 3.0) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = UIStyle.tween(self)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_toast_tween.finished.connect(func() -> void: _toast.visible = false, CONNECT_ONE_SHOT)
	wake()


func set_objective(text: String, target: Vector3) -> void:
	_objective_label.text = text
	_target = target
	_has_target = true
	_objective.visible = true
	wake()


func clear_objective() -> void:
	_has_target = false
	_objective.visible = false


func wake() -> void:
	_idle = 0.0
	_set_dim(false)


func fade_in() -> void:
	_dimmed = false
	_idle = 0.0
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	modulate.a = 0.0
	_dim_tween = UIStyle.tween(self)
	_dim_tween.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() < 1.5:
		return
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.15:
		return
	if event is InputEventKey and not (event as InputEventKey).pressed:
		return
	wake()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_car()
	_refresh_world()
	_refresh_objective()
	_fps.visible = Settings.show_fps
	if Settings.show_fps:
		_fps.text = "%d FPS" % int(Engine.get_frames_per_second())
	_idle += delta
	if _idle >= 6.0:
		_set_dim(true)


func _refresh_car() -> void:
	var speed := 0.0
	var gear := 0
	var reversing := false
	var car: Variant = _game().car
	if car != null:
		speed = float(car.speed_kmh)
		gear = int(car.gear)
		reversing = bool(car.is_reversing)
	_speed.text = str(int(round(absf(speed))))
	_gear.text = _gear_name(gear, reversing)


func _refresh_world() -> void:
	var game: Variant = _game()
	if game.clock != null:
		_clock.text = UIStyle.format_clock(game.clock.time)
		_phase.text = _light_phase(game.clock.sun_elevation_deg())
	else:
		_clock.text = "--:--"
		_phase.text = ""
	_weather.text = game.weather.preset_name() if game.weather != null else ""


## >6 Dzień, 0..6 Złota godzina, -4..0 Wschód/Zachód, -8..-4 Niebieska godzina, else Noc.
func _light_phase(elev: float) -> String:
	if not _have_elev:
		_have_elev = true
		_prev_elev = elev
		var clock: Variant = _game().clock
		_rising = clock != null and clock.time < 12.0
	elif absf(elev - _prev_elev) > 0.002:
		_rising = elev > _prev_elev
		_prev_elev = elev
	if elev > 6.0:
		return "Dzień"
	if elev >= 0.0:
		return "Złota godzina"
	if elev >= -4.0:
		return "Wschód" if _rising else "Zachód"
	if elev >= -8.0:
		return "Niebieska godzina"
	return "Noc"


func _refresh_objective() -> void:
	if not _has_target:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_distance.text = ""
		_arrow.rotation = 0.0
		return
	var meters := cam.global_position.distance_to(_target)
	_distance.text = UIStyle.format_distance(meters)
	var flat := _target - cam.global_position
	flat.y = 0.0
	if flat.length() < 0.5:
		_arrow.rotation = 0.0
		return
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	# Screen rotation is clockwise; the world angle around +Y is the other way.
	var angle := forward.signed_angle_to(flat.normalized(), Vector3.UP)
	_arrow.rotation = -angle


func _set_dim(dimmed: bool) -> void:
	if dimmed == _dimmed:
		return
	_dimmed = dimmed
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = UIStyle.tween(self)
	var target := 0.35 if dimmed else 1.0
	_dim_tween.tween_property(self, "modulate:a", target, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _gear_name(gear: int, reversing: bool) -> String:
	if reversing or gear < 0:
		return "R"
	if gear <= 0:
		return "N"
	return str(clampi(gear, 1, 6))


func _game() -> Variant:
	return get_tree().root.get_node("Game")


func _make_label(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lab


func _pin(node: Control, ax: float, ay: float, grow_h: Control.GrowDirection, grow_v: Control.GrowDirection, margin: float) -> void:
	node.anchor_left = ax
	node.anchor_right = ax
	node.anchor_top = ay
	node.anchor_bottom = ay
	var x := margin if ax < 0.5 else -margin
	var y := margin if ay < 0.5 else -margin
	node.offset_left = x
	node.offset_right = x
	node.offset_top = y
	node.offset_bottom = y
	node.grow_horizontal = grow_h
	node.grow_vertical = grow_v


func _pin_top_center(node: Control, margin: float) -> void:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = 0.0
	node.offset_right = 0.0
	node.offset_top = margin
	node.offset_bottom = margin
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_END


class Arrow extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(18, 18)

	func _ready() -> void:
		resized.connect(_center)
		_center()

	func set_box(px: float) -> void:
		custom_minimum_size = Vector2(px, px)
		_center()

	func _center() -> void:
		pivot_offset = size * 0.5

	func _draw() -> void:
		var c := size * 0.5
		var h := size.y * 0.46
		var w := size.x * 0.32
		var pts := PackedVector2Array([
			c + Vector2(0, -h),
			c + Vector2(w, h * 0.7),
			c + Vector2(0, h * 0.28),
			c + Vector2(-w, h * 0.7),
		])
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(0, 1.5))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
		draw_colored_polygon(pts, Color(1, 1, 1, 0.95))

class_name CameraRig
extends Camera3D
## Chase, bonnet and cinematic cameras for the car, plus a free photo camera.

enum Mode { CHASE, CHASE_FAR, BONNET, CINEMATIC, PHOTO }

const SHOT_SECONDS := 10.0

var mode := Mode.CHASE
var target: Car
var terrain: TerrainData
var mouse_sensitivity := 1.0

var _dir := Vector3.FORWARD
var _pos := Vector3.ZERO
var _orbit := Vector2.ZERO
var _orbit_idle := 0.0
var _shot := -1
var _shot_time := 0.0
var _anchor := Vector3.ZERO
var _anchor_side := 1.0
var _photo_yaw := 0.0
var _photo_pitch := 0.0
var _initialised := false


func _ready() -> void:
	far = 40000.0
	near = 0.08
	fov = 62.0
	process_priority = 500


func set_mode(m: Mode) -> void:
	mode = m
	_shot = -1
	if m == Mode.PHOTO:
		var e := global_transform.basis.get_euler()
		_photo_pitch = e.x
		_photo_yaw = e.y


func cycle_mode() -> void:
	var order := [Mode.CHASE, Mode.CHASE_FAR, Mode.BONNET]
	var i := order.find(mode)
	set_mode(order[(i + 1) % order.size()])


func snap() -> void:
	_initialised = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = event.relative * 0.003 * mouse_sensitivity
		if mode == Mode.PHOTO:
			_photo_yaw -= d.x
			_photo_pitch = clampf(_photo_pitch - d.y, -1.4, 1.4)
		else:
			_orbit.x -= d.x
			_orbit.y = clampf(_orbit.y - d.y, -0.6, 0.5)
			_orbit_idle = 0.0


func _process(delta: float) -> void:
	if target == null:
		return
	match mode:
		Mode.CHASE:
			_chase(delta, 6.4, 1.85)
		Mode.CHASE_FAR:
			_chase(delta, 10.5, 3.0)
		Mode.BONNET:
			_bonnet()
		Mode.CINEMATIC:
			_cinematic(delta)
		Mode.PHOTO:
			_photo(delta)
	_keep_above_ground()


func _flat_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else _dir


func _chase(delta: float, dist: float, height: float) -> void:
	var f := _flat_forward()
	var car_pos := target.global_position
	if not _initialised:
		_dir = f
		_pos = car_pos - f * dist + Vector3.UP * height
		_initialised = true
	# Rotational lag gives a sense of weight in corners.
	_dir = _dir.slerp(f, 1.0 - exp(-delta * 3.5)).normalized()
	_orbit_idle += delta
	if _orbit_idle > 2.5:
		_orbit = _orbit.lerp(Vector2.ZERO, 1.0 - exp(-delta * 2.0))
	var d := _dir.rotated(Vector3.UP, _orbit.x)
	var speed := target.speed_kmh
	var want := car_pos - d * (dist + speed * 0.012) + Vector3.UP * (height + _orbit.y * -4.0)
	_pos = _pos.lerp(want, 1.0 - exp(-delta * 9.0))
	global_position = _pos
	look_at(car_pos + Vector3.UP * 0.9 + d * 2.5)
	fov = lerpf(fov, 60.0 + clampf(speed / 180.0, 0.0, 1.0) * 12.0, 1.0 - exp(-delta * 3.0))


func _bonnet() -> void:
	var xf := target.global_transform
	global_position = xf * Vector3(0.0, 0.82, -0.35)
	look_at(xf * Vector3(0.0, 0.7, -12.0), xf.basis.y)
	fov = 66.0


func _cinematic(delta: float) -> void:
	_shot_time -= delta
	if _shot < 0 or _shot_time <= 0.0:
		_next_shot()
	var car_pos := target.global_position + Vector3.UP * 0.7
	var f := _flat_forward()
	var right := f.cross(Vector3.UP)
	match _shot:
		0: # Tracking alongside, low.
			var want := car_pos + right * 6.5 * _anchor_side - f * 1.5 + Vector3.UP * 0.6
			_pos = _pos.lerp(want, 1.0 - exp(-delta * 4.0))
			global_position = _pos
			look_at(car_pos)
			fov = 50.0
		1, 4: # Fixed roadside camera; the car drives past.
			global_position = _anchor
			look_at(car_pos)
			fov = lerpf(fov, clampf(900.0 / maxf(_anchor.distance_to(car_pos), 10.0), 14.0, 55.0), 1.0 - exp(-delta * 1.5))
		2: # Drone, slow orbit.
			_orbit.x += delta * 0.06
			var want := car_pos + f.rotated(Vector3.UP, PI + _orbit.x) * 34.0 + Vector3.UP * 22.0
			_pos = _pos.lerp(want, 1.0 - exp(-delta * 1.5))
			global_position = _pos
			look_at(car_pos)
			fov = 55.0
		3: # Leading the car, looking back.
			var want := car_pos + f * 8.0 + right * 1.2 * _anchor_side + Vector3.UP * 0.4
			_pos = _pos.lerp(want, 1.0 - exp(-delta * 5.0))
			global_position = _pos
			look_at(car_pos)
			fov = 48.0


func _next_shot() -> void:
	var prev := _shot
	while _shot == prev:
		_shot = randi() % 5
	_shot_time = SHOT_SECONDS
	_anchor_side = -1.0 if randf() < 0.5 else 1.0
	var car_pos := target.global_position
	var f := _flat_forward()
	var right := f.cross(Vector3.UP)
	_pos = car_pos - f * 8.0 + Vector3.UP * 2.0
	if _shot == 1:
		var ahead := car_pos + f * maxf(target.speed_kmh, 30.0) * 0.18
		_anchor = ahead + right * 9.0 * _anchor_side + Vector3.UP * 1.6
	elif _shot == 4:
		# Long lens from far off the road, placed so the sun sits behind the car.
		var sun := Game.clock.sun_dir if Game.clock else Vector3.UP
		var away := Vector3(-sun.x, 0.0, -sun.z)
		if away.length() < 0.1 or sun.y < -0.15:
			away = right
		away = away.normalized()
		_anchor = car_pos + f * 120.0 + away * 160.0
		if terrain:
			_anchor.y = maxf(_anchor.y, terrain.height_at(_anchor.x, _anchor.z) + 8.0)
	elif _shot == 2:
		_orbit.x = randf() * TAU


func _photo(delta: float) -> void:
	var b := Basis.from_euler(Vector3(_photo_pitch, _photo_yaw, 0.0))
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move -= b.z
	if Input.is_physical_key_pressed(KEY_S): move += b.z
	if Input.is_physical_key_pressed(KEY_A): move -= b.x
	if Input.is_physical_key_pressed(KEY_D): move += b.x
	if Input.is_physical_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): move -= Vector3.UP
	var speed := 25.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
	global_position += move * speed * delta
	global_basis = b


func _keep_above_ground() -> void:
	if terrain == null:
		return
	var g := terrain.height_at(global_position.x, global_position.z)
	if global_position.y < g + 0.6:
		global_position.y = g + 0.6
	if global_position.y < 0.8:
		global_position.y = 0.8

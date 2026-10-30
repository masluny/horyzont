class_name Car
extends RigidBody3D
## Raycast vehicle: spring/damper suspension, a simple slip-based tyre model,
## automatic six-speed gearbox, light driving assists and an autopilot that
## follows the island road (used by "Kino" mode).

signal reset_done

const WHEEL_RADIUS := 0.34
const REST_LENGTH := 0.36
const SPRING := 42000.0
const DAMP_BUMP := 3600.0
const DAMP_REBOUND := 4600.0
const ANTIROLL := 9000.0
const MU := 1.15
const IDLE_RPM := 850.0
const MAX_RPM := 6900.0
const GEARS := [3.55, 2.15, 1.48, 1.13, 0.92, 0.76]
const REVERSE_RATIO := 3.3
const FINAL_DRIVE := 3.85
const BRAKE_FORCE := 15000.0
const MAX_STEER := deg_to_rad(31.0)

## Wheel mount points (local, at the top of the suspension travel).
const MOUNTS := [Vector3(-0.78, 0.36, -1.32), Vector3(0.78, 0.36, -1.32), Vector3(-0.79, 0.36, 1.28), Vector3(0.79, 0.36, 1.28)]

var speed_kmh := 0.0
var rpm := IDLE_RPM
var gear := 1
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var slip := 0.0
var is_reversing := false
var autopilot := false
var controls_enabled := true
var autopilot_speed := 78.0
var headlights_on := false
var headlights_auto := true

var model: CarModel
var terrain: TerrainData

var _wheel_compress: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_contact: Array[bool] = [false, false, false, false]
var _wheel_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _steer_smooth := 0.0
var _shift_timer := 0.0
var _road_index := 0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	mass = 1280.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.18, 0.05)
	inertia = Vector3(1900.0, 2300.0, 650.0)
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.15
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.78, 0.55, 4.3)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.3, 0)
	add_child(cs)
	var cabin := BoxShape3D.new()
	cabin.size = Vector3(1.4, 0.45, 2.0)
	var cs2 := CollisionShape3D.new()
	cs2.shape = cabin
	cs2.position = Vector3(0, 0.8, 0.3)
	add_child(cs2)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	pm.bounce = 0.05
	physics_material_override = pm
	_ray.exclude = [get_rid()]
	_ray.collide_with_areas = false
	model = CarModel.new()
	add_child(model)
	if not Game.args.has("shots") and not Game.args.has("mute"):
		var audio := CarAudio.new()
		audio.name = "Audio"
		add_child(audio)
	Game.car = self


func place_on_road(index: int, lane_offset := 1.9) -> void:
	if terrain == null:
		return
	var p := terrain.road_point(index)
	var t := terrain.road_tangent(index)
	var right := t.cross(Vector3.UP).normalized()
	var pos := p + right * lane_offset + Vector3.UP * 0.25
	global_transform = Transform3D(Basis.looking_at(t, Vector3.UP), pos)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_road_index = index
	reset_done.emit()


func reset_to_road() -> void:
	if terrain:
		place_on_road(terrain.nearest_road_index(global_position))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				reset_to_road()
			KEY_L:
				headlights_auto = false
				headlights_on = not headlights_on


func _physics_process(delta: float) -> void:
	_read_input(delta)
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var v := linear_velocity
	var forward_speed := v.dot(fwd)
	speed_kmh = absf(forward_speed) * 3.6
	is_reversing = forward_speed < -0.5 and gear == -1

	# Speed-sensitive steering.
	var steer_limit := MAX_STEER * lerpf(1.0, 0.16, pow(clampf(speed_kmh / 150.0, 0.0, 1.0), 0.8))
	_steer_smooth = move_toward(_steer_smooth, steer * steer_limit, delta * 2.2)

	# Engine and gearbox.
	var wheel_rpm := absf(forward_speed) / WHEEL_RADIUS * 60.0 / TAU
	var ratio: float = (REVERSE_RATIO if gear == -1 else GEARS[gear - 1]) * FINAL_DRIVE
	var engine_rpm := maxf(IDLE_RPM, wheel_rpm * ratio)
	_auto_shift(engine_rpm, delta, forward_speed)
	ratio = (REVERSE_RATIO if gear == -1 else GEARS[gear - 1]) * FINAL_DRIVE
	engine_rpm = clampf(wheel_rpm * ratio, IDLE_RPM, MAX_RPM)
	rpm = lerpf(rpm, engine_rpm + throttle * 250.0 * (1.0 if speed_kmh < 8.0 else 0.0), 1.0 - exp(-delta * 12.0))
	var torque := _torque_curve(engine_rpm) * throttle
	if gear == -1 and speed_kmh > 22.0:
		torque = 0.0
	if engine_rpm >= MAX_RPM - 50.0:
		torque = 0.0
	if _shift_timer > 0.0:
		torque *= 0.25
	var drive_force := torque * ratio / WHEEL_RADIUS * 0.9 * (-1.0 if gear == -1 else 1.0)

	var state := get_world_3d().direct_space_state
	var total_slip := 0.0
	var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var hits := []
	for i in 4:
		var mount: Vector3 = xf * MOUNTS[i]
		_ray.from = mount
		_ray.to = mount - up * (REST_LENGTH + WHEEL_RADIUS)
		var hit := state.intersect_ray(_ray)
		hits.append(hit)
		if hit.is_empty():
			_wheel_contact[i] = false
			_wheel_compress[i] = 0.0
			continue
		var dist: float = mount.distance_to(hit.position)
		var compress := REST_LENGTH + WHEEL_RADIUS - dist
		var comp_vel := (compress - _wheel_compress[i]) / delta
		_wheel_compress[i] = compress
		_wheel_contact[i] = true
		var damp := DAMP_BUMP if comp_vel > 0.0 else DAMP_REBOUND
		loads[i] = maxf(0.0, compress * SPRING + comp_vel * damp)

	# Anti-roll bars.
	for axle in 2:
		var l := axle * 2
		var r := l + 1
		var diff := (_wheel_compress[l] - _wheel_compress[r]) * ANTIROLL
		if _wheel_contact[l]:
			loads[l] += diff
		if _wheel_contact[r]:
			loads[r] -= diff

	for i in 4:
		if not _wheel_contact[i]:
			continue
		var hit: Dictionary = hits[i]
		var n: Vector3 = hit.normal
		var contact: Vector3 = hit.position
		var fz := maxf(loads[i], 0.0)
		apply_force(up * fz, contact - global_position)

		var front := i < 2
		var wheel_basis := xf.basis
		if front:
			wheel_basis = wheel_basis.rotated(up, -_steer_smooth)
		var wf := (-wheel_basis.z - n * (-wheel_basis.z).dot(n)).normalized()
		var wr := wf.cross(n).normalized()
		var pv := linear_velocity + angular_velocity.cross(contact - global_position)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(wr)

		var grip := MU * fz
		var rear_grip := 0.55 if (Input.is_action_pressed("handbrake") and controls_enabled and not autopilot) else 1.0
		if not front:
			grip *= rear_grip
		# Lateral: Pacejka-like curve of the slip angle, damped at low speed.
		var alpha := atan2(v_lat, maxf(absf(v_long), 2.5))
		var f_lat := -grip * sin(1.45 * atan(9.0 * alpha))
		# Longitudinal: drive (AWD 35/65) and brakes.
		var f_long := drive_force * (0.175 if front else 0.325)
		var brake_share := 0.62 if front else 0.38
		var bf := brake * BRAKE_FORCE * brake_share * 0.5
		f_long -= clampf(v_long * 400.0, -bf, bf)
		f_long -= v_long * 12.0
		var total := Vector2(f_long, f_lat)
		var excess := total.length() / maxf(grip, 1.0)
		if excess > 1.0:
			total /= excess
		total_slip += clampf(excess - 0.85, 0.0, 1.0) + clampf(absf(alpha) * 2.0 - 0.3, 0.0, 1.0)
		var apply_at := contact + up * 0.25 - global_position
		apply_force(wf * total.x + wr * total.y, apply_at)
		_wheel_spin[i] += v_long / WHEEL_RADIUS * delta

	slip = clampf(total_slip / 4.0, 0.0, 1.0)

	# Aerodynamics, gentle downforce and yaw stabilisation.
	var drag := -v * v.length() * 0.39
	apply_central_force(drag - up * v.length_squared() * 0.9)
	var grounded := _wheel_contact.count(true)
	if grounded >= 2:
		# Stability assist: steer the yaw rate toward what the tyres can deliver.
		var yaw_rate := angular_velocity.dot(up)
		var max_yaw := 8.5 / maxf(absf(forward_speed), 3.0)
		var desired := clampf(-forward_speed * tan(_steer_smooth) / 2.6, -max_yaw, max_yaw)
		apply_torque(up * (desired - yaw_rate) * 2600.0 * clampf(speed_kmh / 40.0, 0.0, 1.0))
		# Kill sideways drift that the tyres alone would let build up.
		var lat := linear_velocity.dot(xf.basis.x)
		apply_central_force(-xf.basis.x * lat * 220.0 * clampf(speed_kmh / 30.0, 0.0, 1.0))
	else:
		# Keep the car upright-ish in the air.
		var tilt := up.cross(Vector3.UP)
		apply_torque(tilt * 4000.0 - angular_velocity * 600.0)

	if headlights_auto and Game.clock:
		var dark := Game.clock.sun_elevation_deg() < -1.0 or (Game.weather and (Game.weather.rain > 0.3 or Game.weather.value("fog") > 0.0006))
		headlights_on = dark
	if model:
		model.update_wheels(_wheel_compress, _wheel_spin, _steer_smooth, REST_LENGTH, WHEEL_RADIUS)
		model.set_brake_lights(brake > 0.05)
		model.set_headlights(headlights_on)


func _read_input(delta: float) -> void:
	if autopilot:
		_autopilot(delta)
		return
	if not controls_enabled:
		throttle = 0.0
		brake = 1.0
		steer = 0.0
		return
	var acc := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var fwd_speed := linear_velocity.dot(-global_transform.basis.z)
	# Brake pedal becomes reverse once stopped.
	if gear == -1:
		throttle = brk
		brake = acc
		if acc > 0.1 and fwd_speed > -0.5:
			gear = 1
	else:
		throttle = acc
		brake = brk
		if brk > 0.1 and fwd_speed < 0.8 and acc < 0.1:
			gear = -1
	if Input.is_action_pressed("handbrake"):
		brake = maxf(brake, 0.3)


func _auto_shift(engine_rpm: float, delta: float, fwd_speed: float) -> void:
	_shift_timer = maxf(0.0, _shift_timer - delta)
	if gear == -1 or _shift_timer > 0.0:
		return
	var up_rpm := lerpf(3200.0, 6300.0, throttle)
	if engine_rpm > up_rpm and gear < GEARS.size():
		gear += 1
		_shift_timer = 0.22
	elif gear > 1:
		var lower_rpm: float = engine_rpm * GEARS[gear - 2] / GEARS[gear - 1]
		if lower_rpm < lerpf(2600.0, 4800.0, throttle) and fwd_speed > 0.0:
			gear -= 1
			_shift_timer = 0.2


func _torque_curve(r: float) -> float:
	var x := clampf((r - IDLE_RPM) / (MAX_RPM - IDLE_RPM), 0.0, 1.0)
	return 190.0 + 120.0 * sin(x * PI * 0.95) - 40.0 * x * x


func _autopilot(delta: float) -> void:
	if terrain == null:
		return
	var pos := global_position
	var n := terrain.road_points.size()
	# Track progress along the road without searching the whole loop.
	var best := _road_index
	var best_d := INF
	for k in range(-6, 30):
		var j := posmod(_road_index + k, n)
		var d := terrain.road_point(j).distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = j
	_road_index = best
	if best_d > 400.0:
		_road_index = terrain.nearest_road_index(pos)
	var fwd_speed := linear_velocity.dot(-global_transform.basis.z)
	var look := int(clampf(6.0 + absf(fwd_speed) * 0.55, 6.0, 30.0) / TerrainData.ROAD_STEP) + 2
	var i := _road_index + look
	var tgt := terrain.road_point(i) + terrain.road_tangent(i).cross(Vector3.UP).normalized() * 1.9
	var to := tgt - pos
	var local := global_transform.basis.inverse() * to
	var heading_err := atan2(local.x, -local.z)
	steer = clampf(heading_err * 2.4, -1.0, 1.0)
	# Slow down for curves ahead.
	var curv := 0.0
	for k in range(4, 40, 4):
		var t0 := terrain.road_tangent(_road_index + k)
		var t1 := terrain.road_tangent(_road_index + k + 4)
		curv = maxf(curv, t0.angle_to(t1) / (4.0 * TerrainData.ROAD_STEP))
	var v_curve := sqrt(3.2 / maxf(curv, 1e-4)) * 3.6
	var target := minf(autopilot_speed, v_curve)
	var err := target - speed_kmh
	throttle = clampf(err * 0.08, 0.0, 0.85)
	brake = clampf(-err * 0.06, 0.0, 0.7)
	if gear == -1:
		gear = 1

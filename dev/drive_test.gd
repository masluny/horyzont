extends Node
# Simulated player input: accelerate, corner, brake, reverse. Prints telemetry.
func _ready() -> void:
	while Game.car == null or Game.terrain == null or not Game.terrain.is_ready:
		await get_tree().process_frame
	var car: Car = Game.car
	Game.world.set_cinema(false)
	car.controls_enabled = true
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_msec()
	Input.action_press("accelerate")
	for i in 8:
		await get_tree().create_timer(1.0).timeout
		print("DRV t=%d v=%.1f gear=%d rpm=%.0f" % [i + 1, car.speed_kmh, car.gear, car.rpm])
	Input.action_press("steer_right", 0.6)
	for i in 3:
		await get_tree().create_timer(0.5).timeout
		var up := car.global_transform.basis.y
		print("DRV steer v=%.1f yaw=%.2f roll=%.1f slip=%.2f" % [car.speed_kmh, car.angular_velocity.y, rad_to_deg(asin(clampf(up.dot(car.global_transform.basis.x), -1, 1))), car.slip])
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	Input.action_press("brake")
	var tb := Time.get_ticks_msec()
	while car.speed_kmh > 1.0 and Time.get_ticks_msec() - tb < 8000:
		await get_tree().process_frame
	print("DRV brake to stop in %.2fs" % ((Time.get_ticks_msec() - tb) / 1000.0))
	await get_tree().create_timer(2.0).timeout
	print("DRV reverse v=%.1f gear=%d" % [car.speed_kmh, car.gear])
	Input.action_release("brake")
	var up2 := car.global_transform.basis.y
	print("DRV upright=%.2f pos=%s" % [up2.y, car.global_position])
	get_tree().quit()

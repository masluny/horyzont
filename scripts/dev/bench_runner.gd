class_name BenchRunner
extends Node
## Drives the car in cinema mode and records frame and GPU times.
## godot --path . -- --bench=30 [--time=19.5 --weather=cumulusy --mode=chase]

var _frames: PackedFloat32Array = []
var _gpu: PackedFloat32Array = []
var _cpu: PackedFloat32Array = []


func run(seconds: float) -> void:
	if not Game.sky.is_baked:
		await Game.sky.baked
	var world = Game.world
	world.set_cinema(true)
	if Game.args.has("mode") and Game.arg("mode") == "chase":
		world.camera.set_mode(CameraRig.Mode.CHASE)
	Game.clock.paused = true
	if Game.args.has("road_near"):
		var at := Game.vec3_arg("road_near", Vector3.ZERO)
		world.car.place_on_road(world.terrain.nearest_road_index(at))
	if Game.args.has("uncapped"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	# Warm-up (shader compilation, streaming).
	for i in 120:
		await get_tree().process_frame
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frames.append((now - last) / 1000.0)
		last = now
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_report()
	get_tree().quit()


func _report() -> void:
	var f := _frames.duplicate()
	f.sort()
	var n := f.size()
	var avg := 0.0
	for x in f:
		avg += x
	avg /= n
	var gavg := 0.0
	for x in _gpu:
		gavg += x
	gavg /= _gpu.size()
	var cavg := 0.0
	for x in _cpu:
		cavg += x
	cavg /= _cpu.size()
	var size := get_viewport().get_visible_rect().size
	print("BENCH res=%dx%d scale=%.2f frames=%d avg=%.2fms (%.1f fps) p50=%.2f p95=%.2f p99=%.2f gpu=%.2fms render_cpu=%.2fms" % [
		size.x, size.y, get_viewport().scaling_3d_scale, n, avg, 1000.0 / avg, f[n / 2], f[int(n * 0.95)], f[int(n * 0.99)], gavg, cavg])

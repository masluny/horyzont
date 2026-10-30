class_name CarAudio
extends Node3D
## Procedural car audio. Engine, wind, road, tyre squeal and rain are synthesized
## into AudioStreamGenerators — there are no audio files.

const MIX_RATE := 22050.0
const BUFFER_LENGTH := 0.12
const SINE_SIZE := 2048
const SINE_MASK := 2047
const PHASE_MASK := 0xFFFFFFFF
const INDEX_SHIFT := 21
const PHASE_PER_HZ := 4294967296.0 / MIX_RATE
const MAX_FRAMES := 4096
const NOISE_SCALE := 2.0 / 65535.0

# One-pole coefficients at MIX_RATE: 1 - exp(-2π fc / sr).
const INTAKE_A := 0.1078 # ~400 Hz
const WIND_HI_A := 0.3479 # ~1500 Hz
const WIND_LO_A := 0.0688 # ~250 Hz
const ROAD_A := 0.0225 # ~80 Hz
const HISS_A := 0.4955 # ~2400 Hz
const RAIN_A := 0.4345 # ~2000 Hz
const SQUEAL_A := 0.0285 # pitch flutter ~100 Hz

const HARM_SOFT: Array[float] = [0.72, 0.20, 0.06, 0.015, 0.004, 0.001]
const HARM_BRIGHT: Array[float] = [0.30, 0.26, 0.20, 0.13, 0.07, 0.04]

static var _sine := PackedFloat32Array()

var rpm := 800.0
var throttle := 0.0
var speed_kmh := 0.0
var slip := 0.0
var rain := 0.0
var wet := 0.0
var master_volume := 1.0
var muted := false
var auto_from_game := true

var _engine: AudioStreamPlayer3D
var _body: AudioStreamPlayer3D
var _pb_engine: AudioStreamGeneratorPlayback
var _pb_body: AudioStreamGeneratorPlayback
var _buf_engine := PackedVector2Array()
var _buf_body := PackedVector2Array()

var _rpm_s := 800.0
var _thr_s := 0.0
var _spd_s := 0.0
var _slip_s := 0.0
var _rain_s := 0.0
var _wet_s := 0.0
var _master_s := 1.0

var _ph1 := 0
var _ph2 := 0
var _rng_e := 0x1A2B3C4
var _rng_b := 0x5D6E7F8
var _intake := 0.0
var _crack := 0.0
var _wind_hi := 0.0
var _wind_lo := 0.0
var _road_lp := 0.0
var _hiss_lp := 0.0
var _sq_lp := 0.0
var _sq_ph := 0
var _sq_base := 0
var _sq_mod := 0
var _rain_lp := 0.0
var _click := 0.0

var _a1 := 0.0
var _a2 := 0.0
var _a3 := 0.0
var _a4 := 0.0
var _a5 := 0.0
var _a6 := 0.0
var _a1_t := 0.0
var _a2_t := 0.0
var _a3_t := 0.0
var _a4_t := 0.0
var _a5_t := 0.0
var _a6_t := 0.0
var _eng_g := 0.0
var _eng_g_t := 0.0
var _intake_g := 0.0
var _intake_g_t := 0.0
var _wind_g := 0.0
var _wind_g_t := 0.0
var _road_g := 0.0
var _road_g_t := 0.0
var _hiss_g := 0.0
var _hiss_g_t := 0.0
var _sq_g := 0.0
var _sq_g_t := 0.0
var _rain_g := 0.0
var _rain_g_t := 0.0
var _overrun := 0.0
var _inc1 := 0
var _inc2 := 0
var _crack_gate := 0
var _rain_gate := 0
var _max_us := 0


static func _build_sine() -> void:
	if _sine.size() == SINE_SIZE:
		return
	_sine.resize(SINE_SIZE)
	var step := TAU / float(SINE_SIZE)
	for i in SINE_SIZE:
		_sine[i] = sin(float(i) * step)


func _ready() -> void:
	_build_sine()
	_sq_base = _hz_to_inc(800.0)
	_sq_mod = _hz_to_inc(100.0)
	_buf_engine.resize(MAX_FRAMES)
	_buf_body.resize(MAX_FRAMES)
	_engine = _add_voice("Engine")
	_body = _add_voice("Body")
	_pull_smoothed_from_public()
	_update_targets()


func _exit_tree() -> void:
	if _engine != null and _engine.playing:
		_engine.stop()
	if _body != null and _body.playing:
		_body.stop()
	_pb_engine = null
	_pb_body = null


func _process(delta: float) -> void:
	_read_game()
	var dt := delta if delta > 0.0 else 0.0
	_rpm_s = _smooth(_rpm_s, clampf(rpm, 0.0, 12000.0), dt, 0.05)
	_thr_s = _smooth(_thr_s, clampf(throttle, 0.0, 1.0), dt, 0.035)
	_spd_s = _smooth(_spd_s, maxf(speed_kmh, 0.0), dt, 0.06)
	_slip_s = _smooth(_slip_s, clampf(slip, 0.0, 1.0), dt, 0.03)
	_rain_s = _smooth(_rain_s, clampf(rain, 0.0, 1.0), dt, 0.12)
	_wet_s = _smooth(_wet_s, clampf(wet, 0.0, 1.0), dt, 0.18)
	var master_target := 0.0 if muted else maxf(master_volume, 0.0)
	_master_s = _smooth(_master_s, master_target, dt, 0.03)
	_update_targets()
	if not _playbacks_ready():
		return
	var frames_available := _pb_engine.get_frames_available()
	frames_available = mini(frames_available, _pb_body.get_frames_available())
	if frames_available > MAX_FRAMES:
		frames_available = MAX_FRAMES
	if frames_available <= 0:
		return
	var t0 := Time.get_ticks_usec()
	_fill(frames_available)
	var us := Time.get_ticks_usec() - t0
	if us > _max_us:
		_max_us = us
	if Engine.get_process_frames() % 60 == 0:
		print("CAR_US ", us, " max ", _max_us, " n ", frames_available)


func _read_game() -> void:
	if not auto_from_game or not is_inside_tree():
		return
	var game := get_node_or_null("/root/Game")
	if game == null:
		return
	var car := game.get("car") as Object
	if car != null:
		speed_kmh = _num(car, "speed_kmh", speed_kmh)
		rpm = _num(car, "rpm", rpm)
		throttle = _num(car, "throttle", throttle)
		slip = _num(car, "slip", slip)
	var weather := game.get("weather") as Object
	if weather != null:
		rain = _num(weather, "rain", rain)
		wet = _num(weather, "wetness", wet)


func _add_voice(voice_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = voice_name
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
	player.stream = gen
	player.unit_size = 6.0
	player.max_distance = 80.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(player)
	player.play()
	return player


func _playbacks_ready() -> bool:
	_pb_engine = _playback(_engine, _pb_engine)
	_pb_body = _playback(_body, _pb_body)
	return _pb_engine != null and _pb_body != null


func _playback(player: AudioStreamPlayer3D, cached: AudioStreamGeneratorPlayback) -> AudioStreamGeneratorPlayback:
	if cached != null:
		return cached
	if player == null:
		return null
	if not player.playing:
		player.play()
	return player.get_stream_playback() as AudioStreamGeneratorPlayback


func _pull_smoothed_from_public() -> void:
	_rpm_s = clampf(rpm, 0.0, 12000.0)
	_thr_s = clampf(throttle, 0.0, 1.0)
	_spd_s = maxf(speed_kmh, 0.0)
	_slip_s = clampf(slip, 0.0, 1.0)
	_rain_s = clampf(rain, 0.0, 1.0)
	_wet_s = clampf(wet, 0.0, 1.0)
	_master_s = 0.0 if muted else maxf(master_volume, 0.0)


func _update_targets() -> void:
	# Inline-4 four-stroke: two firings per crank revolution.
	var firing := _rpm_s / 60.0 * 2.0
	_inc1 = _hz_to_inc(firing)
	_inc2 = _hz_to_inc(firing * 1.0037)
	var rpm_n := (_rpm_s - 1800.0) / 3200.0
	if rpm_n < 0.0:
		rpm_n = 0.0
	elif rpm_n > 1.0:
		rpm_n = 1.0
	_overrun = (1.0 - _thr_s) * rpm_n
	var bright := 0.14 + 0.86 * _thr_s
	bright *= 1.0 - 0.62 * _overrun
	if bright < 0.0:
		bright = 0.0
	elif bright > 1.0:
		bright = 1.0
	var h1 := lerpf(HARM_SOFT[0], HARM_BRIGHT[0], bright)
	var h2 := lerpf(HARM_SOFT[1], HARM_BRIGHT[1], bright)
	var h3 := lerpf(HARM_SOFT[2], HARM_BRIGHT[2], bright)
	var h4 := lerpf(HARM_SOFT[3], HARM_BRIGHT[3], bright)
	var h5 := lerpf(HARM_SOFT[4], HARM_BRIGHT[4], bright)
	var h6 := lerpf(HARM_SOFT[5], HARM_BRIGHT[5], bright)
	var sum := h1 + h2 + h3 + h4 + h5 + h6
	var norm := 1.0 / sum if sum > 0.0001 else 0.0
	_a1_t = h1 * norm
	_a2_t = h2 * norm
	_a3_t = h3 * norm
	_a4_t = h4 * norm
	_a5_t = h5 * norm
	_a6_t = h6 * norm
	var rpm_lift := (_rpm_s - 600.0) / 4500.0
	if rpm_lift < 0.0:
		rpm_lift = 0.0
	elif rpm_lift > 1.0:
		rpm_lift = 1.0
	var loud := (0.20 + 0.18 * _thr_s + 0.08 * rpm_lift) * (1.0 - 0.28 * _overrun)
	var master := _master_s
	_eng_g_t = loud * master
	_intake_g_t = (0.045 + 0.11 * _thr_s) * (1.0 - 0.35 * _overrun) * master
	var sp := _spd_s / 150.0
	if sp < 0.0:
		sp = 0.0
	elif sp > 1.4:
		sp = 1.4
	_wind_g_t = sp * sp * 0.16 * master
	var speed_n := _spd_s / 130.0
	if speed_n < 0.0:
		speed_n = 0.0
	elif speed_n > 1.0:
		speed_n = 1.0
	_road_g_t = speed_n * (0.085 + 0.11 * _wet_s) * master
	_hiss_g_t = speed_n * _wet_s * 0.055 * master
	_sq_g_t = _slip_s * 0.15 * master
	_rain_g_t = _rain_s * 0.22 * master
	_crack_gate = int(_overrun * 64.0)
	_rain_gate = int(_rain_s * 120.0)


func _fill(n: int) -> void:
	var sine := _sine
	var eng := _buf_engine
	var body := _buf_body
	_buf_engine = PackedVector2Array()
	_buf_body = PackedVector2Array()
	eng.resize(n)
	body.resize(n)

	var inv := 1.0 / float(n)
	var p1 := _ph1
	var p2 := _ph2
	var re := _rng_e
	var rb := _rng_b
	var intake := _intake
	var crack := _crack
	var wind_hi := _wind_hi
	var wind_lo := _wind_lo
	var road_lp := _road_lp
	var hiss_lp := _hiss_lp
	var sq_lp := _sq_lp
	var sq_ph := _sq_ph
	var rain_lp := _rain_lp
	var click := _click
	var a1 := _a1
	var a2 := _a2
	var a3 := _a3
	var a4 := _a4
	var a5 := _a5
	var a6 := _a6
	var d1 := (_a1_t - a1) * inv
	var d2 := (_a2_t - a2) * inv
	var d3 := (_a3_t - a3) * inv
	var d4 := (_a4_t - a4) * inv
	var d5 := (_a5_t - a5) * inv
	var d6 := (_a6_t - a6) * inv
	var eg := _eng_g
	var deg := (_eng_g_t - eg) * inv
	var ig := _intake_g
	var dig := (_intake_g_t - ig) * inv
	var wg := _wind_g
	var dwg := (_wind_g_t - wg) * inv
	var rg := _road_g
	var drg := (_road_g_t - rg) * inv
	var hg := _hiss_g
	var dhg := (_hiss_g_t - hg) * inv
	var sg := _sq_g
	var dsg := (_sq_g_t - sg) * inv
	var qg := _rain_g
	var dqg := (_rain_g_t - qg) * inv
	var inc1 := _inc1
	var inc2 := _inc2
	var sq_base := _sq_base
	var sq_mod := _sq_mod
	var crack_gate := _crack_gate
	var rain_gate := _rain_gate
	var overrun := _overrun
	var chug_depth := 0.16 * (1.0 - 0.55 * overrun)
	var mask := PHASE_MASK

	for i in n:
		re = (re * 1664525 + 1013904223) & mask
		var nz := float(re & 65535) * NOISE_SCALE - 1.0
		p1 = (p1 + inc1) & mask
		p2 = (p2 + inc2) & mask
		var i1 := (p1 >> INDEX_SHIFT) & SINE_MASK
		var i2 := (p2 >> INDEX_SHIFT) & SINE_MASK
		var f1 := sine[i1]
		var v1 := f1 * a1 + sine[(i1 * 2) & SINE_MASK] * a2 + sine[(i1 * 3) & SINE_MASK] * a3 + sine[(i1 * 4) & SINE_MASK] * a4 + sine[(i1 * 5) & SINE_MASK] * a5 + sine[(i1 * 6) & SINE_MASK] * a6
		var f2 := sine[i2]
		var v2 := f2 * a1 + sine[(i2 * 2) & SINE_MASK] * a2 + sine[(i2 * 3) & SINE_MASK] * a3 + sine[(i2 * 4) & SINE_MASK] * a4 + sine[(i2 * 5) & SINE_MASK] * a5 + sine[(i2 * 6) & SINE_MASK] * a6
		a1 += d1
		a2 += d2
		a3 += d3
		a4 += d4
		a5 += d5
		a6 += d6
		intake += (nz - intake) * INTAKE_A
		var pulse := 0.5 + 0.5 * f1
		var chug := (1.0 - chug_depth) + chug_depth * pulse
		crack *= 0.93
		if crack_gate > 0 and (re & 65535) < crack_gate:
			crack = 1.0 if (re & 8192) == 0 else -1.0
		var mid := intake * pulse * ig + crack * overrun * 0.07
		var left := (v1 * 0.56 + v2 * 0.44 + mid) * chug * eg
		var right := (v2 * 0.56 + v1 * 0.44 + mid) * chug * eg
		eg += deg
		ig += dig
		var l2 := left * left
		left = left - left * l2 * 0.18
		var r2 := right * right
		right = right - right * r2 * 0.18
		if left > 0.97:
			left = 0.97
		elif left < -0.97:
			left = -0.97
		if right > 0.97:
			right = 0.97
		elif right < -0.97:
			right = -0.97
		eng[i] = Vector2(left, right)

		rb = (rb * 1664525 + 1013904223) & mask
		var n1 := float(rb & 65535) * NOISE_SCALE - 1.0
		rb = (rb * 1664525 + 1013904223) & mask
		var n2 := float(rb & 65535) * NOISE_SCALE - 1.0
		rb = (rb * 1664525 + 1013904223) & mask
		var n3 := float(rb & 65535) * NOISE_SCALE - 1.0
		wind_hi += (n1 - wind_hi) * WIND_HI_A
		wind_lo += (n1 - wind_lo) * WIND_LO_A
		var wind := (wind_hi - wind_lo) * wg
		road_lp += (n2 - road_lp) * ROAD_A
		hiss_lp += (n2 - hiss_lp) * HISS_A
		var road := road_lp * rg + hiss_lp * hg
		sq_lp += (n1 - sq_lp) * SQUEAL_A
		var sq_inc := sq_base + int(sq_lp * float(sq_mod))
		if sq_inc < 1:
			sq_inc = 1
		sq_ph = (sq_ph + sq_inc) & mask
		var squeal := (sine[(sq_ph >> INDEX_SHIFT) & SINE_MASK] * 0.88 + n1 * 0.12) * sg
		click *= 0.965
		if rain_gate > 0 and (rb & 65535) < rain_gate:
			click = 1.0 if (rb & 16384) == 0 else -1.0
		rain_lp += (n3 - rain_lp) * RAIN_A
		var roof := (click * 0.85 + rain_lp * 0.35) * qg
		var mixed := wind + road + squeal + roof
		if mixed > 0.97:
			mixed = 0.97
		elif mixed < -0.97:
			mixed = -0.97
		body[i] = Vector2(mixed, mixed)
		wg += dwg
		rg += drg
		hg += dhg
		sg += dsg
		qg += dqg

	_ph1 = p1
	_ph2 = p2
	_rng_e = re
	_rng_b = rb
	_intake = intake
	_crack = crack
	_wind_hi = wind_hi
	_wind_lo = wind_lo
	_road_lp = road_lp
	_hiss_lp = hiss_lp
	_sq_lp = sq_lp
	_sq_ph = sq_ph
	_rain_lp = rain_lp
	_click = click
	_a1 = _a1_t
	_a2 = _a2_t
	_a3 = _a3_t
	_a4 = _a4_t
	_a5 = _a5_t
	_a6 = _a6_t
	_eng_g = _eng_g_t
	_intake_g = _intake_g_t
	_wind_g = _wind_g_t
	_road_g = _road_g_t
	_hiss_g = _hiss_g_t
	_sq_g = _sq_g_t
	_rain_g = _rain_g_t
	_pb_engine.push_buffer(eng)
	_pb_body.push_buffer(body)
	_buf_engine = eng
	_buf_body = body


func _hz_to_inc(hz: float) -> int:
	if hz <= 0.0:
		return 0
	return int(hz * PHASE_PER_HZ + 0.5)


func _smooth(current: float, target: float, delta: float, tau: float) -> float:
	var a := 1.0 - exp(-delta / tau)
	return current + (target - current) * a


func _num(obj: Object, key: String, fallback: float) -> float:
	var v: Variant = obj.get(key)
	var kind := typeof(v)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return fallback
	return float(v)

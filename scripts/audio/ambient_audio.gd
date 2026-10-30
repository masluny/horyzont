class_name AmbientAudio
extends Node
## Procedural island ambience: sea, wind, dawn birds and night crickets.

const MIX_RATE := 22050.0
const BUFFER_LENGTH := 0.12
const SINE_SIZE := 2048
const SINE_MASK := 2047
const PHASE_MASK := 0xFFFFFFFF
const INDEX_SHIFT := 21
const PHASE_PER_HZ := 4294967296.0 / MIX_RATE
const MAX_FRAMES := 4096
const FILL_CAP := 736
const NOISE_SCALE := 2.0 / 65535.0
const SEA_A := 0.145 # ~550 Hz, two poles stacked in the loop
const WIND_HI_A := 0.22 # ~900 Hz
const WIND_LO_A := 0.05 # ~180 Hz

static var _sine := PackedFloat32Array()

var sea_amount := 0.5
var enabled := true
var master_volume := 1.0

var _player: AudioStreamPlayer
var _buf := PackedVector2Array()
var _rng := RandomNumberGenerator.new()

var _sea_s := 0.5
var _master_s := 1.0
var _enabled_s := 1.0
var _bird_g := 0.0
var _cr_g := 0.0
var _swell := 0.6
var _swell_t := 0.6
var _gust := 0.6
var _gust_t := 0.6
var _sea_p1 := 0.15
var _sea_p2 := 0.62
var _gust_p1 := 0.3
var _gust_p2 := 0.8

var _ns := 0x2468ACE
var _sea_lp := 0.0
var _sea_lp2 := 0.0
var _wind_hi := 0.0
var _wind_lo := 0.0

var _c0_on := false
var _c1_on := false
var _c0_wait := 0.6
var _c1_wait := 1.4
var _c0_age := 0
var _c1_age := 0
var _c0_len := 1
var _c1_len := 1
var _c0_attack := 1
var _c1_attack := 1
var _c0_att_inv := 1.0
var _c1_att_inv := 1.0
var _c0_dec_inv := 1.0
var _c1_dec_inv := 1.0
var _c0_inc0 := 0
var _c1_inc0 := 0
var _c0_inc_step := 0.0
var _c1_inc_step := 0.0
var _c0_fm_inc := 0
var _c1_fm_inc := 0
var _c0_fm_depth := 0.0
var _c1_fm_depth := 0.0
var _c0_phase := 0
var _c1_phase := 0
var _c0_fm := 0
var _c1_fm := 0

var _cr_ph := 0
var _cr_ph2 := 0
var _cr_am := 0
var _cr_am2 := 0
var _cr_inc := 0
var _cr_inc2 := 0
var _cr_am_inc := 0
var _cr_am_inc2 := 0
var _cr_env := 0.0
var _cr_env2 := 0.0
var _cr_burst := 0.0
var _cr_burst2 := 0.0
var _cr_clock := 0.0


static func _build_sine() -> void:
	if _sine.size() == SINE_SIZE:
		return
	_sine.resize(SINE_SIZE)
	var step := TAU / float(SINE_SIZE)
	for i in SINE_SIZE:
		_sine[i] = sin(float(i) * step)


func _ready() -> void:
	_build_sine()
	_rng.randomize()
	_buf.resize(MAX_FRAMES)
	_cr_inc = _hz_to_inc(4380.0)
	_cr_inc2 = _hz_to_inc(4710.0)
	_cr_am_inc = _hz_to_inc(34.0)
	_cr_am_inc2 = _hz_to_inc(41.0)
	_sea_s = clampf(sea_amount, 0.0, 1.0)
	_master_s = maxf(master_volume, 0.0)
	_enabled_s = 1.0 if enabled else 0.0
	var player := AudioStreamPlayer.new()
	player.name = "Ambience"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
	player.stream = gen
	add_child(player)
	player.play()
	_player = player


func _exit_tree() -> void:
	if _player == null:
		return
	if _player.playing:
		_player.stop()
	_player.stream = null


func _process(delta: float) -> void:
	var dt := delta if delta > 0.0 else 0.0
	var hour := _hour()
	var bird_t := 0.0
	var cricket_t := 0.0
	if hour >= 4.5 and hour <= 9.5:
		bird_t = 1.0
	elif hour >= 21.0 or (hour >= 0.0 and hour < 4.0):
		cricket_t = 1.0
	_sea_s = _smooth(_sea_s, clampf(sea_amount, 0.0, 1.0), dt, 0.25)
	_master_s = _smooth(_master_s, maxf(master_volume, 0.0), dt, 0.04)
	_enabled_s = _smooth(_enabled_s, 1.0 if enabled else 0.0, dt, 0.08)
	_bird_g = _smooth(_bird_g, bird_t, dt, 0.45)
	_cr_g = _smooth(_cr_g, cricket_t, dt, 0.45)
	# Sea swells breathe on 6–10 s cycles. Gusts are a pair of slower winds.
	_sea_p1 = fposmod(_sea_p1 + dt / 6.8, 1.0)
	_sea_p2 = fposmod(_sea_p2 + dt / 9.5, 1.0)
	_gust_p1 = fposmod(_gust_p1 + dt / 5.2, 1.0)
	_gust_p2 = fposmod(_gust_p2 + dt / 8.1, 1.0)
	var s1 := _sine[int(_sea_p1 * float(SINE_SIZE)) & SINE_MASK]
	var s2 := _sine[int(_sea_p2 * float(SINE_SIZE)) & SINE_MASK]
	_swell_t = 0.32 + 0.42 * (0.5 + 0.5 * s1) + 0.26 * (0.5 + 0.5 * s2)
	var g1 := _sine[int(_gust_p1 * float(SINE_SIZE)) & SINE_MASK]
	var g2 := _sine[int(_gust_p2 * float(SINE_SIZE)) & SINE_MASK]
	_gust_t = 0.40 + 0.38 * (0.5 + 0.5 * g1) + 0.22 * (0.5 + 0.5 * g2)
	_schedule_chirps(dt)
	_schedule_crickets(dt)
	var playback := _playback()
	if playback == null:
		return
	var frames_available := playback.get_frames_available()
	if frames_available > FILL_CAP:
		frames_available = FILL_CAP
	if frames_available <= 0:
		return
	_fill(frames_available, playback)


func _schedule_chirps(dt: float) -> void:
	_c0_wait -= dt
	_c1_wait -= dt
	if _bird_g > 0.35 and not _c0_on and _c0_wait <= 0.0:
		_arm_chirp(0)
		_c0_wait = _rng.randf_range(0.28, 1.15)
	if _bird_g > 0.35 and not _c1_on and _c1_wait <= 0.0:
		_arm_chirp(1)
		_c1_wait = _rng.randf_range(0.45, 1.6)


func _arm_chirp(slot: int) -> void:
	var base_hz := _rng.randf_range(1850.0, 2750.0)
	var end_hz := clampf(base_hz + _rng.randf_range(250.0, 1500.0), 1500.0, 4400.0)
	var length := _rng.randi_range(750, 2300)
	var fm_hz := _rng.randf_range(20.0, 52.0)
	var depth_hz := _rng.randf_range(35.0, 160.0)
	var attack := maxi(length / 9, 28)
	var decay := length - attack
	if decay < 1:
		decay = 1
	var inc0 := _hz_to_inc(base_hz)
	var step := float(_hz_to_inc(end_hz) - inc0) / float(length)
	var fm_inc := _hz_to_inc(fm_hz)
	var fm_depth := depth_hz * PHASE_PER_HZ
	var phase := _rng.randi() & PHASE_MASK
	var fm := _rng.randi() & PHASE_MASK
	if slot == 0:
		_c0_on = true
		_c0_age = 0
		_c0_len = length
		_c0_attack = attack
		_c0_att_inv = 1.0 / float(attack)
		_c0_dec_inv = 1.0 / float(decay)
		_c0_inc0 = inc0
		_c0_inc_step = step
		_c0_fm_inc = fm_inc
		_c0_fm_depth = fm_depth
		_c0_phase = phase
		_c0_fm = fm
	else:
		_c1_on = true
		_c1_age = 0
		_c1_len = length
		_c1_attack = attack
		_c1_att_inv = 1.0 / float(attack)
		_c1_dec_inv = 1.0 / float(decay)
		_c1_inc0 = inc0
		_c1_inc_step = step
		_c1_fm_inc = fm_inc
		_c1_fm_depth = fm_depth
		_c1_phase = phase
		_c1_fm = fm


func _schedule_crickets(dt: float) -> void:
	_cr_clock += dt
	if _cr_clock >= 0.52:
		_cr_clock -= 0.52
	_cr_burst = 1.0 if _cr_clock < 0.17 else 0.0
	var shifted := _cr_clock + 0.27
	if shifted >= 0.56:
		shifted -= 0.56
	_cr_burst2 = 1.0 if shifted < 0.14 else 0.0


func _fill(n: int, playback: AudioStreamGeneratorPlayback) -> void:
	var sine := _sine
	var buf := _buf
	_buf = PackedVector2Array()
	buf.resize(n)
	var inv := 1.0 / float(n)
	var ns := _ns
	var sea_lp := _sea_lp
	var sea_lp2 := _sea_lp2
	var wind_hi := _wind_hi
	var wind_lo := _wind_lo
	var swell := _swell
	var dswell := (_swell_t - swell) * inv
	var gust := _gust
	var dgust := (_gust_t - gust) * inv
	var sea_amt := _sea_s
	var bird_g := _bird_g
	var cr_g := _cr_g
	var master := _master_s * _enabled_s
	var do_birds := _c0_on or _c1_on or bird_g > 0.001
	var do_cr := cr_g > 0.001
	var mask := PHASE_MASK
	var c0_on := _c0_on
	var c1_on := _c1_on
	var c0_age := _c0_age
	var c1_age := _c1_age
	var c0_phase := _c0_phase
	var c1_phase := _c1_phase
	var c0_fm := _c0_fm
	var c1_fm := _c1_fm
	var cr_ph := _cr_ph
	var cr_ph2 := _cr_ph2
	var cr_am := _cr_am
	var cr_am2 := _cr_am2
	var cr_env := _cr_env
	var cr_env2 := _cr_env2

	for i in n:
		ns = (ns * 1664525 + 1013904223) & mask
		var nz := float(ns & 65535) * NOISE_SCALE - 1.0
		sea_lp += (nz - sea_lp) * SEA_A
		sea_lp2 += (sea_lp - sea_lp2) * SEA_A
		wind_hi += (nz - wind_hi) * WIND_HI_A
		wind_lo += (nz - wind_lo) * WIND_LO_A
		var sample := sea_lp2 * swell * sea_amt * 0.20
		sample += (wind_hi - wind_lo) * gust * 0.055
		swell += dswell
		gust += dgust
		if do_birds:
			var birds := 0.0
			if c0_on:
				c0_fm = (c0_fm + _c0_fm_inc) & mask
				var fm0 := sine[(c0_fm >> INDEX_SHIFT) & SINE_MASK]
				var inc0 := _c0_inc0 + int(float(c0_age) * _c0_inc_step + fm0 * _c0_fm_depth)
				if inc0 < 1:
					inc0 = 1
				c0_phase = (c0_phase + inc0) & mask
				var env0 := float(c0_age) * _c0_att_inv
				if c0_age >= _c0_attack:
					env0 = float(_c0_len - c0_age) * _c0_dec_inv
				birds += sine[(c0_phase >> INDEX_SHIFT) & SINE_MASK] * env0
				c0_age += 1
				if c0_age >= _c0_len:
					c0_on = false
			if c1_on:
				c1_fm = (c1_fm + _c1_fm_inc) & mask
				var fm1 := sine[(c1_fm >> INDEX_SHIFT) & SINE_MASK]
				var inc1 := _c1_inc0 + int(float(c1_age) * _c1_inc_step + fm1 * _c1_fm_depth)
				if inc1 < 1:
					inc1 = 1
				c1_phase = (c1_phase + inc1) & mask
				var env1 := float(c1_age) * _c1_att_inv
				if c1_age >= _c1_attack:
					env1 = float(_c1_len - c1_age) * _c1_dec_inv
				birds += sine[(c1_phase >> INDEX_SHIFT) & SINE_MASK] * env1 * 0.85
				c1_age += 1
				if c1_age >= _c1_len:
					c1_on = false
			sample += birds * bird_g * 0.09
		if do_cr:
			cr_ph = (cr_ph + _cr_inc) & mask
			cr_ph2 = (cr_ph2 + _cr_inc2) & mask
			cr_am = (cr_am + _cr_am_inc) & mask
			cr_am2 = (cr_am2 + _cr_am_inc2) & mask
			var am := 0.5 + 0.5 * sine[(cr_am >> INDEX_SHIFT) & SINE_MASK]
			var am2 := 0.5 + 0.5 * sine[(cr_am2 >> INDEX_SHIFT) & SINE_MASK]
			cr_env += (_cr_burst - cr_env) * 0.01
			cr_env2 += (_cr_burst2 - cr_env2) * 0.01
			sample += sine[(cr_ph >> INDEX_SHIFT) & SINE_MASK] * am * cr_env * cr_g * 0.055
			sample += sine[(cr_ph2 >> INDEX_SHIFT) & SINE_MASK] * am2 * cr_env2 * cr_g * 0.045
		sample *= master
		if sample > 0.97:
			sample = 0.97
		elif sample < -0.97:
			sample = -0.97
		buf[i] = Vector2(sample, sample)

	_ns = ns
	_sea_lp = sea_lp
	_sea_lp2 = sea_lp2
	_wind_hi = wind_hi
	_wind_lo = wind_lo
	_swell = _swell_t
	_gust = _gust_t
	_c0_on = c0_on
	_c1_on = c1_on
	_c0_age = c0_age
	_c1_age = c1_age
	_c0_phase = c0_phase
	_c1_phase = c1_phase
	_c0_fm = c0_fm
	_c1_fm = c1_fm
	_cr_ph = cr_ph
	_cr_ph2 = cr_ph2
	_cr_am = cr_am
	_cr_am2 = cr_am2
	_cr_env = cr_env
	_cr_env2 = cr_env2
	playback.push_buffer(buf)
	_buf = buf


func _hour() -> float:
	if not is_inside_tree():
		return -1.0
	var game := get_node_or_null("/root/Game")
	if game == null:
		return -1.0
	var clock := game.get("clock") as Object
	if clock == null:
		return -1.0
	var v: Variant = clock.get("time")
	var kind := typeof(v)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return -1.0
	return float(v)


func _playback() -> AudioStreamGeneratorPlayback:
	if _player == null:
		return null
	if not _player.playing:
		_player.play()
	return _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _hz_to_inc(hz: float) -> int:
	if hz <= 0.0:
		return 0
	return int(hz * PHASE_PER_HZ + 0.5)


func _smooth(current: float, target: float, delta: float, tau: float) -> float:
	var a := 1.0 - exp(-delta / tau)
	return current + (target - current) * a

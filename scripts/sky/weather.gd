class_name Weather
extends Node
## Weather presets with smooth transitions. Pushes cloud, haze, fog and
## wetness parameters to the shader globals and the Environment.

signal preset_changed(id: String)

const PRESETS := {
	"pogodnie": {
		"name": "Pogodnie",
		"coverage": 0.34, "type": 0.55, "density": 0.9, "bottom": 1.4, "thickness": 2.4,
		"cirrus": 0.35, "mie": 1.0, "fog": 0.00003, "height_fog": 0.0, "rain": 0.0,
		"wind": 9.0, "exposure_bias": 0.0,
	},
	"zlota_mgielka": {
		"name": "Złota mgiełka",
		"coverage": 0.4, "type": 0.45, "density": 0.8, "bottom": 1.6, "thickness": 2.0,
		"cirrus": 0.65, "mie": 3.2, "fog": 0.0001, "height_fog": 0.0, "rain": 0.0,
		"wind": 6.0, "exposure_bias": 0.1,
	},
	"cumulusy": {
		"name": "Cumulusy",
		"coverage": 0.56, "type": 0.72, "density": 1.05, "bottom": 1.2, "thickness": 3.4,
		"cirrus": 0.25, "mie": 1.4, "fog": 0.000035, "height_fog": 0.0, "rain": 0.0,
		"wind": 12.0, "exposure_bias": 0.0,
	},
	"burzowy_zachod": {
		"name": "Burzowy zachód",
		"coverage": 0.62, "type": 1.0, "density": 1.25, "bottom": 1.2, "thickness": 6.5,
		"cirrus": 0.5, "mie": 2.4, "fog": 0.00008, "height_fog": 0.0, "rain": 0.0,
		"wind": 15.0, "exposure_bias": 0.25,
	},
	"pochmurno": {
		"name": "Pochmurno",
		"coverage": 0.86, "type": 0.25, "density": 1.15, "bottom": 1.0, "thickness": 1.8,
		"cirrus": 0.1, "mie": 2.0, "fog": 0.0002, "height_fog": 0.0, "rain": 0.0,
		"wind": 14.0, "exposure_bias": 0.35,
	},
	"deszcz": {
		"name": "Deszcz",
		"coverage": 0.97, "type": 0.55, "density": 1.4, "bottom": 0.8, "thickness": 3.0,
		"cirrus": 0.0, "mie": 2.6, "fog": 0.0004, "height_fog": 0.0, "rain": 1.0,
		"wind": 18.0, "exposure_bias": 0.5,
	},
	"po_deszczu": {
		"name": "Po deszczu",
		"coverage": 0.42, "type": 0.7, "density": 1.1, "bottom": 1.1, "thickness": 3.2,
		"cirrus": 0.3, "mie": 0.7, "fog": 0.00002, "height_fog": 0.0, "rain": 0.0,
		"wind": 11.0, "exposure_bias": 0.0,
	},
	"poranna_mgla": {
		"name": "Poranna mgła",
		"coverage": 0.18, "type": 0.3, "density": 0.8, "bottom": 1.6, "thickness": 1.4,
		"cirrus": 0.45, "mie": 4.5, "fog": 0.0009, "height_fog": 0.012, "rain": 0.0,
		"wind": 3.0, "exposure_bias": 0.15,
	},
}

const KEYS := ["coverage", "type", "density", "bottom", "thickness", "cirrus", "mie", "fog", "height_fog", "rain", "wind", "exposure_bias"]

var current_id := "pogodnie"
var auto_cycle := true
var transition_seconds := 90.0

var mie_scale := 1.0
var exposure_bias := 0.0
var wetness := 0.0
var rain := 0.0

var env: Environment
var clock: TimeOfDay

var _from := {}
var _to := {}
var _value := {}
var _blend := 1.0
var wind_offset := Vector2.ZERO
var _cirrus_offset := Vector2.ZERO
var _evolve := 0.0
var _next_change := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_to = PRESETS[current_id].duplicate()
	_from = _to.duplicate()
	_value = _to.duplicate()
	_next_change = _rng.randf_range(15.0, 35.0) * 60.0


func set_preset(id: String, instant := false) -> void:
	if not PRESETS.has(id):
		push_warning("Unknown weather preset: %s" % id)
		return
	current_id = id
	_from = _value.duplicate()
	_to = PRESETS[id].duplicate()
	_blend = 1.0 if instant else 0.0
	if instant:
		_value = _to.duplicate()
		wetness = 1.0 if id == "deszcz" else (0.75 if id == "po_deszczu" else 0.0)
	preset_changed.emit(id)


func value(key: String) -> float:
	return _value.get(key, 0.0)


func preset_name() -> String:
	return PRESETS[current_id]["name"]


func _process(delta: float) -> void:
	var game_dt := delta * (clock.time_scale if clock else 12.0)
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / transition_seconds)
		var k := smoothstep(0.0, 1.0, _blend)
		for key in KEYS:
			_value[key] = lerpf(_from[key], _to[key], k)
	if auto_cycle:
		_next_change -= game_dt
		if _next_change <= 0.0:
			_next_change = _rng.randf_range(25.0, 70.0) * 60.0
			set_preset(_pick_next())

	rain = _value["rain"]
	mie_scale = _value["mie"]
	exposure_bias = _value["exposure_bias"]
	# Roads get wet quickly in rain and dry over roughly two game hours.
	if rain > 0.05:
		wetness = minf(1.0, wetness + game_dt / 600.0 * rain)
	else:
		wetness = maxf(0.0, wetness - game_dt / 7200.0)

	var wind_dir := Vector2(0.8, 0.6).normalized()
	wind_offset += wind_dir * _value["wind"] * 0.001 * game_dt
	_cirrus_offset += wind_dir.rotated(0.4) * _value["wind"] * 0.0025 * game_dt
	_evolve += game_dt * 0.0004

	RenderingServer.global_shader_parameter_set("cloud_coverage", _value["coverage"])
	RenderingServer.global_shader_parameter_set("cloud_type", _value["type"])
	RenderingServer.global_shader_parameter_set("cloud_density", _value["density"])
	RenderingServer.global_shader_parameter_set("cloud_bottom", _value["bottom"])
	RenderingServer.global_shader_parameter_set("cloud_thickness", _value["thickness"])
	RenderingServer.global_shader_parameter_set("cirrus_coverage", _value["cirrus"])
	RenderingServer.global_shader_parameter_set("cloud_wind", wind_offset)
	RenderingServer.global_shader_parameter_set("cirrus_offset", _cirrus_offset)
	RenderingServer.global_shader_parameter_set("cloud_evolve", _evolve)
	RenderingServer.global_shader_parameter_set("mie_scale", mie_scale)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("rain_amount", rain)
	RenderingServer.global_shader_parameter_set("world_wind", wind_dir * _value["wind"])

	if env:
		# Godot's exponential fog needs ~12x the textbook extinction for this look.
		env.fog_density = _value["fog"] * 12.0 * float(Game.arg("fog_mul", "1"))
		env.fog_height_density = _value["height_fog"]


func _pick_next() -> String:
	var weights := {
		"pogodnie": 3.0, "zlota_mgielka": 2.5, "cumulusy": 3.0, "burzowy_zachod": 1.2,
		"pochmurno": 1.0, "deszcz": 0.8, "po_deszczu": 1.2, "poranna_mgla": 0.0,
	}
	if clock and clock.time > 3.5 and clock.time < 7.0:
		weights["poranna_mgla"] = 3.0
	if current_id == "deszcz":
		weights = {"po_deszczu": 1.0}
	weights.erase(current_id)
	var total := 0.0
	for w in weights.values():
		total += w
	var pick := _rng.randf() * total
	for id in weights:
		pick -= weights[id]
		if pick <= 0.0:
			return id
	return "pogodnie"

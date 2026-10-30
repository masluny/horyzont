class_name TimeOfDay
extends Node
## Game clock, sun and moon positions, sun/moon lights, exposure and fog colour.
## Sun direction convention: +X east, -Z north, +Y up.

signal hour_changed(hour: int)

const LATITUDE := deg_to_rad(50.0)
const SUN_E := 12.0
const MOON_E := 0.0026
const R_GROUND := 6360.0
const R_TOP := 6460.0
const RAYLEIGH := Vector3(5.802e-3, 13.558e-3, 33.1e-3)
const MIE_EXT := 4.44e-3
const OZONE := Vector3(0.650e-3, 1.881e-3, 0.085e-3)

## Hours, 0..24.
var time := 19.0
## Game seconds per real second.
var time_scale := 12.0
var day_of_year := 172
var paused := false

var sun_dir := Vector3.UP
var moon_dir := Vector3.DOWN
var sun_color := Color.WHITE
var sun_strength := 1.0
var night := 0.0
var exposure := 1.0

var env: Environment
var attributes: CameraAttributesPractical
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var weather: Weather
var sky: SkySystem

var _last_hour := -1
var _exposure_initialised := false


func setup(p_env: Environment, p_attr: CameraAttributesPractical, p_sun: DirectionalLight3D,
		p_moon: DirectionalLight3D, p_weather: Weather, p_sky: SkySystem) -> void:
	env = p_env
	attributes = p_attr
	sun_light = p_sun
	moon_light = p_moon
	weather = p_weather
	sky = p_sky


func _process(delta: float) -> void:
	if not paused:
		time = fposmod(time + delta * time_scale / 3600.0, 24.0)
	var h := int(time)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	update_sky(delta)


## Hours until the sun reaches the given elevation (degrees) going up or down.
func hours_until_elevation(deg: float, rising: bool) -> float:
	var t := time
	var prev := _sun_elevation(t)
	for i in 24 * 60:
		t = fposmod(t + 1.0 / 60.0, 24.0)
		var e := _sun_elevation(t)
		if rising and prev < deg and e >= deg:
			return (i + 1) / 60.0
		if not rising and prev > deg and e <= deg:
			return (i + 1) / 60.0
		prev = e
	return 0.0


func sun_elevation_deg() -> float:
	return rad_to_deg(asin(clampf(sun_dir.y, -1.0, 1.0)))


func update_sky(delta: float) -> void:
	sun_dir = _celestial_dir(time, _declination())
	# Moon: a few days after full moon, so it rises in the evening.
	moon_dir = _celestial_dir(time + 12.0 - 1.6, -_declination() * 0.8 + deg_to_rad(4.0))
	var sidereal := (time - 12.0) / 24.0 * TAU + day_of_year / 365.25 * TAU
	night = clampf(smoothstep(-0.05, -0.2, sun_dir.y), 0.0, 1.0)

	RenderingServer.global_shader_parameter_set("sun_direction", sun_dir)
	RenderingServer.global_shader_parameter_set("moon_direction", moon_dir)
	RenderingServer.global_shader_parameter_set("star_rotation", sidereal)
	RenderingServer.global_shader_parameter_set("night_factor", night)
	RenderingServer.global_shader_parameter_set("sun_illuminance", Vector3.ONE * SUN_E)
	var moon_vis := clampf(moon_dir.y * 8.0 + 0.3, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("moon_illuminance", Vector3(0.9, 0.95, 1.0) * MOON_E * moon_vis)

	var cam := get_viewport().get_camera_3d()
	var alt_km := 0.05
	var cam_xz := Vector2.ZERO
	if cam:
		alt_km = maxf(cam.global_position.y, 2.0) * 0.001
		cam_xz = Vector2(cam.global_position.x, cam.global_position.z)
	var mie := weather.mie_scale if weather else 1.0

	# Sun light: colour from the real transmittance, dimmed by clouds overhead.
	var t_sun := transmittance(alt_km, sun_dir.y, mie)
	var vis := clampf((sun_dir.y + 0.006) / 0.02, 0.0, 1.0)
	var cloud_shadow := 1.0
	if sky and sky.is_baked and sun_dir.y > 0.0:
		var offset := Vector2(sun_dir.x, sun_dir.z) / maxf(sun_dir.y, 0.08) * 2000.0
		var cov := sky.coverage_at(cam_xz + offset)
		var thick: float = weather.value("density") if weather else 1.0
		cloud_shadow = lerpf(1.0, 0.15, clampf(cov * cov * 1.4 * thick, 0.0, 1.0))
	var tmax := maxf(t_sun.x, maxf(t_sun.y, t_sun.z))
	sun_color = Color(t_sun.x / tmax, t_sun.y / tmax, t_sun.z / tmax) if tmax > 1e-6 else Color.BLACK
	sun_strength = tmax * vis * cloud_shadow
	if sun_light:
		_aim_light(sun_light, sun_dir)
		sun_light.light_color = sun_color
		sun_light.light_energy = SUN_E / PI * sun_strength
		sun_light.visible = sun_strength > 0.0005
		sun_light.shadow_enabled = sun_dir.y > 0.0 and not sun_light.has_meta("force_no_shadow")
	if moon_light:
		_aim_light(moon_light, moon_dir)
		var t_moon := transmittance(alt_km, moon_dir.y, mie)
		var mvis := clampf((moon_dir.y + 0.01) / 0.04, 0.0, 1.0)
		moon_light.light_color = Color(0.62, 0.72, 1.0)
		moon_light.light_energy = MOON_E / PI * t_moon.length() / 1.7 * mvis * night * 3.0
		moon_light.visible = night > 0.05 and mvis > 0.0
		moon_light.shadow_enabled = night > 0.6

	_update_exposure(delta)
	_update_fog(t_sun, mie)


## Transmittance from altitude (km) toward a direction with cosine mu.
static func transmittance(alt_km: float, mu: float, mie_scale: float) -> Vector3:
	var r := R_GROUND + alt_km
	var ro := Vector3(0.0, r, 0.0)
	var rd := Vector3(sqrt(maxf(0.0, 1.0 - mu * mu)), mu, 0.0)
	# Planet hit?
	var b := ro.dot(rd)
	var c := (r - R_GROUND) * (r + R_GROUND)
	if b < 0.0 and b * b - c > 0.0:
		return Vector3.ZERO
	var ct := (r - R_TOP) * (r + R_TOP)
	var t_end := -b + sqrt(maxf(b * b - ct, 0.0))
	var steps := 32
	var dt := t_end / steps
	var od := Vector3.ZERO
	for i in steps:
		var p := ro + rd * ((i + 0.5) * dt)
		var h := maxf(p.length() - R_GROUND, 0.0)
		var dr := exp(-h / 8.0)
		var dm := exp(-h / 1.2) * mie_scale
		var doz := maxf(0.0, 1.0 - absf(h - 25.0) / 15.0)
		od += (RAYLEIGH * dr + Vector3.ONE * MIE_EXT * dm + OZONE * doz) * dt
	return Vector3(exp(-od.x), exp(-od.y), exp(-od.z))


func _declination() -> float:
	return deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)


func _sun_elevation(t: float) -> float:
	return rad_to_deg(asin(clampf(_celestial_dir(t, _declination()).y, -1.0, 1.0)))


func _celestial_dir(hours: float, decl: float) -> Vector3:
	var ha := (hours - 12.0) / 24.0 * TAU
	var sin_e := sin(LATITUDE) * sin(decl) + cos(LATITUDE) * cos(decl) * cos(ha)
	var e := asin(clampf(sin_e, -1.0, 1.0))
	var az := atan2(-sin(ha) * cos(decl), cos(LATITUDE) * sin(decl) - sin(LATITUDE) * cos(decl) * cos(ha))
	return Vector3(cos(e) * sin(az), sin(e), -cos(e) * cos(az)).normalized()


func _aim_light(light: DirectionalLight3D, dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(-dir, up), Vector3.ZERO)


func _update_exposure(delta: float) -> void:
	if env == null:
		return
	var e := sun_elevation_deg()
	# Hand-tuned exposure curve (stops relative to midday).
	var stops: float
	const CURVE := [[90.0, 0.0], [25.0, 0.0], [8.0, 0.6], [2.0, 1.5], [0.0, 2.1], [-3.0, 4.2],
			[-6.0, 6.2], [-9.0, 7.8], [-13.0, 8.8], [-90.0, 8.8]]
	stops = 8.8
	for i in CURVE.size() - 1:
		var a: Array = CURVE[i]
		var b: Array = CURVE[i + 1]
		if e <= a[0] and e >= b[0]:
			stops = remap(e, a[0], b[0], a[1], b[1])
			break
	if weather:
		stops += weather.exposure_bias
	var target := pow(2.0, stops) * 0.62
	if not _exposure_initialised:
		exposure = target
		_exposure_initialised = true
	exposure = lerpf(exposure, target, 1.0 - exp(-delta * 2.0))
	env.tonemap_exposure = exposure


func _update_fog(t_sun: Vector3, mie: float) -> void:
	if env == null:
		return
	var horizon := Color(0.55, 0.65, 0.8).lerp(Color(t_sun.x, t_sun.y, t_sun.z) * 0.9, 0.35)
	horizon = horizon * clampf(sun_strength * 1.5 + 0.02, 0.0, 1.0)
	horizon = horizon.lerp(Color(0.04, 0.05, 0.09), night)
	env.fog_light_color = horizon
	# Lift the shadows in twilight and at night so the land stays readable.
	var e := sun_elevation_deg()
	env.ambient_light_energy = 1.0 + 6.0 * smoothstep(3.0, -5.0, e) - 1.5 * smoothstep(-7.0, -14.0, e)
	env.fog_sun_scatter = clampf(0.08 + (mie - 1.0) * 0.05, 0.0, 0.4) * (1.0 - night)

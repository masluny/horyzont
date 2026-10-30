class_name SkySystem
extends Node3D
## Owns the atmosphere look-up tables, the baked cloud noise volumes and the
## sky materials (visible dome + environment sky for ambient and reflections).

signal baked

const TRANSMITTANCE_SIZE := Vector2i(256, 64)
const MULTISCATTER_SIZE := Vector2i(32, 32)
const AMBIENT_SIZE := Vector2i(32, 2)
const SHAPE_SIZE := 128
const SHAPE_TILES := Vector2i(16, 8)
const DETAIL_SIZE := 32
const DETAIL_TILES := Vector2i(8, 4)
const WEATHER_SIZE := 512
const DOME_RADIUS := 32000.0
const SKY_PASS_SCALE := 0.5
const CLOUD_SHADOW_SIZE := 256

var environment: Environment
var dome: MeshInstance3D
var dome_material: ShaderMaterial
var sky_material: ShaderMaterial
var weather_image: Image
var is_baked := false
## Without a temporal upscaler the dither pattern must hold still or it flickers.
var temporal_dither := true

var _transmittance_vp: SubViewport
var _multiscatter_vp: SubViewport
var _ambient_vp: SubViewport
var _cloud_shape: ImageTexture3D
var _cloud_detail: ImageTexture3D
var _cloud_weather: ImageTexture
var _registered: Array[ShaderMaterial] = []
var _frame := 0
var _sky_vp: Array[SubViewport] = []
var _sky_mat: Array[ShaderMaterial] = []
var _sky_flip := 0
var _sky_warm := 0
var _prev_basis := Basis.IDENTITY
var _shadow_vp: SubViewport
var _shadow_mat: ShaderMaterial


func _init(env: Environment) -> void:
	environment = env
	process_priority = 1000


func _ready() -> void:
	_transmittance_vp = _make_lut(TRANSMITTANCE_SIZE, preload("res://shaders/bake/lut_transmittance.gdshader"), true)
	_multiscatter_vp = _make_lut(MULTISCATTER_SIZE, preload("res://shaders/bake/lut_multiscatter.gdshader"), true)
	_ambient_vp = _make_lut(AMBIENT_SIZE, preload("res://shaders/bake/lut_ambient.gdshader"), true)
	_lut_material(_multiscatter_vp).set_shader_parameter("transmittance_lut", _transmittance_vp.get_texture())
	_lut_material(_ambient_vp).set_shader_parameter("transmittance_lut", _transmittance_vp.get_texture())
	_lut_material(_ambient_vp).set_shader_parameter("multiscatter_lut", _multiscatter_vp.get_texture())
	_build_materials()
	_build_passes()
	_bake_noise()


func _process(_delta: float) -> void:
	_frame += 1
	RenderingServer.global_shader_parameter_set("frame_jitter", float(_frame % 64))
	RenderingServer.global_shader_parameter_set("dither_jitter", float(_frame % 64) if temporal_dither else 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam and dome:
		dome.global_position = cam.global_position
	if cam and is_baked:
		_update_sky_pass(cam)
		if _frame % 3 == 0:
			_update_shadow_pass(cam)


func set_cloud_quality(steps: int, light_steps: int) -> void:
	for mat in _sky_mat:
		mat.set_shader_parameter("cloud_steps", steps)
		mat.set_shader_parameter("cloud_light_steps", light_steps)


func set_sky_debug(quality: int) -> void:
	for mat in _sky_mat:
		mat.set_shader_parameter("debug_quality", quality)


## Gives a material the LUTs and cloud textures (terrain, water, etc.).
func register_material(mat: ShaderMaterial) -> void:
	if not _registered.has(mat):
		_registered.append(mat)
	_apply_textures(mat)


func transmittance_texture() -> Texture2D:
	return _transmittance_vp.get_texture()


## Local cumulus coverage (0..1) at a world position in metres, using the same
## weather map and wind offset as the shaders.
func coverage_at(world_xz: Vector2) -> float:
	if weather_image == null:
		return 0.0
	var wind: Vector2 = Game.weather.wind_offset if Game.weather else Vector2.ZERO
	var c: float = Game.weather.value("coverage") if Game.weather else 0.0
	var uv := (world_xz * 0.001 + wind * 0.55) / 24.0
	var px := Vector2i(posmod(int(uv.x * WEATHER_SIZE), WEATHER_SIZE), posmod(int(uv.y * WEATHER_SIZE), WEATHER_SIZE))
	var w := weather_image.get_pixelv(px).r
	var lo := 0.85 - c
	return smoothstep(lo, lo + 0.3, w) * clampf(c * 3.0, 0.0, 1.0)


func _make_lut(size: Vector2i, shader: Shader, hdr: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.use_hdr_2d = hdr
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	return vp


func _lut_material(vp: SubViewport) -> ShaderMaterial:
	return (vp.get_child(0) as ColorRect).material


func _build_materials() -> void:
	dome_material = ShaderMaterial.new()
	dome_material.shader = preload("res://shaders/sky_dome.gdshader")
	dome_material.render_priority = -100
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	dome = MeshInstance3D.new()
	dome.name = "SkyDome"
	dome.mesh = sphere
	dome.material_override = dome_material
	dome.scale = Vector3.ONE * DOME_RADIUS
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dome.custom_aabb = AABB(Vector3.ONE * -2.0, Vector3.ONE * 4.0)
	dome.ignore_occlusion_culling = true
	dome.visible = false
	add_child(dome)

	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky_env.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


func _apply_textures(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("transmittance_lut", _transmittance_vp.get_texture())
	mat.set_shader_parameter("multiscatter_lut", _multiscatter_vp.get_texture())
	mat.set_shader_parameter("ambient_lut", _ambient_vp.get_texture())
	if is_baked:
		mat.set_shader_parameter("cloud_shape", _cloud_shape)
		mat.set_shader_parameter("cloud_detail", _cloud_detail)
		mat.set_shader_parameter("cloud_weather", _cloud_weather)


func _build_passes() -> void:
	for i in 2:
		var vp := _make_lut(Vector2i(64, 64), preload("res://shaders/sky_lowres.gdshader"), true)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		(vp.get_child(0) as ColorRect).set_anchors_preset(Control.PRESET_FULL_RECT)
		_sky_vp.append(vp)
		_sky_mat.append(_lut_material(vp))
		register_material(_lut_material(vp))
	_shadow_vp = _make_lut(Vector2i(CLOUD_SHADOW_SIZE, CLOUD_SHADOW_SIZE), preload("res://shaders/cloud_shadow_pass.gdshader"), true)
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_shadow_mat = _lut_material(_shadow_vp)
	register_material(_shadow_mat)
	RenderingServer.global_shader_parameter_set("cloud_shadow_tex", _shadow_vp.get_texture().get_rid())


func _update_sky_pass(cam: Camera3D) -> void:
	var main := get_viewport()
	var size := main.get_visible_rect().size * main.scaling_3d_scale * SKY_PASS_SCALE
	var want := Vector2i(maxi(int(size.x), 16), maxi(int(size.y), 16))
	var cur := _sky_vp[_sky_flip]
	if cur.size != want:
		for vp in _sky_vp:
			vp.size = want
		_sky_warm = 0
	var other := _sky_vp[1 - _sky_flip]
	var mat := _sky_mat[_sky_flip]
	var basis := cam.global_basis.orthonormalized()
	var tan_y := tan(deg_to_rad(cam.fov) * 0.5)
	var aspect := float(want.x) / float(want.y)
	mat.set_shader_parameter("history", other.get_texture())
	mat.set_shader_parameter("cam_basis", basis)
	mat.set_shader_parameter("prev_basis_inv", _prev_basis.inverse())
	mat.set_shader_parameter("tan_half", Vector2(tan_y * aspect, tan_y))
	mat.set_shader_parameter("cam_pos", cam.global_position)
	var settled := 0.1 if Game.clock and Game.clock.time_scale > 30.0 else 0.92
	mat.set_shader_parameter("history_weight", settled if _sky_warm > 2 else 0.0)
	cur.render_target_update_mode = SubViewport.UPDATE_ONCE
	dome_material.set_shader_parameter("sky_lowres", cur.get_texture())
	_prev_basis = basis
	_sky_flip = 1 - _sky_flip
	_sky_warm += 1


func _update_shadow_pass(cam: Camera3D) -> void:
	# Snapped to texels so the shadows do not swim as the camera moves.
	var texel := 8000.0 / CLOUD_SHADOW_SIZE
	var center := Vector2(snappedf(cam.global_position.x, texel), snappedf(cam.global_position.z, texel))
	_shadow_mat.set_shader_parameter("center_km", center * 0.001)
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.global_shader_parameter_set("cloud_shadow_center", center)


func _bake_noise() -> void:
	var shader := preload("res://shaders/bake/cloud_noise.gdshader")
	var shape_vp := _bake_viewport(SHAPE_TILES * SHAPE_SIZE, shader, {"mode": 0, "slice_size": float(SHAPE_SIZE), "tiles_x": float(SHAPE_TILES.x)})
	var detail_vp := _bake_viewport(DETAIL_TILES * DETAIL_SIZE, shader, {"mode": 1, "slice_size": float(DETAIL_SIZE), "tiles_x": float(DETAIL_TILES.x)})
	var weather_vp := _bake_viewport(Vector2i(WEATHER_SIZE, WEATHER_SIZE), preload("res://shaders/bake/weather_map.gdshader"), {})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	_cloud_shape = _atlas_to_volume(shape_vp.get_texture().get_image(), SHAPE_SIZE, SHAPE_TILES)
	_cloud_detail = _atlas_to_volume(detail_vp.get_texture().get_image(), DETAIL_SIZE, DETAIL_TILES)
	weather_image = weather_vp.get_texture().get_image()
	weather_image.convert(Image.FORMAT_RGBA8)
	var mipped := weather_image.duplicate()
	mipped.generate_mipmaps()
	_cloud_weather = ImageTexture.create_from_image(mipped)
	if Game.args.has("dump_noise"):
		weather_image.save_png("res://dev/out/weather_map.png")
		shape_vp.get_texture().get_image().save_png("res://dev/out/shape_atlas.png")
	for vp in [shape_vp, detail_vp, weather_vp]:
		vp.queue_free()

	is_baked = true
	_apply_textures(dome_material)
	_apply_textures(sky_material)
	for mat in _registered:
		_apply_textures(mat)
	dome.visible = not Game.args.has("no_dome")
	if Game.args.has("dome_q"):
		set_sky_debug(int(Game.arg("dome_q")))
	baked.emit()


func _bake_viewport(size: Vector2i, shader: Shader, params: Dictionary) -> SubViewport:
	var vp := _make_lut(size, shader, true)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mat := _lut_material(vp)
	for key in params:
		mat.set_shader_parameter(key, params[key])
	return vp


func _atlas_to_volume(atlas: Image, size: int, tiles: Vector2i) -> ImageTexture3D:
	atlas.convert(Image.FORMAT_RGBA8)
	var slices: Array[Image] = []
	for z in tiles.x * tiles.y:
		var tx := z % tiles.x
		var ty := z / tiles.x
		slices.append(atlas.get_region(Rect2i(tx * size, ty * size, size, size)))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, size, size, tiles.x * tiles.y, false, slices)
	return tex

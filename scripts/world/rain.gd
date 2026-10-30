class_name Rain
extends GPUParticles3D
## Rain streaks in a box that follows the camera; amount follows Weather.rain.

func _ready() -> void:
	amount = 9000
	lifetime = 0.9
	preprocess = 1.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.15, -1, 0.1)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.55, 0.6, 0.65, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.disable_receive_shadows = true
	quad.material = mat
	draw_pass_1 = quad
	emitting = false


func _process(_delta: float) -> void:
	var r := Game.weather.rain if Game.weather else 0.0
	emitting = r > 0.05
	amount_ratio = clampf(r, 0.0, 1.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var v := Vector3.ZERO
		if Game.car:
			v = Game.car.linear_velocity * 0.5
		global_position = cam.global_position + Vector3.UP * 16.0 + v

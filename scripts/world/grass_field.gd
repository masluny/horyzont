class_name GrassField
extends MultiMeshInstance3D
## Camera-centred field of grass blades; placement happens in the shader.

const SIDE := 150
const CELL := 0.5
const BLADES := 5

var material: ShaderMaterial


func setup(data: TerrainData) -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/grass.gdshader")
	material.set_shader_parameter("heightmap", data.height_texture)
	material.set_shader_parameter("normalmap", data.normal_texture)
	material.set_shader_parameter("maskmap", data.mask_texture)
	material.set_shader_parameter("side", SIDE)
	material.set_shader_parameter("cell", CELL)
	material.set_shader_parameter("radius", SIDE * CELL * 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blade_mesh()
	mm.instance_count = SIDE * SIDE
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	multimesh = mm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))


func set_density(side: int) -> void:
	multimesh.visible_instance_count = side * side if side < SIDE else -1
	material.set_shader_parameter("side", mini(side, SIDE))
	material.set_shader_parameter("radius", mini(side, SIDE) * CELL * 0.5)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		material.set_shader_parameter("field_center", Vector2(cam.global_position.x, cam.global_position.z))


func _blade_mesh() -> ArrayMesh:
	# A clump of tapered blades: x in [-1, 1], y in [0, 1], UV.y = height.
	# COLOR carries per-blade offset (rg), height factor (b) and yaw (a).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var segs := 3
	for b in BLADES:
		var col := Color(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.0), rng.randf())
		var base := verts.size()
		for s in segs + 1:
			var t := float(s) / segs
			verts.append(Vector3(-1.0, t, 0.0))
			verts.append(Vector3(1.0, t, 0.0))
			uvs.append(Vector2(0.0, t))
			uvs.append(Vector2(1.0, t))
			cols.append(col)
			cols.append(col)
		for s in segs:
			var a := base + s * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

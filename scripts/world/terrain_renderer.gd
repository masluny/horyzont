class_name TerrainRenderer
extends Node3D
## Geometry clipmap: LEVELS nested square grids around the camera. Level 0 is a
## full grid; outer levels are rings whose hole is covered by the finer level.
## Nodes stay at the origin (so motion vectors stay correct); the snapped
## centre is passed as an instance uniform.

const LEVELS := 7
const BASE_SPACING := 1.5
const GRID := 128

var material: ShaderMaterial
var _levels: Array[MeshInstance3D] = []


func setup(data: TerrainData, sky: SkySystem) -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	material.set_shader_parameter("heightmap", data.height_texture)
	material.set_shader_parameter("normalmap", data.normal_texture)
	material.set_shader_parameter("maskmap", data.mask_texture)
	for set_name in ["grass:leafy_grass", "rock:rock_face_03", "sand:coast_sand_01", "gravel:gravelly_sand"]:
		var parts: PackedStringArray = set_name.split(":")
		var base := "res://assets/textures/%s/%s_" % [parts[1], parts[1]]
		material.set_shader_parameter(parts[0] + "_albedo", load(base + "diffuse.jpg"))
		material.set_shader_parameter(parts[0] + "_normal", load(base + "nor_gl.jpg"))
		material.set_shader_parameter(parts[0] + "_arm", load(base + "arm.jpg"))
	sky.register_material(material)
	if Game.args.has("terrain_debug"):
		material.set_shader_parameter("debug_mode", int(Game.arg("terrain_debug")))
	var full := build_grid(false)
	var ring := build_grid(true)
	for i in LEVELS:
		var mi := MeshInstance3D.new()
		mi.name = "TerrainL%d" % i
		mi.mesh = full if i == 0 else ring
		mi.material_override = material
		mi.custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		_levels.append(mi)
	_update(Vector3.ZERO)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_update(cam.global_position)


func _update(cam: Vector3) -> void:
	var centers: Array[Vector2] = []
	for i in LEVELS:
		var s := BASE_SPACING * pow(2.0, i)
		var c := Vector2(round(cam.x / (2.0 * s)) * 2.0 * s, round(cam.z / (2.0 * s)) * 2.0 * s)
		centers.append(c)
	for i in LEVELS:
		var s := BASE_SPACING * pow(2.0, i)
		var mi := _levels[i]
		mi.set_instance_shader_parameter("center", centers[i])
		mi.set_instance_shader_parameter("spacing", s)
		if i > 0:
			mi.set_instance_shader_parameter("inner_center", centers[i - 1])
			mi.set_instance_shader_parameter("inner_half", GRID * 0.5 * s * 0.5)
		else:
			mi.set_instance_shader_parameter("inner_half", 0.0)


static func build_grid(ring: bool) -> ArrayMesh:
	var half := GRID / 2
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for z in GRID + 1:
		for x in GRID + 1:
			verts.append(Vector3(x - half, 0.0, z - half))
	var hole_lo := half - 31
	var hole_hi := half + 31
	for z in GRID:
		for x in GRID:
			if ring and x >= hole_lo and x < hole_hi and z >= hole_lo and z < hole_hi:
				continue
			var a := z * (GRID + 1) + x
			var b := a + 1
			var c := a + GRID + 1
			var d := c + 1
			# Alternate the diagonal for a more isotropic triangulation.
			if (x + z) % 2 == 0:
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

class_name WaterRenderer
extends Node3D
## Ocean surface on a clipmap (same ring meshes as the terrain).

const LEVELS := 9
const BASE_SPACING := 1.5

var material: ShaderMaterial
var _levels: Array[MeshInstance3D] = []


func setup(data: TerrainData, sky: SkySystem) -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/water.gdshader")
	material.set_shader_parameter("heightmap", data.height_texture)
	material.set_shader_parameter("ripple_a", _noise_normal(512, 0.012, 7, FastNoiseLite.TYPE_SIMPLEX_SMOOTH))
	material.set_shader_parameter("ripple_b", _noise_normal(256, 0.03, 13, FastNoiseLite.TYPE_PERLIN))
	var foam := NoiseTexture2D.new()
	foam.width = 256
	foam.height = 256
	foam.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = 0.03
	fn.seed = 3
	foam.noise = fn
	foam.generate_mipmaps = true
	material.set_shader_parameter("foam_noise", foam)
	sky.register_material(material)
	var full := TerrainRenderer.build_grid(false)
	var ring := TerrainRenderer.build_grid(true)
	for i in LEVELS:
		var mi := MeshInstance3D.new()
		mi.name = "WaterL%d" % i
		mi.mesh = full if i == 0 else ring
		mi.material_override = material
		mi.custom_aabb = AABB(Vector3(-40000, -10, -40000), Vector3(80000, 20, 80000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_levels.append(mi)


func _noise_normal(size: int, freq: float, seed: int, type: int) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.seed = seed
	n.fractal_octaves = 4
	t.noise = n
	return t


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var centers: Array[Vector2] = []
	for i in LEVELS:
		var s := BASE_SPACING * pow(2.0, i)
		centers.append(Vector2(round(p.x / (2.0 * s)) * 2.0 * s, round(p.z / (2.0 * s)) * 2.0 * s))
	for i in LEVELS:
		var s := BASE_SPACING * pow(2.0, i)
		var mi := _levels[i]
		mi.set_instance_shader_parameter("center", centers[i])
		mi.set_instance_shader_parameter("spacing", s)
		mi.set_instance_shader_parameter("inner_center", centers[maxi(i - 1, 0)])
		mi.set_instance_shader_parameter("inner_half", 0.0 if i == 0 else 32.0 * s)

class_name GrassField
extends Node3D
## Meadow around the camera. Blades live in pre-built square tiles; every frame
## the visible tiles are written to a small table texture that the vertex shader
## reads by INSTANCE_ID. The MultiMesh buffers never change, so motion vectors
## stay those of static ground. Blades thin out and widen with distance so the
## three LODs meet without popping.

const COARSE := 8.0
const FINE := 4.0
const TABLE_WIDTH := 1024
const TILES := 3
# Blades per tile and segments per blade. LOD 2 tiles are twice as wide.
const BLADES: Array[int] = [2000, 460, 300]
const SEGMENTS: Array[int] = [4, 2, 1]

var material: ShaderMaterial
var near_radius := 20.0
var mid_radius := 58.0
var far_radius := 150.0

var _layers: Array[MultiMeshInstance3D] = []
var _decor: Array[MultiMeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _table: Image
var _table_tex: ImageTexture
var _table_data := PackedFloat32Array()
var _counts: Array[int] = [0, 0, 0]
var _coverage := PackedByteArray()
var _cover_size := 0
var _terrain: TerrainData
var _last_pos := Vector3(1e9, 0, 0)
var _last_dir := Vector3.ZERO
var _normals := {}


func setup(data: TerrainData) -> void:
	_terrain = data
	_build_coverage()
	_table_data.resize(TABLE_WIDTH * TILES * 4)
	_table = Image.create_from_data(TABLE_WIDTH, TILES, false, Image.FORMAT_RGBAF, _table_data.to_byte_array())
	_table_tex = ImageTexture.create_from_image(_table)
	var shader: Shader = preload("res://shaders/grass.gdshader")
	var wind := _noise_texture()
	for lod in TILES:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("heightmap", data.height_texture)
		mat.set_shader_parameter("eco_map", data.eco_texture)
		mat.set_shader_parameter("wind_noise", wind)
		mat.set_shader_parameter("patch_table", _table_tex)
		mat.set_shader_parameter("lod_row", lod)
		var size := COARSE if lod == 2 else FINE
		mat.set_shader_parameter("tile_size", size)
		_materials.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tile_mesh(BLADES[lod], SEGMENTS[lod], size, 7 + lod)
		mm.instance_count = TABLE_WIDTH
		for i in TABLE_WIDTH:
			mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))
		add_child(inst)
		_layers.append(inst)
	material = _materials[0]
	_build_decor(wind)
	_apply_radii()


## Quality presets pass 90..150; 135 is the shipped "wysoka".
func set_density(side: int) -> void:
	var k := clampf(side / 135.0, 0.6, 1.2)
	near_radius = 20.0 * k
	mid_radius = 58.0 * k
	far_radius = 150.0 * k
	_apply_radii()


func register_sky(sky: SkySystem) -> void:
	for mat in _materials:
		sky.register_material(mat)


func _apply_radii() -> void:
	for mat in _materials:
		mat.set_shader_parameter("near_radius", near_radius)
		mat.set_shader_parameter("mid_radius", mid_radius)
		mat.set_shader_parameter("far_radius", far_radius)
	_last_pos = Vector3(1e9, 0, 0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var pos := cam.global_position
	var dir := -cam.global_basis.z
	if pos.distance_squared_to(_last_pos) < 0.04 and dir.dot(_last_dir) > 0.9995:
		return
	_last_pos = pos
	_last_dir = dir
	_refresh(pos, dir, cam.fov)


func _refresh(pos: Vector3, dir: Vector3, fov: float) -> void:
	var flat := Vector2(dir.x, dir.z)
	var looking_down := flat.length() < 0.4
	flat = flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var half_h := atan(tan(deg_to_rad(fov) * 0.5) * aspect)
	var range_cells := int(ceil(far_radius / COARSE))
	var cx := int(floor(pos.x / COARSE))
	var cz := int(floor(pos.z / COARSE))
	var half_world := TerrainData.WORLD * 0.5
	_counts = [0, 0, 0]
	var margin := COARSE * 0.72
	for gz in range(cz - range_cells, cz + range_cells + 1):
		var wz := (gz + 0.5) * COARSE
		for gx in range(cx - range_cells, cx + range_cells + 1):
			var wx := (gx + 0.5) * COARSE
			var dx := wx - pos.x
			var dz := wz - pos.z
			var d2 := dx * dx + dz * dz
			if d2 > (far_radius + margin) * (far_radius + margin):
				continue
			var d := sqrt(d2)
			if not looking_down and d > 14.0:
				var cone := half_h + asin(minf(margin / d, 1.0)) + 0.04
				if (dx * flat.x + dz * flat.y) / d < cos(cone):
					continue
			var ci := int((wx + half_world) / COARSE)
			var cj := int((wz + half_world) / COARSE)
			if ci < 0 or cj < 0 or ci >= _cover_size or cj >= _cover_size or _coverage[cj * _cover_size + ci] == 0:
				continue
			if d > mid_radius + margin:
				_emit(2, wx - COARSE * 0.5, wz - COARSE * 0.5)
				continue
			for k in 4:
				var fx := wx - FINE + (k & 1) * FINE
				var fz := wz - FINE + (k >> 1) * FINE
				var fd := Vector2(fx + FINE * 0.5 - pos.x, fz + FINE * 0.5 - pos.z).length()
				_emit(0 if fd < near_radius + FINE * 0.72 else 1, fx, fz)
	_table = Image.create_from_data(TABLE_WIDTH, TILES, false, Image.FORMAT_RGBAF, _table_data.to_byte_array())
	_table_tex.update(_table)
	for lod in TILES:
		_layers[lod].multimesh.visible_instance_count = _counts[lod]
	for i in _decor.size():
		_decor[i].multimesh.visible_instance_count = _counts[i]


func _emit(lod: int, x: float, z: float) -> void:
	var n := _counts[lod]
	if n >= TABLE_WIDTH:
		return
	var key := Vector2i(int(floor(x)), int(floor(z)))
	var nrm: Vector2 = _normals.get(key, Vector2.INF)
	if nrm == Vector2.INF:
		var size := COARSE if lod == 2 else FINE
		var v := _terrain.normal_at(x + size * 0.5, z + size * 0.5)
		nrm = Vector2(v.x, v.z)
		if _normals.size() > 60000:
			_normals.clear()
		_normals[key] = nrm
	var i := (lod * TABLE_WIDTH + n) * 4
	_table_data[i] = x
	_table_data[i + 1] = z
	_table_data[i + 2] = nrm.x
	_table_data[i + 3] = nrm.y
	_counts[lod] = n + 1


func _build_coverage() -> void:
	# One byte per coarse cell: does anything grow here at all?
	_cover_size = int(TerrainData.WORLD / COARSE)
	var img := _terrain.eco_image.duplicate() as Image
	img.resize(_cover_size, _cover_size, Image.INTERPOLATE_BILINEAR)
	var src := img.get_data()
	_coverage.resize(_cover_size * _cover_size)
	for i in _coverage.size():
		_coverage[i] = 1 if src[i * 4] > 6 else 0


func _build_decor(wind: Texture2D) -> void:
	var mesh := _decor_mesh(11)
	for row in 2:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/meadow_decor.gdshader")
		mat.set_shader_parameter("heightmap", _terrain.height_texture)
		mat.set_shader_parameter("eco_map", _terrain.eco_texture)
		mat.set_shader_parameter("wind_noise", wind)
		mat.set_shader_parameter("patch_table", _table_tex)
		mat.set_shader_parameter("seeds_albedo", load("res://assets/foliage/baked/seeds_albedo.png"))
		mat.set_shader_parameter("lod_row", row)
		mat.set_shader_parameter("tile_size", FINE)
		mat.set_shader_parameter("fade_far", mid_radius)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = TABLE_WIDTH
		for i in TABLE_WIDTH:
			mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.visible_instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))
		add_child(inst)
		_decor.append(inst)


func _decor_mesh(seed_value: int) -> ArrayMesh:
	# CUSTOM0: xy = root in the tile, z = 0 seed card, 1 flower head, 2 stem.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var buf := {"v": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "c": PackedColorArray(), "cu": PackedFloat32Array(), "i": PackedInt32Array()}
	for n in 44:
		var root := Vector2(rng.randf(), rng.randf()) * FINE
		var col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var h := rng.randf_range(0.72, 1.12)
		var w := h * 0.17
		var cell := rng.randi_range(0, 3)
		var uv_rect := Rect2(cell * 0.25 + 0.015, 0.03, 0.22, 0.94)
		var base: int = buf["v"].size()
		for k in 4:
			var t := float(k >> 1)
			var s := float(k & 1) * 2.0 - 1.0
			buf["v"].append(Vector3(s * w, t * h, 0.0))
			buf["uv"].append(uv_rect.position + Vector2((s + 1.0) * 0.5, 1.0 - t) * uv_rect.size)
			buf["uv2"].append(Vector2.ZERO)
			buf["c"].append(col)
			buf["cu"].append_array([root.x, root.y, 0.0, 0.0])
		buf["i"].append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	for n in 70:
		var root := Vector2(rng.randf(), rng.randf()) * FINE
		var col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var h := rng.randf_range(0.26, 0.5)
		var base: int = buf["v"].size()
		for k in 4:
			var t := float(k >> 1)
			var s := float(k & 1) * 2.0 - 1.0
			buf["v"].append(Vector3(s * 0.006, t * h, 0.0))
			buf["uv"].append(Vector2.ZERO)
			buf["uv2"].append(Vector2.ZERO)
			buf["c"].append(col)
			buf["cu"].append_array([root.x, root.y, 2.0, 0.0])
		buf["i"].append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
		var r := rng.randf_range(0.03, 0.05)
		var tilt := rng.randf_range(0.2, 0.75)
		base = buf["v"].size()
		for k in 4:
			var a := float(k & 1) * 2.0 - 1.0
			var b := float(k >> 1) * 2.0 - 1.0
			buf["v"].append(Vector3(a * r, h + b * r * tilt, b * r * sqrt(1.0 - tilt * tilt)))
			buf["uv"].append(Vector2.ZERO)
			buf["uv2"].append(Vector2(a, b))
			buf["c"].append(col)
			buf["cu"].append_array([root.x, root.y, 1.0, 0.0])
		buf["i"].append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buf["v"]
	arrays[Mesh.ARRAY_TEX_UV] = buf["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = buf["uv2"]
	arrays[Mesh.ARRAY_COLOR] = buf["c"]
	arrays[Mesh.ARRAY_CUSTOM0] = buf["cu"]
	arrays[Mesh.ARRAY_INDEX] = buf["i"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m


func _noise_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.016
	noise.fractal_octaves = 3
	var img := noise.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _tile_mesh(blades: int, segs: int, size: float, seed_value: int) -> ArrayMesh:
	# VERTEX: x,z = blade root in the tile, y = position along the blade.
	# UV: x = side (-1..1), y = rank (blades drop out from high rank to low).
	# COLOR: per-blade random numbers. CUSTOM0.x: 0 grass, 1 broad leaf.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for b in blades:
		# Clumped roots read as tussocks rather than even carpet.
		var clump := Vector2(rng.randf(), rng.randf())
		if b > 0 and b % 7 != 0:
			var last := verts[verts.size() - 1]
			clump = Vector2(last.x / size, last.z / size) + Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05)) * 4.0 / size
			clump = Vector2(fposmod(clump.x, 1.0), fposmod(clump.y, 1.0))
		var root := clump * size
		var rank := (b + 0.5) / blades
		var col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var base := verts.size()
		for s in segs + 1:
			var t := float(s) / segs
			if s == segs:
				verts.append(Vector3(root.x, 1.0, root.y))
				uvs.append(Vector2(0.0, rank))
				cols.append(col)
				break
			verts.append(Vector3(root.x, t, root.y))
			verts.append(Vector3(root.x, t, root.y))
			uvs.append(Vector2(-1.0, rank))
			uvs.append(Vector2(1.0, rank))
			cols.append(col)
			cols.append(col)
		for s in segs - 1:
			var a := base + s * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		var a2 := base + (segs - 1) * 2
		idx.append_array([a2, a2 + 2, a2 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

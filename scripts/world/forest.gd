class_name Forest
extends Node3D
## All trees on the island. Close trees are real meshes in two LODs, drawn through
## MultiMeshes whose instances read their placement from a table texture (so the
## buffers never change and motion vectors stay correct); far trees are impostor
## quads baked here at startup from the same meshes.

const VARIANTS: Array[String] = ["oak", "oak", "oak", "round", "round", "round", "olive", "olive", "pine", "pine", "pine", "pine", "bush", "bush", "bush"]
const FIRST_BUSH := 12
const CELL := 60.0
const TABLE_WIDTH := 512
const IMPOSTOR_VIEWS := 8
const IMPOSTOR_SIZE := 256
const BODY_POOL := 14

const ROWS_PER_VARIANT := 4

var lod_r0 := 32.0
var lod_r1 := 74.0
var shadow_near := 42.0
var shadow_range := 125.0

var tree_count := 0

var _data: TerrainData
var _meshes: Array[Dictionary] = []
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _z := PackedFloat32Array()
var _s := PackedFloat32Array()
var _v := PackedByteArray()
var _grid := {}
var _table: Image
var _table_tex: ImageTexture
var _table_data := PackedFloat32Array()
var _layers: Array[MultiMeshInstance3D] = []
var _counts := PackedInt32Array()
var _leaf_mats := {}
var _bark_mats := {}
var _last_pos := Vector3(1e9, 0, 0)
var _last_dir := Vector3.ZERO
var _bodies: Array[StaticBody3D] = []
var _body_timer := 0.0
var _impostor_mat: ShaderMaterial


func build(data: TerrainData, extra: Array[Vector3]) -> void:
	_data = data
	var t0 := Time.get_ticks_msec()
	for i in VARIANTS.size():
		_meshes.append(TreeGen.make(VARIANTS[i], 1000 + i * 37))
	var t1 := Time.get_ticks_msec()
	_make_materials()
	_scatter(extra)
	var t2 := Time.get_ticks_msec()
	_build_layers()
	await _build_impostors()
	_build_bodies()
	print("forest: %d trees, meshes %d ms, scatter %d ms, layers+impostors %d ms" % [tree_count, t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])


func _make_materials() -> void:
	var tints := {
		"oak": [Vector3(0.37, 0.47, 0.25), Vector3(0.28, 0.4, 0.19)],
		"round": [Vector3(0.36, 0.48, 0.23), Vector3(0.26, 0.4, 0.17)],
		"olive": [Vector3(0.42, 0.47, 0.36), Vector3(0.33, 0.38, 0.29)],
		"pine": [Vector3(0.42, 0.52, 0.36), Vector3(0.32, 0.43, 0.29)],
		"bush": [Vector3(0.24, 0.33, 0.17), Vector3(0.19, 0.28, 0.12)],
	}
	_table_data.resize(TABLE_WIDTH * VARIANTS.size() * ROWS_PER_VARIANT * 4)
	_table = Image.create_from_data(TABLE_WIDTH, VARIANTS.size() * ROWS_PER_VARIANT, false, Image.FORMAT_RGBAF, _table_data.to_byte_array())
	_table_tex = ImageTexture.create_from_image(_table)
	for species in TreeGen.SPECIES:
		var p: Dictionary = TreeGen.SPECIES[species]
		var bark: String = p["bark"]
		var base := "res://assets/textures/%s/%s_" % [bark, bark]
		for lod in 3:
			var bm := ShaderMaterial.new()
			bm.shader = preload("res://shaders/tree_bark.gdshader")
			bm.set_shader_parameter("bark_albedo", load(base + "diffuse_2k.jpg"))
			bm.set_shader_parameter("bark_normal", load(base + "nor_gl_2k.jpg"))
			bm.set_shader_parameter("bark_arm", load(base + "arm_2k.jpg"))
			var lm := ShaderMaterial.new()
			lm.shader = preload("res://shaders/tree_leaf.gdshader")
			lm.set_shader_parameter("leaf_albedo", load("res://assets/foliage/baked/%s_albedo.png" % p["atlas"]))
			lm.set_shader_parameter("leaf_normal", load("res://assets/foliage/baked/%s_normal.png" % p["atlas"]))
			lm.set_shader_parameter("tint_a", tints[species][0])
			lm.set_shader_parameter("tint_b", tints[species][1])
			for m in [bm, lm]:
				m.set_shader_parameter("tree_table", _table_tex)
				m.set_shader_parameter("lod_kind", lod)
				m.set_shader_parameter("lod_r0", lod_r0)
				m.set_shader_parameter("lod_r1", lod_r1)
			_bark_mats["%s%d" % [species, lod]] = bm
			_leaf_mats["%s%d" % [species, lod]] = lm


func _scatter(extra: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var size := TerrainData.ECO_SIZE
	var eco := _data.eco_image.get_data()
	var half := TerrainData.WORLD * 0.5
	var texel := TerrainData.WORLD / size
	var spacing := 14.5
	var steps := int(TerrainData.WORLD / spacing)
	for gz in steps:
		for gx in steps:
			var x := (gx + 0.5) * spacing - half + rng.randf_range(-5.0, 5.0)
			var z := (gz + 0.5) * spacing - half + rng.randf_range(-5.0, 5.0)
			var px := clampi(int((x + half) / texel), 0, size - 1)
			var pz := clampi(int((z + half) / texel), 0, size - 1)
			var i := (pz * size + px) * 4
			var forest := eco[i + 1] / 255.0
			var grass := eco[i] / 255.0
			var keep := forest * 0.92
			var lone := false
			if forest < 0.08 and grass > 0.4 and rng.randf() < 0.0035:
				keep = 1.0
				lone = true
			if rng.randf() >= keep:
				continue
			var h := _data.height_at(x, z)
			if h < 5.5:
				continue
			_add(x, h, z, _pick(x, z, h, lone, rng), rng.randf_range(0.72, 1.18))
	# Bushes on the open slopes and as undergrowth in the woods.
	var bush_spacing := 11.0
	var bush_steps := int(TerrainData.WORLD / bush_spacing)
	for gz in bush_steps:
		for gx in bush_steps:
			var x := (gx + 0.5) * bush_spacing - half + rng.randf_range(-4.5, 4.5)
			var z := (gz + 0.5) * bush_spacing - half + rng.randf_range(-4.5, 4.5)
			var px := clampi(int((x + half) / texel), 0, size - 1)
			var pz := clampi(int((z + half) / texel), 0, size - 1)
			var i := (pz * size + px) * 4
			# Thickets, not an even sprinkle.
			var thicket := sin(x * 0.0127 + sin(z * 0.0091) * 2.0) * cos(z * 0.0143 - sin(x * 0.0071) * 2.0) * 0.5 + 0.5
			thicket = clampf((thicket - 0.42) * 3.0, 0.0, 1.0)
			var keep := eco[i + 2] / 255.0 * 0.75 * thicket + eco[i + 1] / 255.0 * 0.5
			if rng.randf() >= keep:
				continue
			var h := _data.height_at(x, z)
			if h < 5.0:
				continue
			_add(x, h, z, FIRST_BUSH + rng.randi_range(0, 2), rng.randf_range(0.6, 1.3))
	for p in extra:
		var h := _data.height_at(p.x, p.z)
		_add(p.x, h, p.z, 6 if rng.randf() < 0.5 else 0, rng.randf_range(0.8, 1.05))


func _pick(x: float, z: float, h: float, lone: bool, rng: RandomNumberGenerator) -> int:
	var n := sin(x * 0.0023 + 1.1) * cos(z * 0.0019 - 0.6) + sin((x + z) * 0.0071) * 0.3
	var species := "oak"
	if lone:
		species = "olive" if rng.randf() < 0.55 else "oak"
	elif h > 190.0 or n > 0.34:
		species = "pine"
	elif n < -0.22:
		species = "round"
	var options: Array[int] = []
	for i in VARIANTS.size():
		if VARIANTS[i] == species:
			options.append(i)
	return options[rng.randi() % options.size()]


func _add(x: float, h: float, z: float, variant: int, scale_k: float) -> void:
	var i := _x.size()
	_x.append(x)
	_y.append(h - 0.1)
	_z.append(z)
	_s.append(scale_k)
	_v.append(variant)
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if not _grid.has(key):
		_grid[key] = PackedInt32Array()
	var arr: PackedInt32Array = _grid[key]
	arr.append(i)
	_grid[key] = arr
	tree_count += 1


func _build_layers() -> void:
	var rows := VARIANTS.size() * ROWS_PER_VARIANT
	_counts.resize(rows)
	var blob_mat := ShaderMaterial.new()
	blob_mat.shader = preload("res://shaders/tree_shadow.gdshader")
	blob_mat.set_shader_parameter("tree_table", _table_tex)
	blob_mat.set_shader_parameter("lod_kind", 2)
	var identity := PackedFloat32Array()
	identity.resize(TABLE_WIDTH * 12)
	for i in TABLE_WIDTH:
		identity[i * 12] = 1.0
		identity[i * 12 + 5] = 1.0
		identity[i * 12 + 10] = 1.0
	for v in VARIANTS.size():
		var species := VARIANTS[v]
		for lod in ROWS_PER_VARIANT:
			var mesh: ArrayMesh
			if lod == 3:
				mesh = _meshes[v]["blobs"]
				mesh.surface_set_material(0, blob_mat)
			else:
				mesh = (_meshes[v]["lod0"] if lod == 0 else _meshes[v]["lod1"]).duplicate()
				mesh.surface_set_material(0, _bark_mats["%s%d" % [species, lod]])
				mesh.surface_set_material(1, _leaf_mats["%s%d" % [species, lod]])
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = TABLE_WIDTH
			mm.buffer = identity
			mm.visible_instance_count = 0
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if lod >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			inst.set_instance_shader_parameter("table_row", v * ROWS_PER_VARIANT + lod)
			add_child(inst)
			_layers.append(inst)


func _build_impostors() -> void:
	var rows := VARIANTS.size()
	var vp := SubViewport.new()
	var vp_size := Vector2i(IMPOSTOR_VIEWS * IMPOSTOR_SIZE, rows * IMPOSTOR_SIZE)
	vp.size = vp_size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = float(rows)
	cam.near = 0.1
	cam.far = 200.0
	cam.position = Vector3(IMPOSTOR_VIEWS * 0.5, rows * 0.5, 100.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.14, 0.06)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	var mats: Array[ShaderMaterial] = []
	var sizes := PackedFloat32Array()
	for v in rows:
		var d: Dictionary = _meshes[v]
		var size: float = maxf(d["height"], d["radius"] * 2.0)
		sizes.append(size)
		var species := VARIANTS[v]
		var p: Dictionary = TreeGen.SPECIES[species]
		var leaf_mat := ShaderMaterial.new()
		leaf_mat.shader = preload("res://shaders/bake/tree_impostor_bake.gdshader")
		leaf_mat.set_shader_parameter("albedo_tex", load("res://assets/foliage/baked/%s_albedo.png" % p["atlas"]))
		var t: Variant = _leaf_mats[species + "0"].get_shader_parameter("tint_a")
		leaf_mat.set_shader_parameter("tint", t)
		var bark_mat := ShaderMaterial.new()
		bark_mat.shader = preload("res://shaders/bake/tree_impostor_bake.gdshader")
		bark_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/%s/%s_diffuse_2k.jpg" % [p["bark"], p["bark"]]))
		bark_mat.set_shader_parameter("leaf", false)
		mats.append(leaf_mat)
		mats.append(bark_mat)
		for k in IMPOSTOR_VIEWS:
			var mi := MeshInstance3D.new()
			mi.mesh = d["lod0"]
			mi.set_surface_override_material(0, bark_mat)
			mi.set_surface_override_material(1, leaf_mat)
			mi.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 50, 60))
			var s := 1.0 / size
			mi.transform = Transform3D(Basis(Vector3.UP, TAU * k / IMPOSTOR_VIEWS).scaled(Vector3.ONE * s), Vector3(k + 0.5, rows - v - 1.0, 0.0))
			vp.add_child(mi)
	add_child(vp)
	var textures: Array[ImageTexture] = []
	await RenderingServer.frame_post_draw
	for mode in 2:
		for m in mats:
			m.set_shader_parameter("mode", mode)
		env.background_color = Color(0.1, 0.14, 0.06) if mode == 0 else Color(0.5, 0.5, 1.0)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if Game.args.has("dump_forest"):
			img.save_png("res://dev/out/impostor_%d.png" % mode)
		img.generate_mipmaps()
		textures.append(ImageTexture.create_from_image(img))
	vp.queue_free()

	var quad := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/tree_impostor.gdshader")
	mat.set_shader_parameter("atlas_albedo", textures[0])
	mat.set_shader_parameter("atlas_normal", textures[1])
	mat.set_shader_parameter("rows", float(rows))
	mat.set_shader_parameter("views", float(IMPOSTOR_VIEWS))
	mat.set_shader_parameter("atlas_size", Vector2(vp_size))
	mat.set_shader_parameter("fade_near", lod_r1 - 20.0)
	mat.set_shader_parameter("fade_far", lod_r1)
	_impostor_mat = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = tree_count
	var buf := PackedFloat32Array()
	buf.resize(tree_count * 16)
	for i in tree_count:
		var k := i * 16
		var v := int(_v[i])
		buf[k] = 1.0
		buf[k + 3] = _x[i]
		buf[k + 5] = 1.0
		buf[k + 7] = _y[i]
		buf[k + 10] = 1.0
		buf[k + 11] = _z[i]
		buf[k + 12] = sizes[v] * _s[i]
		buf[k + 13] = float(v)
		buf[k + 14] = fposmod(_x[i] * 0.137 + _z[i] * 0.331, 1.0) * TAU
		buf[k + 15] = fposmod(_x[i] * 0.77 + _z[i] * 0.41, 1.0)
	mm.buffer = buf
	var inst := MultiMeshInstance3D.new()
	inst.name = "Impostors"
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.custom_aabb = AABB(Vector3(-8000, -300, -8000), Vector3(16000, 1400, 16000))
	add_child(inst)


## Distances scale with the quality preset: 1.0 is "wysoka".
func set_quality(k: float) -> void:
	lod_r0 = 32.0 * k
	lod_r1 = 74.0 * k
	shadow_near = 42.0 * k
	shadow_range = 125.0 * k
	for key in _leaf_mats:
		for m: ShaderMaterial in [_leaf_mats[key], _bark_mats[key]]:
			m.set_shader_parameter("lod_r0", lod_r0)
			m.set_shader_parameter("lod_r1", lod_r1)
	if _impostor_mat:
		_impostor_mat.set_shader_parameter("fade_near", lod_r1 - 20.0)
		_impostor_mat.set_shader_parameter("fade_far", lod_r1)
	_last_pos = Vector3(1e9, 0, 0)


func _build_bodies() -> void:
	for i in BODY_POOL:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.height = 6.0
		shape.radius = 0.4
		cs.shape = shape
		body.add_child(cs)
		body.position = Vector3(0, -500, 0)
		add_child(body)
		_bodies.append(body)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pos := cam.global_position
	var dir := -cam.global_basis.z
	if pos.distance_squared_to(_last_pos) > 9.0 or dir.dot(_last_dir) < 0.985:
		_last_pos = pos
		_last_dir = dir
		_refresh(pos, dir, cam.fov)
	_body_timer -= delta
	if _body_timer <= 0.0 and Game.car:
		_body_timer = 0.25
		_place_bodies(Game.car.global_position)


func _refresh(pos: Vector3, dir: Vector3, fov: float) -> void:
	_counts.fill(0)
	var flat := Vector2(dir.x, dir.z)
	var looking_down := flat.length() < 0.35
	flat = flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
	var aspect := get_viewport().get_visible_rect().size.aspect()
	# Wider than the view: the table only refreshes every few metres or degrees.
	var cone_cos := cos(atan(tan(deg_to_rad(fov) * 0.5) * aspect) + 0.42)
	var reach := maxf(lod_r1, shadow_range) + 8.0
	var cells := int(ceil(reach / CELL))
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	var r0 := lod_r0
	var r0_in := lod_r0 - 9.0
	var r1 := lod_r1
	var row_width := TABLE_WIDTH
	for gz in range(cz - cells, cz + cells + 1):
		for gx in range(cx - cells, cx + cells + 1):
			var arr: Variant = _grid.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i: int in arr:
				var dx := _x[i] - pos.x
				var dz := _z[i] - pos.z
				var d := sqrt(dx * dx + dz * dz)
				if d > reach:
					continue
				var v := int(_v[i])
				var row := v * ROWS_PER_VARIANT
				var in_view := looking_down or d < 18.0 or (dx * flat.x + dz * flat.y) / d > cone_cos
				if in_view and d < r0:
					_write(row, i, row_width)
				if in_view and d > r0_in and d < r1:
					_write(row + 1, i, row_width)
				if d < shadow_near:
					_write(row + 2, i, row_width)
				elif d < shadow_range and v < FIRST_BUSH:
					_write(row + 3, i, row_width)
	_table = Image.create_from_data(TABLE_WIDTH, VARIANTS.size() * ROWS_PER_VARIANT, false, Image.FORMAT_RGBAF, _table_data.to_byte_array())
	_table_tex.update(_table)
	for r in _layers.size():
		_layers[r].multimesh.visible_instance_count = _counts[r]


func _write(row: int, i: int, row_width: int) -> void:
	var n := _counts[row]
	if n >= row_width:
		return
	var k := (row * row_width + n) * 4
	_table_data[k] = _x[i]
	_table_data[k + 1] = _y[i]
	_table_data[k + 2] = _z[i]
	_table_data[k + 3] = _s[i]
	_counts[row] = n + 1


func _place_bodies(at: Vector3) -> void:
	var near: Array = []
	var cx := floori(at.x / CELL)
	var cz := floori(at.z / CELL)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			var arr: Variant = _grid.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i: int in arr:
				var dx := _x[i] - at.x
				var dz := _z[i] - at.z
				var d2 := dx * dx + dz * dz
				if d2 < 2500.0 and int(_v[i]) < FIRST_BUSH:
					near.append([d2, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for b in _bodies.size():
		if b < near.size():
			var i: int = near[b][1]
			_bodies[b].position = Vector3(_x[i], _y[i] + 3.0, _z[i])
		else:
			_bodies[b].position = Vector3(0, -500, 0)

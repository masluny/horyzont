class_name FoliageBaker
extends Node
## Dev tool: builds leaf-spray atlases from the scanned leaves in assets/foliage/src.
## godot --path . -- --bake_foliage
## Writes assets/foliage/baked/<species>_albedo.png and _normal.png (four sprays).

const OUT := "res://assets/foliage/baked/"
const SIZE := 2048
const SPECIES := {
	"oak": {"set": "LeafSet016", "leaf": 0.23, "side": 11, "per_twig": 9, "twig": 0.95, "fold": 0.2},
	"round": {"set": "LeafSet024", "leaf": 0.2, "side": 12, "per_twig": 11, "twig": 0.95, "fold": 0.25},
	"olive": {"set": "LeafSet020", "leaf": 0.24, "side": 12, "per_twig": 13, "twig": 0.95, "fold": 0.15},
	"pine": {"set": "", "leaf": 0.34, "side": 9, "per_twig": 170, "twig": 0.9, "fold": 0.0},
}

var _rng := RandomNumberGenerator.new()
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _tangents := PackedFloat32Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _idx := PackedInt32Array()


func run() -> void:
	_rng.seed = 2207
	for id in SPECIES:
		await _bake(id, SPECIES[id])
		print("baked ", id)
	get_tree().quit()


func _bake(id: String, cfg: Dictionary) -> void:
	var rects: Array[Rect2] = []
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bake/foliage_card.gdshader")
	if cfg["set"] != "":
		var base: String = "res://assets/foliage/src/%s/%s_2K-JPG_" % [cfg["set"], cfg["set"]]
		var opacity := Image.load_from_file(ProjectSettings.globalize_path(base + "Opacity.jpg"))
		rects = _find_leaves(opacity)
		print(id, " leaves: ", rects.size())
		mat.set_shader_parameter("leaf_color", load(base + "Color.jpg"))
		mat.set_shader_parameter("leaf_opacity", load(base + "Opacity.jpg"))
		mat.set_shader_parameter("leaf_normal", load(base + "NormalGL.jpg"))
	_clear()
	for row in 2:
		for col in 2:
			var c := Vector2(col * 2.0 - 1.0, 1.0 - row * 2.0)
			_spray(c, cfg, rects, row * 2 + col)
	var mesh := _commit()

	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE) * 2
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.near = 0.1
	cam.far = 20.0
	cam.position = Vector3(0, 0, 8)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.28, 0.1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	vp.add_child(mi)
	add_child(vp)
	await RenderingServer.frame_post_draw
	for pass_i in 2:
		mat.set_shader_parameter("mode", pass_i)
		env.background_color = Color(0.2, 0.28, 0.1) if pass_i == 0 else Color(0.5, 0.5, 1.0)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		if pass_i == 0:
			img.fix_alpha_edges()
		img.save_png(OUT + id + ("_albedo.png" if pass_i == 0 else "_normal.png"))
	vp.queue_free()


## Bounding boxes of the separate leaves in an opacity scan.
func _find_leaves(opacity: Image) -> Array[Rect2]:
	var n := 192
	var small := opacity.duplicate() as Image
	small.convert(Image.FORMAT_L8)
	small.resize(n, n, Image.INTERPOLATE_BILINEAR)
	var seen := PackedByteArray()
	seen.resize(n * n)
	var src := small.get_data()
	var out: Array[Rect2] = []
	for start in n * n:
		if seen[start] != 0 or src[start] < 110:
			continue
		var stack := [start]
		seen[start] = 1
		var lo := Vector2i(n, n)
		var hi := Vector2i(-1, -1)
		var area := 0
		while not stack.is_empty():
			var p: int = stack.pop_back()
			var x := p % n
			var y := p / n
			area += 1
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			for d in [-1, 1, -n, n]:
				var q: int = p + d
				if q < 0 or q >= n * n or seen[q] != 0 or src[q] < 110:
					continue
				seen[q] = 1
				stack.append(q)
		if area > 40:
			out.append(Rect2(Vector2(lo) / n, Vector2(hi - lo + Vector2i.ONE) / n).grow(0.004))
	return out


func _spray(c: Vector2, cfg: Dictionary, rects: Array[Rect2], variant: int) -> void:
	var sides: int = cfg["side"] + _rng.randi_range(-1, 1)
	var is_pine: bool = rects.is_empty()
	var base := Vector3(c.x + _rng.randf_range(-0.05, 0.05), c.y - 0.95, 0.0)
	var dir := Vector2(_rng.randf_range(-0.1, 0.1), 1.0).normalized()
	var length := 1.8
	var spread := 1.25 if variant < 2 else 1.5
	var stem_pts: Array[Vector3] = []
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var bend := sin(t * 3.1 + variant) * 0.09
		stem_pts.append(base + Vector3(dir.x * t * length + bend, dir.y * t * length, 0.0))
	_stem(stem_pts, 0.012, 0.004, Color(0.2, 0.15, 0.1))
	for s in sides:
		var t := 0.1 + 0.86 * float(s) / sides
		var at := stem_pts[int(t * steps)]
		var side := -1.0 if s % 2 == 0 else 1.0
		var ang := (0.62 + _rng.randf_range(-0.14, 0.14)) * side * spread
		var twig_len: float = cfg["twig"] * (1.0 - t * 0.68) * _rng.randf_range(0.8, 1.1)
		var d := Vector2(sin(ang), cos(ang))
		var tip := at + Vector3(d.x, d.y, 0.0) * twig_len
		var tp: Array[Vector3] = []
		var z_off := _rng.randf_range(-0.2, 0.2)
		for k in 7:
			var u := k / 6.0
			var p := at.lerp(tip, u)
			p += Vector3(0.0, -u * u * 0.07, z_off * u)
			tp.append(p)
		_stem(tp, 0.007, 0.002, Color(0.22, 0.17, 0.11))
		if is_pine:
			_needles(tp, cfg["per_twig"], cfg["leaf"])
		else:
			_leaves(tp, cfg, rects, 1.0)
	if not is_pine:
		_leaves(stem_pts.slice(steps * 2 / 3), cfg, rects, 1.1)
	else:
		_needles(stem_pts.slice(steps * 1 / 2), cfg["per_twig"], cfg["leaf"])


func _leaves(pts: Array[Vector3], cfg: Dictionary, rects: Array[Rect2], scale_k: float) -> void:
	var n: int = cfg["per_twig"]
	for i in n:
		var u := (float(i) + 0.5) / n
		var f := u * (pts.size() - 1)
		var a := pts[int(f)]
		var b := pts[mini(int(f) + 1, pts.size() - 1)]
		var at := a.lerp(b, f - floorf(f))
		var along := (pts[pts.size() - 1] - pts[0]).normalized()
		var side := -1.0 if i % 2 == 0 else 1.0
		var ang := _rng.randf_range(0.5, 1.05) * side * (1.0 - u * 0.55)
		var perp := Vector3(-along.y, along.x, 0.0)
		var dir := (along * cos(ang) + perp * sin(ang)).normalized()
		dir.z = _rng.randf_range(-0.45, 0.45)
		dir = dir.normalized()
		var size: float = cfg["leaf"] * scale_k * _rng.randf_range(0.8, 1.15) * (1.0 - u * 0.25)
		var r := rects[_rng.randi() % rects.size()]
		var shade := _rng.randf_range(0.72, 1.08)
		var depth_shade := clampf(0.8 + at.z * 0.4 + _rng.randf_range(-0.08, 0.08), 0.55, 1.05)
		var tint := Color(_rng.randf_range(0.94, 1.06), _rng.randf_range(0.97, 1.03), _rng.randf_range(0.88, 1.05), shade * depth_shade)
		_leaf(at, dir, _rng.randf_range(-0.7, 0.7), size, r, tint, cfg["fold"])


func _leaf(at: Vector3, dir: Vector3, roll: float, size: float, r: Rect2, tint: Color, fold: float) -> void:
	var w_axis := dir.cross(Vector3(0, 0, 1)).normalized().rotated(dir, roll)
	var aspect := r.size.x / r.size.y
	var half := size * aspect * 0.5
	var nrm := w_axis.cross(dir).normalized()
	if nrm.z < 0.0:
		nrm = -nrm
	var base := _verts.size()
	var droop := _rng.randf_range(0.0, 0.14)
	for row in 3:
		var t := row / 2.0
		var p := at + dir * size * t - nrm * droop * size * t * t
		for col in 3:
			var s := col / 2.0
			var lateral := (s - 0.5) * 2.0
			var v := p + w_axis * half * lateral + nrm * absf(lateral) * half * fold
			_verts.append(v)
			_normals.append((nrm - w_axis * lateral * fold * 1.2).normalized())
			_tangents.append_array([w_axis.x, w_axis.y, w_axis.z, 1.0])
			_uvs.append(r.position + Vector2(s, 1.0 - t) * r.size)
			_colors.append(tint)
	for row in 2:
		for col in 2:
			var a := base + row * 3 + col
			_idx.append_array([a, a + 1, a + 3, a + 1, a + 4, a + 3])


func _needles(pts: Array[Vector3], count: int, length: float) -> void:
	for i in count:
		var u := _rng.randf()
		var f := u * (pts.size() - 1)
		var a := pts[int(f)]
		var b := pts[mini(int(f) + 1, pts.size() - 1)]
		var at := a.lerp(b, f - floorf(f))
		var along := (pts[pts.size() - 1] - pts[0]).normalized()
		var perp := Vector3(-along.y, along.x, 0.0)
		var ang := _rng.randf_range(-1.05, 1.05)
		var dir := (along * cos(ang) * 0.9 + perp * sin(ang)).normalized()
		dir.z = _rng.randf_range(-0.7, 0.7)
		dir = dir.normalized()
		var len_k := length * _rng.randf_range(0.65, 1.05)
		var g := _rng.randf_range(0.12, 0.34)
		var col := Color(g * 0.62, g * 0.92, g * 0.42, 1.0)
		_ribbon([at, at + dir * len_k * 0.5, at + dir * len_k], 0.0062, 0.0008, col)


func _stem(pts: Array[Vector3], r0: float, r1: float, col: Color) -> void:
	_ribbon(pts, r0, r1, col)


func _ribbon(pts: Array, r0: float, r1: float, col: Color) -> void:
	var base := _verts.size()
	var n := pts.size()
	for i in n:
		var t := float(i) / (n - 1)
		var d: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := d.cross(Vector3(0, 0, 1)).normalized()
		var r := lerpf(r0, r1, t)
		for s in [-1.0, 1.0]:
			_verts.append(pts[i] + side * r * s)
			_normals.append((Vector3(0, 0, 1) + side * s * 0.7).normalized())
			_tangents.append_array([side.x, side.y, side.z, 1.0])
			_uvs.append(Vector2(-1.0, -1.0))
			_colors.append(Color(col.r, col.g, col.b, 1.0))
	for i in n - 1:
		var a := base + i * 2
		_idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


func _clear() -> void:
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_tangents = PackedFloat32Array()
	_uvs = PackedVector2Array()
	_colors = PackedColorArray()
	_idx = PackedInt32Array()


func _commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TANGENT] = _tangents
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

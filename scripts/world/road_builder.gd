class_name RoadBuilder
extends Node3D
## Builds the road surface mesh (in chunks, with collision) and the roadside
## delineator posts from TerrainData.road_points.

const CHUNK_POINTS := 64
const POST_SPACING := 48.0

var material: ShaderMaterial


func build(data: TerrainData, sky: SkySystem) -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/road.gdshader")
	var base := "res://assets/textures/asphalt_02/asphalt_02_"
	material.set_shader_parameter("asphalt_albedo", load(base + "diffuse_4k.jpg"))
	material.set_shader_parameter("asphalt_normal", load(base + "nor_gl_4k.jpg"))
	material.set_shader_parameter("asphalt_arm", load(base + "arm_4k.jpg"))
	var gbase := "res://assets/textures/gravel_road/gravel_road_"
	material.set_shader_parameter("gravel_albedo", load(gbase + "diffuse_4k.jpg"))
	material.set_shader_parameter("gravel_normal", load(gbase + "nor_gl_4k.jpg"))
	material.set_shader_parameter("half_width", TerrainData.ROAD_HALF_WIDTH)
	sky.register_material(material)

	var pts := data.road_points
	var n := pts.size()
	var w := TerrainData.ROAD_HALF_WIDTH
	var sh := TerrainData.ROAD_SHOULDER
	# Lateral profile: (offset, height delta).
	var profile := [Vector2(-(w + sh + 0.8), -0.35), Vector2(-(w + sh), -0.04), Vector2(-w, 0.0), Vector2(0.0, 0.06),
			Vector2(w, 0.0), Vector2(w + sh, -0.04), Vector2(w + sh + 0.8, -0.35)]
	var start := 0
	while start < n:
		var count := mini(CHUNK_POINTS, n - start)
		_build_chunk(data, start, count + 1, profile)
		start += CHUNK_POINTS
	_build_posts(data)


func _frame(data: TerrainData, i: int) -> Array:
	var p := data.road_point(i)
	var t := data.road_tangent(i)
	var right := t.cross(Vector3.UP).normalized()
	return [p, t, right]


func _build_chunk(data: TerrainData, start: int, count: int, profile: Array) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var idx := PackedInt32Array()
	var cols := profile.size()
	var faces := PackedVector3Array()
	for k in count:
		var i := start + k
		var f := _frame(data, i)
		var p: Vector3 = f[0]
		var right: Vector3 = f[2]
		var along := float(i) * TerrainData.ROAD_STEP
		for c in cols:
			var pr: Vector2 = profile[c]
			verts.append(p + right * pr.x + Vector3.UP * pr.y)
			uvs.append(Vector2(pr.x, along))
			normals.append(Vector3.UP)
			tangents.append_array([right.x, right.y, right.z, 1.0])
	for k in count - 1:
		for c in cols - 1:
			var a := k * cols + c
			var b := a + 1
			var cc := a + cols
			var d := cc + 1
			idx.append_array([a, cc, b, b, cc, d])
			if c >= 1 and c < cols - 2:
				faces.append_array([verts[a], verts[cc], verts[b], verts[b], verts[cc], verts[d]])
	# Smooth normals from the triangles.
	for v in normals.size():
		normals[v] = Vector3.ZERO
	for t in range(0, idx.size(), 3):
		var nrm := (verts[idx[t + 2]] - verts[idx[t]]).cross(verts[idx[t + 1]] - verts[idx[t]])
		for j in 3:
			normals[idx[t + j]] += nrm
	for v in normals.size():
		normals[v] = normals[v].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.set_meta("surface", "asphalt")
	add_child(body)


func _build_posts(data: TerrainData) -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.0, 0.12)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/delineator.gdshader")
	post.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	var step := int(POST_SPACING / TerrainData.ROAD_STEP)
	var count := data.road_points.size() / step
	mm.instance_count = count * 2
	var off := TerrainData.ROAD_HALF_WIDTH + TerrainData.ROAD_SHOULDER + 0.35
	for k in count:
		var i := k * step
		var f := _frame(data, i)
		var p: Vector3 = f[0]
		var t: Vector3 = f[1]
		var right: Vector3 = f[2]
		for side in 2:
			var s := -1.0 if side == 0 else 1.0
			var pos := p + right * off * s
			pos.y = data.height_at(pos.x, pos.z) + 0.5
			var basis := Basis.looking_at(t * s, Vector3.UP)
			mm.set_instance_transform(k * 2 + side, Transform3D(basis, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

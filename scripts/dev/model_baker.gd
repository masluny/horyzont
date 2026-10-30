class_name ModelBaker
extends Node
## Dev tool: turns the heavy scanned models into game meshes.
## godot --path . -- --bake_models
## Saves assets/models/baked/<id>.res: an ArrayMesh of about TARGET triangles
## with the scan's material, using Godot's own mesh simplifier.

const OUT := "res://assets/models/baked/"
const MODELS := {
	"rock_moss_set_01": 2600, "rock_moss_set_02": 2600, "rock_07": 2600, "rock_09": 2600,
	"boulder_01": 3200, "stone_01": 1800, "rock_face_01": 3200, "rock_face_02": 3200,
	"namaqualand_boulder_02": 3200, "tree_stump_01": 2000, "dead_tree_trunk": 3000,
}


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for id in MODELS:
		_bake(id, MODELS[id])
		await get_tree().process_frame
	get_tree().quit()


func _bake(id: String, target: int) -> void:
	var scene: PackedScene = load("res://assets/models/%s/%s.gltf" % [id, id])
	var root := scene.instantiate()
	var parts: Array[MeshInstance3D] = []
	_find(root, parts)
	var out := ArrayMesh.new()
	var src_tris := 0
	var kept := 0
	for mi in parts:
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var xf := _to_root(mi, root)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = xf * verts[i]
				nrm[i] = (xf.basis * nrm[i]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = nrm
			var tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			src_tris += tris
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mi.mesh.surface_get_material(s))
			im.generate_lods(25.0, 60.0, [])
			var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for l in im.get_surface_lod_count(0):
				var idx := im.get_surface_lod_indices(0, l)
				if idx.size() / 3 >= target * 0.6:
					best = idx
			# Keep only the vertices the chosen index list still uses.
			var slim := _compact(arrays, best)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, slim)
			out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(s))
			kept += best.size() / 3
	root.free()
	ResourceSaver.save(out, OUT + id + ".res")
	print("baked %s: %d -> %d tris" % [id, src_tris, kept])


func _compact(arrays: Array, index: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var new_index := PackedInt32Array()
	new_index.resize(index.size())
	for i in index.size():
		var v := index[i]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		new_index[i] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var src_t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var t := PackedFloat32Array()
	for o in order:
		v.append(src_v[o])
		n.append(src_n[o])
		uv.append(src_uv[o])
		if not src_t.is_empty():
			t.append_array([src_t[o * 4], src_t[o * 4 + 1], src_t[o * 4 + 2], src_t[o * 4 + 3]])
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_TEX_UV] = uv
	if not t.is_empty():
		out[Mesh.ARRAY_TANGENT] = t
	out[Mesh.ARRAY_INDEX] = new_index
	return out


func _find(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find(c, out)


func _to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

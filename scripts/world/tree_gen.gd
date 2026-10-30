class_name TreeGen
extends RefCounted
## Procedural trees: a recursive branch skeleton skinned with bark, and leaf-spray
## cards along the twigs. Vertex data the shaders rely on:
##   COLOR  r = canopy occlusion, g = per-card hue, b = bark/leaf variation, a = wind flex
##   UV2    x = branch phase, y = flutter weight

const SPECIES := {
	"oak": {"atlas": "oak", "bark": "bark_brown_02", "h": [10.0, 14.0], "bole": 0.26, "n1": [8, 11], "len1": 0.6,
		"ang1": [0.8, 1.2], "n2": [4, 6], "len2": 0.55, "ang2": [0.6, 1.0], "n3": [4, 5], "len3": 0.62, "gnarl": 0.5,
		"up": 0.1, "radius": 0.03, "card": [1.3, 1.95], "spacing": 0.34, "shape": "dome"},
	"round": {"atlas": "round", "bark": "jolcham_oak_bark_01", "h": [13.0, 18.0], "bole": 0.22, "n1": [10, 13], "len1": 0.42,
		"ang1": [0.5, 0.85], "n2": [4, 6], "len2": 0.6, "ang2": [0.5, 0.9], "n3": [4, 5], "len3": 0.62, "gnarl": 0.35,
		"up": 0.2, "radius": 0.024, "card": [1.3, 1.95], "spacing": 0.34, "shape": "oval"},
	"olive": {"atlas": "olive", "bark": "bark_brown_02", "h": [6.0, 8.5], "bole": 0.2, "n1": [6, 8], "len1": 0.62,
		"ang1": [0.75, 1.15], "n2": [4, 6], "len2": 0.6, "ang2": [0.6, 1.0], "n3": [4, 5], "len3": 0.62, "gnarl": 0.85,
		"up": 0.08, "radius": 0.042, "card": [1.05, 1.55], "spacing": 0.3, "shape": "dome"},
	"bush": {"atlas": "round", "bark": "bark_brown_02", "h": [2.0, 3.4], "bole": 0.03, "n1": [6, 8], "len1": 0.85,
		"ang1": [0.35, 0.95], "n2": [4, 5], "len2": 0.6, "ang2": [0.5, 0.9], "n3": [0, 0], "len3": 0.0, "gnarl": 0.6,
		"up": 0.2, "radius": 0.022, "card": [0.8, 1.2], "spacing": 0.26, "shape": "dome"},
	"pine": {"atlas": "pine", "bark": "pine_bark", "h": [16.0, 23.0], "bole": 0.6, "n1": [12, 16], "len1": 0.33,
		"ang1": [1.05, 1.4], "n2": [4, 6], "len2": 0.6, "ang2": [0.5, 0.85], "n3": [0, 0], "len3": 0.0, "gnarl": 0.3,
		"up": 0.2, "radius": 0.021, "card": [1.45, 2.1], "spacing": 0.34, "shape": "umbrella"},
}
const BARK_TILE := 1.5

var _p: Dictionary
var _rng := RandomNumberGenerator.new()
var _height := 10.0
var _crown_center := Vector3.ZERO
var _crown_radius := Vector3.ONE
var _max_level := 3
var _phase := 0.0

var bark_a := MeshBuffer.new()
var bark_b := MeshBuffer.new()
var leaf_a := MeshBuffer.new()
var leaf_b := MeshBuffer.new()
var _cards: Array = []


## Returns {lod0: ArrayMesh, lod1: ArrayMesh, height, radius, trunk}. Surface 0 is
## bark, surface 1 is leaves.
static func make(species: String, seed_value: int) -> Dictionary:
	var g := TreeGen.new()
	return g._make(species, seed_value)


func _make(species: String, seed_value: int) -> Dictionary:
	_p = SPECIES[species]
	_rng.seed = seed_value
	_height = _rng.randf_range(_p["h"][0], _p["h"][1])
	_max_level = 3 if int(_p["n3"][1]) > 0 else 2
	var bole: float = _p["bole"]
	var crown_h := _height * (1.0 - bole)
	var width: float = crown_h * (0.72 if _p["shape"] == "oval" else 1.0)
	if _p["shape"] == "umbrella":
		width = _height * 0.3
	_crown_center = Vector3(0.0, _height * bole + crown_h * 0.52, 0.0)
	_crown_radius = Vector3(width, crown_h * 0.6, width)
	var trunk_r: float = _height * float(_p["radius"])
	var lean := Vector3(_rng.randf_range(-0.12, 0.12), 1.0, _rng.randf_range(-0.12, 0.12)).normalized()
	_grow(Vector3.ZERO, lean, _height, trunk_r, 0, 0.0, 0)
	_place_cards()
	var blobs := _shadow_blobs()
	var aabb_r := 0.0
	for c in _cards:
		aabb_r = maxf(aabb_r, Vector2(c["p"].x, c["p"].z).length())
	if Game.args.has("tree_stats"):
		print("tree %s: %d m, bark %d/%d v, leaves %d/%d v" % [species, int(_height), bark_a.verts.size(), bark_b.verts.size(), leaf_a.verts.size(), leaf_b.verts.size()])
	return {
		"lod0": _commit(bark_a, leaf_a),
		"lod1": _commit(bark_b, leaf_b),
		"blobs": blobs,
		"height": _height + 1.5,
		"radius": aabb_r + 2.0,
		"trunk": trunk_r,
	}


func _grow(start: Vector3, dir: Vector3, length: float, radius: float, level: int, flex0: float, group: int) -> void:
	var segs: int = [12, 7, 5, 3][level]
	var pts: Array[Vector3] = [start]
	var rad: Array[float] = [radius]
	var d := dir
	var step := length / segs
	var gnarl: float = _p["gnarl"]
	var up: float = _p["up"]
	var wander := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1))
	for i in segs:
		var t := float(i + 1) / segs
		d += wander * gnarl * (0.1 if level == 0 else 0.2) / segs * 4.0
		d += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * gnarl * 0.06
		if level > 0:
			d.y += (up - 0.06 * level) * 0.45
		d = d.normalized()
		pts.append(pts[i] + d * step)
		var k := 1.0 - t
		rad.append(lerpf(radius * 0.12, radius, k * k * 0.3 + k * 0.7))
	var phase := _rng.randf() * TAU
	var flex_end: float = flex0 + float([0.16, 0.34, 0.3, 0.2][level])
	_tube(pts, rad, level, flex0, flex_end, phase)
	if level >= _max_level - 1:
		_cards.append({"p": pts[segs], "d": d, "flex": flex_end, "phase": phase, "len": length, "pts": pts, "tip": level == _max_level, "group": group})
	if level == _max_level:
		return
	var key := "n%d" % (level + 1)
	var n := _rng.randi_range(_p[key][0], _p[key][1])
	var start_t: float = float(_p["bole"]) if level == 0 else 0.25
	var azimuth := _rng.randf() * TAU
	for i in n:
		var t := lerpf(start_t, 0.96, (i + _rng.randf_range(0.1, 0.9)) / n)
		var f := t * segs
		var idx := mini(int(f), segs - 1)
		var at := pts[idx].lerp(pts[idx + 1], f - idx)
		var r_at := lerpf(rad[idx], rad[idx + 1], f - idx)
		azimuth += 2.4 + _rng.randf_range(-0.3, 0.3)
		var a_key := "ang%d" % mini(level + 1, 2)
		var pitch := _rng.randf_range(_p[a_key][0], _p[a_key][1])
		var seg_dir := (pts[idx + 1] - pts[idx]).normalized()
		var side := seg_dir.cross(Vector3(cos(azimuth), 0.02, sin(azimuth))).normalized()
		var child_dir := seg_dir.rotated(side, pitch).normalized()
		var len_k: float = _p["len%d" % (level + 1)]
		var child_len := length * len_k * _crown_shape(t, level) * _rng.randf_range(0.8, 1.15)
		_grow(at, child_dir, child_len, r_at * (0.62 if level == 0 else 0.68), level + 1, lerpf(flex0, flex_end, t), i if level == 0 else group)


func _crown_shape(t: float, level: int) -> float:
	if level > 0:
		return 1.0 - t * 0.45
	var u := inverse_lerp(float(_p["bole"]), 1.0, t)
	match _p["shape"]:
		"umbrella":
			return lerpf(0.72, 1.0, sin(clampf(u * 1.5, 0.0, 1.0) * PI * 0.5)) * (1.0 - smoothstep(0.82, 1.0, u) * 0.55)
		"oval":
			return 0.42 + 0.72 * sin(clampf(u, 0.0, 1.0) * PI)
	return 0.55 + 0.6 * sin(clampf(u * 0.82 + 0.1, 0.0, 1.0) * PI)


func _tube(pts: Array[Vector3], rad: Array[float], level: int, flex0: float, flex1: float, phase: float) -> void:
	_tube_into(bark_a, pts, rad, [10, 6, 4, 3][level], 1, level, flex0, flex1, phase)
	if level <= 1:
		_tube_into(bark_b, pts, rad, [6, 4, 3, 3][level], 2, level, flex0, flex1, phase)


func _tube_into(buf: MeshBuffer, pts: Array[Vector3], rad: Array[float], sides: int, stride: int, level: int, flex0: float, flex1: float, phase: float) -> void:
	var n := pts.size()
	var ring_count := 0
	var base := buf.verts.size()
	var side := (pts[1] - pts[0]).cross(Vector3(0.31, 0.07, 0.94)).normalized()
	var dist := 0.0
	var i := 0
	while i < n:
		var d: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		side = (side - d * side.dot(d)).normalized()
		var fwd := d.cross(side)
		var r := rad[i]
		if i > 0:
			dist += pts[i].distance_to(pts[maxi(i - stride, 0)])
		var around := maxf(round(TAU * rad[0] / BARK_TILE), 1.0)
		var t := float(i) / (n - 1)
		var flex := lerpf(flex0, flex1, t)
		for s in sides + 1:
			var a := TAU * s / sides
			var c := cos(a)
			var sn := sin(a)
			var rr := r
			if level == 0:
				# Root flare with buttress lobes at the base of the trunk.
				var y := pts[i].y
				rr *= 1.0 + (0.55 + 0.45 * sin(a * 5.0 + 1.3)) * 0.85 * exp(-y / 0.55)
			var nrm := (side * c + fwd * sn).normalized()
			buf.verts.append(pts[i] + nrm * rr)
			buf.normals.append(nrm)
			buf.tangents.append_array([-sn * side.x + c * fwd.x, -sn * side.y + c * fwd.y, -sn * side.z + c * fwd.z, 1.0])
			buf.uvs.append(Vector2(float(s) / sides * around, dist / BARK_TILE))
			buf.uv2.append(Vector2(phase, 0.0))
			buf.colors.append(Color(1.0, 0.5, _rng.randf(), flex))
		ring_count += 1
		if i == n - 1:
			break
		i = mini(i + stride, n - 1)
	for r in ring_count - 1:
		for s in sides:
			var a := base + r * (sides + 1) + s
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			buf.idx.append_array([a, c, b, b, c, d])


func _place_cards() -> void:
	var spacing: float = _p["spacing"]
	var lo: float = _p["card"][0]
	var hi: float = _p["card"][1]
	for twig in _cards:
		var pts: Array = twig["pts"]
		var total: float = twig["len"]
		var count := maxi(int(total / spacing), 1)
		var reach := 0.85 if twig["tip"] else 0.5
		for i in count:
			var u := 1.0 - float(i) / count * reach
			var f := u * (pts.size() - 1)
			var idx := mini(int(f), pts.size() - 2)
			var at: Vector3 = pts[idx].lerp(pts[idx + 1], f - idx)
			var dir: Vector3 = (pts[idx + 1] - pts[idx]).normalized()
			var size := _rng.randf_range(lo, hi)
			_card(at, dir, size, twig["flex"], twig["phase"], 0)
	# Fewer, larger cards make the far tree.
	for twig in _cards:
		var pts: Array = twig["pts"]
		var dir: Vector3 = (pts[pts.size() - 1] - pts[0]).normalized()
		var size := _rng.randf_range(lo, hi) * 2.1
		_card(pts[pts.size() - 1], dir, size, twig["flex"], twig["phase"], 1)
		_card(pts[pts.size() / 2], dir, size * 0.8, twig["flex"], twig["phase"], 1)


func _card(at: Vector3, dir: Vector3, size: float, flex: float, phase: float, lod: int) -> void:
	var outward := (at - _crown_center) / _crown_radius
	var out_len := outward.length()
	var out_n := (at - _crown_center).normalized()
	# Sprays hang outwards and a little down, showing their face to the sky.
	var axis := (dir * 0.7 + out_n * 0.55 + Vector3.DOWN * 0.3 + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.4, 0.4))).normalized()
	var w_axis := axis.cross(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1))).normalized()
	var face := w_axis.cross(axis).normalized()
	if face.dot(out_n + Vector3.UP * 0.4) < 0.0:
		face = -face
		w_axis = -w_axis
	var cell := Vector2(_rng.randi_range(0, 1), _rng.randi_range(0, 1)) * 0.5
	var occl := clampf(smoothstep(0.1, 1.05, out_len), 0.0, 1.0)
	occl = lerpf(0.26, 1.0, occl) * clampf(0.68 + (at.y - _crown_center.y) / _crown_radius.y * 0.5, 0.4, 1.08)
	var hue := _rng.randf()
	var buf := leaf_a if lod == 0 else leaf_b
	var base := buf.verts.size()
	var rows := 3 if lod == 0 else 2
	var cols := 3 if lod == 0 else 2
	var half := size * 0.5
	var droop := _rng.randf_range(0.05, 0.22)
	for r in rows:
		var t := float(r) / (rows - 1)
		var center := at - axis * size * 0.22 + axis * size * t - face * droop * size * t * t
		for c in cols:
			var s := float(c) / (cols - 1)
			var lat := (s - 0.5) * 2.0
			var v := center + w_axis * half * lat + face * absf(lat) * half * 0.16
			var blob := ((v - _crown_center) / _crown_radius).normalized()
			buf.verts.append(v)
			buf.normals.append((blob * 0.82 + face * 0.3 + Vector3.UP * 0.2).normalized())
			buf.tangents.append_array([w_axis.x, w_axis.y, w_axis.z, 1.0])
			buf.uvs.append(cell + Vector2(s * 0.5, (1.0 - t) * 0.5))
			buf.uv2.append(Vector2(phase, t))
			buf.colors.append(Color(occl, hue, 0.5, clampf(flex + t * 0.15, 0.0, 1.0)))
	for r in rows - 1:
		for c in cols - 1:
			var a := base + r * cols + c
			buf.idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])


## Shadow caster for trees further away: one lumpy solid per main branch plus the
## trunk, cheap enough to draw into every shadow cascade.
func _shadow_blobs() -> ArrayMesh:
	var groups := {}
	for c in _cards:
		if not groups.has(c["group"]):
			groups[c["group"]] = []
		groups[c["group"]].append(c["p"])
	var buf := MeshBuffer.new()
	var t := (1.0 + sqrt(5.0)) * 0.5
	var ico: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for key in groups:
		var pts: Array = groups[key]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var center := (lo + hi) * 0.5
		var half := ((hi - lo) * 0.5 + Vector3.ONE * 0.7) * 0.62
		var base := buf.verts.size()
		for v in ico:
			buf.verts.append(center + v.normalized() * half)
			buf.normals.append(v.normalized())
			buf.tangents.append_array([1.0, 0.0, 0.0, 1.0])
			buf.uvs.append(Vector2.ZERO)
			buf.uv2.append(Vector2.ZERO)
			buf.colors.append(Color(1, 1, 1, 0.2))
		for f in faces:
			buf.idx.append(base + f)
	# Trunk as a tall thin box.
	var r := _height * float(_p["radius"]) * 1.1
	var base2 := buf.verts.size()
	for k in 8:
		var y := 0.0 if k < 4 else _height * 0.7
		var a := PI * 0.5 * (k % 4) + 0.78
		buf.verts.append(Vector3(cos(a) * r, y, sin(a) * r))
		buf.normals.append(Vector3(cos(a), 0, sin(a)))
		buf.tangents.append_array([1.0, 0.0, 0.0, 1.0])
		buf.uvs.append(Vector2.ZERO)
		buf.uv2.append(Vector2.ZERO)
		buf.colors.append(Color(1, 1, 1, 0.0))
	for k in 4:
		var a := base2 + k
		var b := base2 + (k + 1) % 4
		buf.idx.append_array([a, a + 4, b, b, a + 4, b + 4])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, buf.arrays())
	return m


func _commit(bark: MeshBuffer, leaf: MeshBuffer) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.arrays())
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf.arrays())
	return m


class MeshBuffer extends RefCounted:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_TANGENT] = tangents
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_INDEX] = idx
		return a

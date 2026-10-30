class_name CarModel
extends Node3D
## Procedural grand tourer. The body is lofted from hand-placed sections with a
## hard shoulder crease; the cabin is a second loft whose faces are sorted into
## glass, pillars and roof. Lamps, shut lines and trim are patches that follow
## the body surface, so everything sits on it exactly. Needs no assets.

const GROUND_Y := -0.265
const WHEEL_Z: Array[float] = [-1.32, 1.28]
const ARCH_RADIUS := 0.405
const ARCH_Y := 0.34
const ROW_STEP := 0.035
# Control points of the half section: 0 floor .. 6 shoulder crease .. 10 centreline.
const CREASE := 6.0
const SAMPLES: Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.33, 2.66, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0,
		6.0, 6.33, 6.66, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]

# z, half width, sill, shoulder, centre of the bonnet or deck (-z is the front)
const BODY := [
	[-2.26, 0.60, 0.30, 0.50, 0.53], [-2.20, 0.76, 0.24, 0.565, 0.60], [-2.06, 0.855, 0.205, 0.635, 0.665],
	[-1.75, 0.895, 0.19, 0.725, 0.735], [-1.32, 0.915, 0.19, 0.785, 0.785], [-0.90, 0.92, 0.19, 0.795, 0.825],
	[-0.50, 0.925, 0.19, 0.80, 0.865], [0.0, 0.93, 0.19, 0.805, 0.895], [0.70, 0.935, 0.19, 0.815, 0.91],
	[1.28, 0.94, 0.20, 0.835, 0.925], [1.72, 0.925, 0.215, 0.855, 0.945], [2.02, 0.905, 0.25, 0.87, 0.968],
	[2.18, 0.875, 0.30, 0.875, 0.965], [2.27, 0.80, 0.36, 0.86, 0.94],
]
# z, roof height, half width of the roof
const CABIN := [
	[-0.80, 0.84, 0.70], [-0.52, 0.985, 0.655], [-0.22, 1.14, 0.615], [0.06, 1.24, 0.59], [0.40, 1.285, 0.58],
	[0.75, 1.272, 0.585], [1.05, 1.21, 0.60], [1.35, 1.105, 0.63], [1.62, 1.015, 0.665], [1.88, 0.96, 0.70],
]
const CABIN_KEYS: Array[float] = [-0.46, 0.03, 0.52, 0.58, 1.12, 1.22]

var paint := StandardMaterial3D.new()
var glass := StandardMaterial3D.new()
var dark := StandardMaterial3D.new()
var trim := StandardMaterial3D.new()
var tyre := StandardMaterial3D.new()
var rim := StandardMaterial3D.new()
var chrome := StandardMaterial3D.new()
var brake := StandardMaterial3D.new()
var head_mat := StandardMaterial3D.new()
var lamp_glass := StandardMaterial3D.new()
var tail_mat := StandardMaterial3D.new()
var plate_mat := StandardMaterial3D.new()
var wheels: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var tail_light: OmniLight3D

var _mounts := []
var _table := []


func _ready() -> void:
	_setup_materials(Color(0.46, 0.026, 0.032))
	_build_table()
	var root := Node3D.new()
	root.position.y = GROUND_Y
	add_child(root)
	root.add_child(_mesh(_body_mesh(), paint))
	_add_cabin(root)
	_add_arch_liners(root)
	_add_shut_lines(root)
	_add_lamps(root)
	_add_trim(root)
	_mounts = Car.MOUNTS
	for i in 4:
		var w := _make_wheel(i % 2 == 0)
		add_child(w)
		wheels.append(w)
	_add_lights()


func set_paint(c: Color) -> void:
	paint.albedo_color = c


func update_wheels(compress: Array, spin: Array, steer: float, rest: float, _radius: float) -> void:
	for i in 4:
		var m: Vector3 = _mounts[i]
		var w := wheels[i]
		w.position = Vector3(m.x, m.y - rest + compress[i] if compress[i] > 0.0 else m.y - rest, m.z)
		var yaw := -steer if i < 2 else 0.0
		w.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -spin[i])


func set_brake_lights(on: bool) -> void:
	tail_mat.emission_energy_multiplier = 7.0 if on else (2.2 if headlights[0].visible else 0.35)
	tail_light.light_energy = 0.0


func set_headlights(on: bool) -> void:
	for l in headlights:
		l.visible = on
	head_mat.emission_energy_multiplier = 14.0 if on else 0.2


func _setup_materials(c: Color) -> void:
	paint.albedo_color = c
	paint.metallic = 0.45
	paint.roughness = 0.34
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.7
	paint.clearcoat_roughness = 0.08
	glass.albedo_color = Color(0.012, 0.015, 0.018)
	glass.roughness = 0.05
	glass.metallic_specular = 0.8
	dark.albedo_color = Color(0.008, 0.008, 0.009)
	dark.roughness = 0.9
	dark.metallic_specular = 0.2
	trim.albedo_color = Color(0.018, 0.018, 0.02)
	trim.roughness = 0.34
	tyre.albedo_color = Color(0.012, 0.012, 0.013)
	tyre.roughness = 0.92
	tyre.metallic_specular = 0.2
	rim.albedo_color = Color(0.36, 0.37, 0.39)
	rim.metallic = 1.0
	rim.roughness = 0.3
	chrome.albedo_color = Color(0.72, 0.72, 0.74)
	chrome.metallic = 1.0
	chrome.roughness = 0.16
	brake.albedo_color = Color(0.2, 0.2, 0.21)
	brake.metallic = 1.0
	brake.roughness = 0.7
	head_mat.albedo_color = Color(0.9, 0.92, 0.95)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.95, 0.85)
	head_mat.emission_energy_multiplier = 0.2
	head_mat.roughness = 0.1
	lamp_glass.albedo_color = Color(0.03, 0.035, 0.04)
	lamp_glass.roughness = 0.06
	lamp_glass.metallic = 0.6
	tail_mat.albedo_color = Color(0.2, 0.0, 0.0)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.03, 0.015)
	tail_mat.emission_energy_multiplier = 0.35
	tail_mat.roughness = 0.2
	plate_mat.albedo_color = Color(0.72, 0.72, 0.68)
	plate_mat.roughness = 0.5


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


# --- section functions -----------------------------------------------------------

func _build_table() -> void:
	var rows := 240
	for r in rows + 1:
		_table.append(_catmull_row(BODY, float(r) / rows))


static func _catmull_row(rows: Array, t: float) -> Array:
	var n := rows.size()
	var f := t * (n - 1)
	var i := clampi(int(f), 0, n - 2)
	var u := f - i
	var out := []
	for k in rows[0].size():
		var p0: float = rows[maxi(i - 1, 0)][k]
		var p1: float = rows[i][k]
		var p2: float = rows[i + 1][k]
		var p3: float = rows[mini(i + 2, n - 1)][k]
		var u2 := u * u
		out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u2 * u))
	return out


func _sec(z: float) -> Array:
	var lo := 0
	var hi: int = _table.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(_table[mid][0]) <= z:
			lo = mid
		else:
			hi = mid
	var a: Array = _table[lo]
	var b: Array = _table[hi]
	var u := clampf((z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-5), 0.0, 1.0)
	var out := []
	for k in a.size():
		out.append(lerpf(a[k], b[k], u))
	return out


func _arch_top(z: float) -> float:
	var top := 0.0
	for wz in WHEEL_Z:
		var d := z - wz
		if absf(d) < ARCH_RADIUS:
			top = maxf(top, ARCH_Y + sqrt(ARCH_RADIUS * ARCH_RADIUS - d * d))
	return top


func _controls(z: float) -> PackedVector2Array:
	var s := _sec(z)
	var w: float = s[1]
	var sill: float = s[2]
	var sh: float = s[3]
	var deck: float = s[4]
	var low := maxf(sill, minf(_arch_top(z), sh - 0.035))
	return PackedVector2Array([
		Vector2(0.0, sill + 0.03), Vector2(w * 0.72, sill), Vector2(w * 0.93, low), Vector2(w * 0.985, low + 0.012),
		Vector2(w * 0.995, lerpf(low, sh, 0.36)), Vector2(w * 1.0, lerpf(low, sh, 0.74)), Vector2(w * 0.992, sh),
		Vector2(w * 0.94, lerpf(sh, deck, 0.66)), Vector2(w * 0.80, deck - 0.02), Vector2(w * 0.42, deck - 0.002),
		Vector2(0.0, deck),
	])


## Point on the body. c is a control-point position, side is -1 or 1.
func _surf(z: float, c: float, side: float, ctrl := PackedVector2Array()) -> Vector3:
	var p := ctrl if not ctrl.is_empty() else _controls(z)
	var i := clampi(int(c), 0, 9)
	var u := c - i
	# Tangents stop at the crease so it stays sharp.
	var lo := 0 if c <= CREASE else int(CREASE)
	var hi := int(CREASE) if c <= CREASE else 10
	var p0 := p[maxi(i - 1, lo)]
	var p1 := p[i]
	var p2 := p[i + 1]
	var p3 := p[mini(i + 2, hi)]
	var v := 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u)
	return Vector3(v.x * side, v.y, z)


# --- body ------------------------------------------------------------------------

func _body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0: float = BODY[0][0]
	var z1: float = BODY[BODY.size() - 1][0]
	var rows := int((z1 - z0) / ROW_STEP)
	var grid := []
	for r in rows + 1:
		var z := lerpf(z0, z1, float(r) / rows)
		var ctrl := _controls(z)
		var pts := PackedVector3Array()
		for c in SAMPLES:
			pts.append(_surf(z, c, 1.0, ctrl))
		grid.append(pts)
	for side: float in [1.0, -1.0]:
		for r in rows:
			var inside := Vector3(0.0, 0.52, (grid[r][0].z + grid[r + 1][0].z) * 0.5)
			for k in SAMPLES.size() - 1:
				if SAMPLES[k] == SAMPLES[k + 1]:
					continue
				st.set_smooth_group(0 if SAMPLES[k] < CREASE else 1)
				var a: Vector3 = grid[r][k] * Vector3(side, 1, 1)
				var b: Vector3 = grid[r][k + 1] * Vector3(side, 1, 1)
				var c2: Vector3 = grid[r + 1][k] * Vector3(side, 1, 1)
				var d: Vector3 = grid[r + 1][k + 1] * Vector3(side, 1, 1)
				_tri(st, a, b, c2, inside)
				_tri(st, b, d, c2, inside)
		# The flat tail and the nose close the loft.
		for end: int in [0, rows]:
			st.set_smooth_group(2)
			var row: PackedVector3Array = grid[end]
			var centre := Vector3(0.0, 0.62 if end == rows else 0.42, row[0].z)
			var inside := centre + Vector3(0.0, 0.0, 0.5 if end == 0 else -0.5)
			for k in row.size() - 1:
				_tri(st, centre, row[k] * Vector3(side, 1, 1), row[k + 1] * Vector3(side, 1, 1), inside)
	st.generate_normals()
	st.index()
	return st.commit()


func _add_cabin(root: Node3D) -> void:
	var rows: Array[float] = []
	var steps := 44
	var z0: float = CABIN[0][0]
	var z1: float = CABIN[CABIN.size() - 1][0]
	for r in steps + 1:
		rows.append(lerpf(z0, z1, float(r) / steps))
	rows.append_array(CABIN_KEYS)
	rows.sort()
	var grid := []
	for z in rows:
		var row := _catmull_row(CABIN, inverse_lerp(z0, z1, z))
		var roof: float = row[1]
		var rw: float = row[2]
		var belt := _surf(z, 8.0, 1.0)
		belt.x -= 0.015
		belt.y -= 0.03
		var height := maxf(roof - belt.y, 0.0)
		var rail := Vector2(minf(rw, belt.x), belt.y + height * 0.9)
		var pts := PackedVector3Array()
		pts.append(belt)
		pts.append(Vector3(lerpf(belt.x, rail.x, 0.3) + 0.012, lerpf(belt.y, rail.y, 0.33), z))
		pts.append(Vector3(lerpf(belt.x, rail.x, 0.64) + 0.012, lerpf(belt.y, rail.y, 0.67), z))
		pts.append(Vector3(rail.x, rail.y, z))
		pts.append(Vector3(rail.x * 0.93, belt.y + height * 0.985, z))
		pts.append(Vector3(rail.x * 0.62, belt.y + height * 0.998, z))
		pts.append(Vector3(rail.x * 0.3, belt.y + height, z))
		pts.append(Vector3(0.0, belt.y + height * 1.002, z))
		grid.append(pts)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint_st := SurfaceTool.new()
	paint_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black_st := SurfaceTool.new()
	black_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:
		var flip := Vector3(side, 1, 1)
		for r in rows.size() - 1:
			var z := (rows[r] + rows[r + 1]) * 0.5
			if rows[r + 1] - rows[r] < 1e-4:
				continue
			var inside := Vector3(0.0, 0.55, z)
			for k in 7:
				var st := _cabin_surface(k, z, glass_st, paint_st, black_st)
				var a: Vector3 = grid[r][k] * flip
				var b: Vector3 = grid[r][k + 1] * flip
				var c: Vector3 = grid[r + 1][k] * flip
				var d: Vector3 = grid[r + 1][k + 1] * flip
				if st == glass_st:
					# Glass sits a little inside its frame.
					var drop := Vector3(-0.012 * side, -0.006, 0.0)
					a += drop
					b += drop
					c += drop
					d += drop
				_tri(st, a, b, c, inside)
				_tri(st, b, d, c, inside)
	for pair: Array in [[glass_st, glass], [paint_st, paint], [black_st, trim]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		st.index()
		root.add_child(_mesh(st.commit(), pair[1]))


func _cabin_surface(k: int, z: float, glass_st: SurfaceTool, paint_st: SurfaceTool, black_st: SurfaceTool) -> SurfaceTool:
	if k >= 4:
		return paint_st if z > 0.03 and z < 1.12 else glass_st
	if k == 3:
		return paint_st
	if z < -0.46:
		return paint_st
	if z < 0.52:
		return glass_st
	if z < 0.58:
		return black_st
	return glass_st if z < 1.22 else paint_st


## The body narrows towards the nose and up to the shoulder; the liner stays inside it.
static func _liner_edge(z: float, up: float) -> float:
	var half_width: float = BODY[0][1]
	for i in BODY.size() - 1:
		var a: Array = BODY[i]
		var b: Array = BODY[i + 1]
		if z >= a[0] and z <= b[0]:
			half_width = lerpf(a[1], b[1], (z - a[0]) / (b[0] - a[0]))
	return half_width - 0.03 - 0.05 * up * up


func _add_arch_liners(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	for wz in WHEEL_Z:
		for side: float in [-1.0, 1.0]:
			var inner := 0.56 * side
			var centre := Vector3(inner, ARCH_Y, wz)
			for s in segs:
				var a0 := PI * s / segs
				var a1 := PI * (s + 1) / segs
				var o0 := Vector3(0.0, sin(a0), cos(a0)) * ARCH_RADIUS
				var o1 := Vector3(0.0, sin(a1), cos(a1)) * ARCH_RADIUS
				var p00 := Vector3(inner, ARCH_Y, wz) + o0
				var p01 := Vector3(inner, ARCH_Y, wz) + o1
				var p10 := Vector3(_liner_edge(wz + o0.z, sin(a0)) * side, ARCH_Y, wz) + o0
				var p11 := Vector3(_liner_edge(wz + o1.z, sin(a1)) * side, ARCH_Y, wz) + o1
				var axis := Vector3(inner, ARCH_Y + 3.0, wz)
				_tri(st, p00, p10, p01, axis)
				_tri(st, p10, p11, p01, axis)
				_tri(st, centre, p01, p00, centre + Vector3(-side, 0.0, 0.0) * 1.0 + Vector3(side * 2.0, 0.0, 0.0))
	st.generate_normals()
	var mi := _mesh(st.commit(), dark)
	mi.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(mi)
	# Underfloor, so nothing shows through the car at a low angle.
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(1.1, 0.34, 3.9)
	var fi := _mesh(floor_box, dark)
	fi.position = Vector3(0.0, 0.36, 0.0)
	root.add_child(fi)


# --- things that follow the body surface -------------------------------------------

## A strip laid on the body between two control positions along z.
func _patch(st: SurfaceTool, z0: float, z1: float, c0: float, c1: float, side: float, lift: float, rows := 8, cols := 3) -> void:
	var grid := []
	for r in rows + 1:
		var z := lerpf(z0, z1, float(r) / rows)
		var ctrl := _controls(z)
		var row := PackedVector3Array()
		for k in cols + 1:
			var c := lerpf(c0, c1, float(k) / cols)
			var p := _surf(z, c, side, ctrl)
			row.append(p + (p - Vector3(0.0, 0.55, z)).normalized() * lift)
		grid.append(row)
	for r in rows:
		var inside := Vector3(0.0, 0.55, (grid[r][0].z + grid[r + 1][0].z) * 0.5)
		for k in cols:
			_tri(st, grid[r][k], grid[r][k + 1], grid[r + 1][k], inside)
			_tri(st, grid[r][k + 1], grid[r + 1][k + 1], grid[r + 1][k], inside)


## A thin dark line along a list of surface points.
func _line(st: SurfaceTool, pts: PackedVector3Array, width: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var out_a := (a - Vector3(0.0, 0.55, a.z)).normalized()
		var out_b := (b - Vector3(0.0, 0.55, b.z)).normalized()
		var across := (b - a).cross(out_a).normalized() * width
		var inside := (a + b) * 0.5 - out_a
		var lift := 0.0025
		_tri(st, a + out_a * lift - across, a + out_a * lift + across, b + out_b * lift - across, inside)
		_tri(st, a + out_a * lift + across, b + out_b * lift + across, b + out_b * lift - across, inside)


func _add_shut_lines(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		# Door.
		var front := PackedVector3Array()
		var rear := PackedVector3Array()
		for k in 15:
			var c := lerpf(2.6, 8.0, k / 14.0)
			front.append(_surf(-0.62, c, side))
			rear.append(_surf(0.92, c, side))
		_line(st, front, 0.003)
		_line(st, rear, 0.003)
		var bottom := PackedVector3Array()
		for k in 21:
			bottom.append(_surf(lerpf(-0.62, 0.92, k / 20.0), 2.6, side))
		_line(st, bottom, 0.003)
		# Bonnet and boot edges.
		var bonnet := PackedVector3Array()
		for k in 25:
			bonnet.append(_surf(lerpf(-0.74, -2.04, k / 24.0), 8.0, side))
		_line(st, bonnet, 0.003)
		var boot := PackedVector3Array()
		for k in 11:
			boot.append(_surf(lerpf(1.72, 2.2, k / 10.0), 8.0, side))
		_line(st, boot, 0.003)
		for z: float in [-0.74, -2.04, 1.72]:
			var across := PackedVector3Array()
			for k in 11:
				across.append(_surf(z, lerpf(8.0, 10.0, k / 10.0), side))
			_line(st, across, 0.003)
		# Fuel flap on the right rear wing.
		if side > 0.0:
			var flap := PackedVector3Array()
			for a in 13:
				var t := TAU * a / 12.0
				flap.append(_surf(1.42 + cos(t) * 0.07, 6.5 + sin(t) * 0.55, side))
			_line(st, flap, 0.002)
	st.generate_normals()
	root.add_child(_mesh(st.commit(), dark))


func _add_lamps(root: Node3D) -> void:
	var lens := SurfaceTool.new()
	lens.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drl := SurfaceTool.new()
	drl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tail := SurfaceTool.new()
	tail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var housing := SurfaceTool.new()
	housing.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		# Headlight: a dark lens along the top of the wing with a light blade inside.
		_patch(lens, -2.17, -1.7, 6.15, 7.5, side, 0.002, 12, 4)
		_patch(drl, -2.13, -1.76, 6.5, 6.72, side, 0.004, 10, 1)
		# Tail lamp wraps round the rear corner.
		_patch(housing, 2.02, 2.25, 5.75, 6.75, side, 0.002, 6, 3)
		_patch(tail, 2.05, 2.24, 6.0, 6.32, side, 0.004, 5, 1)
	var bar_y := 0.806
	_box(tail, Vector3(0.0, bar_y, 2.274), Vector3(1.5, 0.016, 0.006))
	_box(housing, Vector3(0.0, bar_y, 2.271), Vector3(1.58, 0.082, 0.008))
	for i in 16:
		var x := -0.72 + i * 0.096
		_box(tail, Vector3(x, bar_y - 0.022, 2.274), Vector3(0.07, 0.012, 0.006))
	lens.generate_normals()
	root.add_child(_mesh(lens.commit(), lamp_glass))
	drl.generate_normals()
	root.add_child(_mesh(drl.commit(), head_mat))
	housing.generate_normals()
	root.add_child(_mesh(housing.commit(), dark))
	tail.generate_normals()
	root.add_child(_mesh(tail.commit(), tail_mat))


func _add_trim(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rear: diffuser with fins, plate recess, bumper line.
	_box(st, Vector3(0.0, 0.43, 2.262), Vector3(1.5, 0.15, 0.02))
	_box(st, Vector3(0.0, 0.615, 2.268), Vector3(0.56, 0.135, 0.012))
	for i in 7:
		_box(st, Vector3(-0.42 + i * 0.14, 0.42, 2.285), Vector3(0.01, 0.12, 0.05))
	_box(st, Vector3(0.0, 0.525, 2.27), Vector3(1.52, 0.006, 0.01))
	# Nose: grille, lower intake, splitter.
	_box(st, Vector3(0.0, 0.415, -2.235), Vector3(0.98, 0.125, 0.06))
	_box(st, Vector3(0.0, 0.29, -2.215), Vector3(1.34, 0.065, 0.06))
	_box(st, Vector3(0.0, 0.205, -2.17), Vector3(1.52, 0.02, 0.16))
	# Side vents behind the front wheels.
	for side: float in [-1.0, 1.0]:
		_patch(st, -0.86, -0.7, 4.2, 5.2, side, 0.003, 3, 2)
		_patch(st, -0.86, 0.86, 1.25, 2.1, side, 0.004, 26, 2)
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		_box(bars, Vector3(0.0, 0.372 + i * 0.022, -2.268), Vector3(0.96, 0.006, 0.01))
	st.generate_normals()
	root.add_child(_mesh(st.commit(), dark))
	bars.generate_normals()
	root.add_child(_mesh(bars.commit(), trim))

	var plate := BoxMesh.new()
	plate.size = Vector3(0.5, 0.11, 0.008)
	var pi_ := _mesh(plate, plate_mat)
	pi_.position = Vector3(0.0, 0.615, 2.277)
	root.add_child(pi_)
	for side: float in [-1.0, 1.0]:
		# Exhausts.
		var tube := CylinderMesh.new()
		tube.top_radius = 0.052
		tube.bottom_radius = 0.052
		tube.height = 0.1
		tube.radial_segments = 20
		tube.cap_top = false
		tube.cap_bottom = false
		var ti := _mesh(tube, chrome)
		ti.rotation.x = PI * 0.5
		ti.position = Vector3(0.56 * side, 0.4, 2.27)
		root.add_child(ti)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.046
		cap.bottom_radius = 0.046
		cap.height = 0.01
		cap.radial_segments = 16
		var ci := _mesh(cap, dark)
		ci.rotation.x = PI * 0.5
		ci.position = Vector3(0.56 * side, 0.4, 2.265)
		root.add_child(ci)
		# Door mirror: painted shell, glass closing its back, on a stalk from the door.
		var shell := SphereMesh.new()
		shell.radius = 0.1
		shell.height = 0.1
		shell.is_hemisphere = true
		shell.radial_segments = 20
		shell.rings = 8
		var si := _mesh(shell, paint)
		si.rotation.x = -PI * 0.5
		si.scale = Vector3(1.08, 0.75, 0.6)
		si.position = Vector3(0.985 * side, 0.93, -0.38)
		root.add_child(si)
		var mirror := CylinderMesh.new()
		mirror.top_radius = 0.1
		mirror.bottom_radius = 0.1
		mirror.height = 0.006
		mirror.radial_segments = 20
		var mi := _mesh(mirror, chrome)
		mi.rotation.x = PI * 0.5
		mi.scale = Vector3(1.04, 1.0, 0.57)
		mi.position = Vector3(0.985 * side, 0.93, -0.378)
		root.add_child(mi)
		var stalk := BoxMesh.new()
		stalk.size = Vector3(0.22, 0.024, 0.05)
		var sti := _mesh(stalk, trim)
		sti.position = Vector3(0.86 * side, 0.8625, -0.39)
		sti.rotation.z = 0.607 * side
		root.add_child(sti)
		# Door handle.
		var handle := BoxMesh.new()
		handle.size = Vector3(0.012, 0.018, 0.15)
		var hi := _mesh(handle, trim)
		hi.position = Vector3(0.937 * side, 0.815, 0.68)
		root.add_child(hi)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var v: Array[Vector3] = []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(st, v[f[0]], v[f[1]], v[f[2]], c)
		_tri(st, v[f[0]], v[f[2]], v[f[3]], c)


## Adds a triangle wound so that its front face points away from `inside`
## (Godot treats clockwise triangles as front-facing).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


# --- wheels ------------------------------------------------------------------------

## Spins a profile of (radius, x) points round the X axis.
## Turns a profile of (radius, x) points around the x axis. The outside of the solid
## is on the left when walking the profile with side 1, as in a tyre section from one
## bead over the tread to the other. A mirrored profile passes side -1.
static func _lathe(profile: Array[Vector2], segs: int, side := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var mid := (a0 + a1) * 0.5
		for i in profile.size() - 1:
			var p := profile[i]
			var q := profile[i + 1]
			var v00 := Vector3(p.y, cos(a0) * p.x, sin(a0) * p.x)
			var v01 := Vector3(p.y, cos(a1) * p.x, sin(a1) * p.x)
			var v10 := Vector3(q.y, cos(a0) * q.x, sin(a0) * q.x)
			var v11 := Vector3(q.y, cos(a1) * q.x, sin(a1) * q.x)
			var d := q - p
			var out := Vector3(-d.x, cos(mid) * d.y, sin(mid) * d.y) * side
			var inside := (v00 + v11) * 0.5 - out
			_tri(st, v00, v10, v01, inside)
			_tri(st, v10, v11, v01, inside)
	st.generate_normals()
	st.index()
	return st.commit()


func _make_wheel(left: bool) -> Node3D:
	var w := Node3D.new()
	var f := -1.0 if left else 1.0
	# Half a tyre section from the bead to the middle of the tread, with two grooves.
	var half: Array[Vector2] = [Vector2(0.243, 0.113), Vector2(0.256, 0.119), Vector2(0.278, 0.125), Vector2(0.302, 0.125),
		Vector2(0.325, 0.118), Vector2(0.336, 0.107), Vector2(0.34, 0.094), Vector2(0.34, 0.086), Vector2(0.33, 0.084),
		Vector2(0.33, 0.074), Vector2(0.34, 0.072), Vector2(0.34, 0.036), Vector2(0.33, 0.034), Vector2(0.33, 0.024),
		Vector2(0.34, 0.022), Vector2(0.34, 0.0)]
	var tyre_profile: Array[Vector2] = []
	for p in half:
		tyre_profile.append(Vector2(p.x, -p.y))
	for i in range(half.size() - 2, -1, -1):
		tyre_profile.append(half[i])
	w.add_child(_mesh(_lathe(tyre_profile, 64), tyre))
	var lip: Array[Vector2] = [Vector2(0.246, 0.112 * f), Vector2(0.24, 0.122 * f), Vector2(0.229, 0.119 * f), Vector2(0.223, 0.098 * f), Vector2(0.218, 0.06 * f)]
	w.add_child(_mesh(_lathe(lip, 48, f), rim))
	# The barrel closes behind the spokes, so nothing shows through the wheel.
	var barrel: Array[Vector2] = [Vector2(0.218, 0.06 * f), Vector2(0.218, 0.03 * f), Vector2(0.05, 0.03 * f)]
	w.add_child(_mesh(_lathe(barrel, 32, f), dark))
	var disc := CylinderMesh.new()
	disc.top_radius = 0.175
	disc.bottom_radius = 0.175
	disc.height = 0.012
	disc.radial_segments = 32
	var di := _mesh(disc, brake)
	di.rotation.z = PI * 0.5
	di.position.x = 0.048 * f
	w.add_child(di)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.055
	hub.bottom_radius = 0.065
	hub.height = 0.06
	hub.radial_segments = 16
	var hi := _mesh(hub, rim)
	hi.rotation.z = -PI * 0.5 * f
	hi.position.x = 0.08 * f
	w.add_child(hi)
	var spokes := SurfaceTool.new()
	spokes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for k in n:
		var a := TAU * k / n
		var pair := -1.0 if k % 2 == 0 else 1.0
		var tip_a := a + pair * 0.07
		var root_p := Vector3(0.09 * f, cos(a) * 0.05, sin(a) * 0.05)
		var tip_p := Vector3(0.106 * f, cos(tip_a) * 0.224, sin(tip_a) * 0.224)
		var along := (tip_p - root_p).normalized()
		var across := Vector3(0.0, -sin(a), cos(a))
		var depth := Vector3(1.0, 0.0, 0.0) * 0.016
		var wr := across * 0.026
		var wt := across * 0.017
		var pts := [root_p - wr, root_p + wr, tip_p + wt, tip_p - wt]
		var centre := (root_p + tip_p) * 0.5 + Vector3(-0.02 * f, 0.0, 0.0)
		for s: float in [1.0, -1.0]:
			var off: Vector3 = depth * s
			_tri(spokes, pts[0] + off, pts[1] + off, pts[2] + off, centre + Vector3(-s, 0, 0) * 0.3)
			_tri(spokes, pts[0] + off, pts[2] + off, pts[3] + off, centre + Vector3(-s, 0, 0) * 0.3)
		for e in 4:
			var a2: Vector3 = pts[e]
			var b2: Vector3 = pts[(e + 1) % 4]
			var mid := (a2 + b2) * 0.5
			_tri(spokes, a2 + depth, a2 - depth, b2 + depth, mid - (mid - (root_p + along * 0.09)).normalized() * 0.4)
			_tri(spokes, a2 - depth, b2 - depth, b2 + depth, mid - (mid - (root_p + along * 0.09)).normalized() * 0.4)
	spokes.generate_normals()
	w.add_child(_mesh(spokes.commit(), rim))
	return w


func _add_lights() -> void:
	for s: float in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(0.62 * s, 0.62 + GROUND_Y, -2.25)
		l.rotation.x = deg_to_rad(-4.0)
		l.spot_range = 90.0
		l.spot_angle = 28.0
		l.spot_angle_attenuation = 1.6
		l.light_energy = 9.0
		l.light_color = Color(1.0, 0.94, 0.84)
		l.shadow_enabled = s > 0.0
		l.visible = false
		add_child(l)
		headlights.append(l)
	tail_light = OmniLight3D.new()
	tail_light.position = Vector3(0, 0.7 + GROUND_Y, 2.3)
	tail_light.omni_range = 2.5
	tail_light.light_color = Color(1.0, 0.05, 0.02)
	tail_light.light_energy = 0.0
	add_child(tail_light)

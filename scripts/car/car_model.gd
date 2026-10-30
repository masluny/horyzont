class_name CarModel
extends Node3D
## Procedural grand-tourer body: lofted superellipse sections for the body and
## the glasshouse, plus wheels and lights. Built in code so it needs no assets.

const GROUND_Y := -0.265
const RING := 40

# z, half width, bottom, top (ground at y = 0, -z is the front)
const BODY := [
	[-2.24, 0.60, 0.31, 0.50], [-2.12, 0.82, 0.25, 0.61], [-1.86, 0.89, 0.22, 0.69],
	[-1.40, 0.915, 0.21, 0.755], [-0.72, 0.925, 0.205, 0.83], [0.0, 0.93, 0.205, 0.875],
	[0.80, 0.935, 0.205, 0.9], [1.40, 0.925, 0.215, 0.92], [1.90, 0.885, 0.24, 0.92],
	[2.13, 0.80, 0.30, 0.87], [2.24, 0.62, 0.37, 0.78],
]
# z, bottom half width, top half width, bottom, top
const GLASS := [
	[-0.82, 0.79, 0.62, 0.80, 0.83], [-0.46, 0.79, 0.62, 0.81, 1.05], [-0.10, 0.78, 0.62, 0.82, 1.25],
	[0.55, 0.78, 0.63, 0.84, 1.28], [1.0, 0.79, 0.62, 0.86, 1.21], [1.44, 0.81, 0.6, 0.88, 1.0],
	[1.66, 0.82, 0.58, 0.9, 0.915],
]

var paint := StandardMaterial3D.new()
var glass := StandardMaterial3D.new()
var dark := StandardMaterial3D.new()
var tyre := StandardMaterial3D.new()
var rim := StandardMaterial3D.new()
var head_mat := StandardMaterial3D.new()
var tail_mat := StandardMaterial3D.new()
var wheels: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var tail_light: OmniLight3D

var _mounts := []


func _ready() -> void:
	_setup_materials(Color(0.36, 0.025, 0.03))
	var root := Node3D.new()
	root.position.y = GROUND_Y
	add_child(root)
	root.add_child(_mesh(_loft_body(), paint))
	var gh := _loft_glass()
	var gi := MeshInstance3D.new()
	gi.mesh = gh
	gi.set_surface_override_material(0, glass)
	gi.set_surface_override_material(1, paint)
	root.add_child(gi)
	_add_details(root)
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
	tail_mat.emission_energy_multiplier = 6.0 if on else (1.8 if headlights[0].visible else 0.3)
	tail_light.light_energy = 0.0


func set_headlights(on: bool) -> void:
	for l in headlights:
		l.visible = on
	head_mat.emission_energy_multiplier = 12.0 if on else 0.15


func _setup_materials(c: Color) -> void:
	paint.albedo_color = c
	paint.metallic = 0.55
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.05
	glass.albedo_color = Color(0.015, 0.018, 0.022)
	glass.metallic = 0.0
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	dark.albedo_color = Color(0.02, 0.02, 0.022)
	dark.roughness = 0.55
	tyre.albedo_color = Color(0.025, 0.025, 0.025)
	tyre.roughness = 0.85
	rim.albedo_color = Color(0.6, 0.6, 0.62)
	rim.metallic = 1.0
	rim.roughness = 0.22
	head_mat.albedo_color = Color(0.9, 0.92, 0.95)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.95, 0.85)
	head_mat.emission_energy_multiplier = 0.6
	head_mat.roughness = 0.1
	tail_mat.albedo_color = Color(0.25, 0.0, 0.0)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.04, 0.02)
	tail_mat.emission_energy_multiplier = 0.4


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


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


func _superellipse(a: float, n: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	return Vector2(signf(c) * pow(absf(c), 2.0 / n), signf(s) * pow(absf(s), 2.0 / n))


func _loft_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 56
	var grid := []
	for r in rings + 1:
		var row := _catmull_row(BODY, float(r) / rings)
		var z: float = row[0]
		var w: float = row[1]
		var yb: float = row[2]
		var yt: float = row[3]
		var yc := (yb + yt) * 0.5
		var hh := (yt - yb) * 0.5
		var pts := []
		for k in RING:
			var a := TAU * k / RING
			var se := _superellipse(a, 3.2)
			var x := se.x * w
			var y := yc + se.y * hh
			# Slight tumblehome above the beltline and a crease along the shoulder.
			if se.y > 0.0:
				x *= lerpf(1.0, 0.9, se.y * se.y)
			# Wheel arches: lift the lower flanks around each axle.
			if absf(x) > 0.5:
				for wz in [-1.32, 1.28]:
					var u: float = (z - wz) / 0.5
					if absf(u) < 1.0:
						var arch := 0.06 + 0.68 * sqrt(1.0 - u * u)
						var side_k := smoothstep(0.5, 0.72, absf(x))
						y = maxf(y, lerpf(y, arch, side_k))
			pts.append(Vector3(x, y, z))
		grid.append(pts)
	_emit_grid(st, grid, true)
	st.index()
	st.generate_normals()
	return st.commit()


func _loft_glass() -> ArrayMesh:
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_st := SurfaceTool.new()
	roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 36
	var half := RING / 2
	var grid := []
	for r in rings + 1:
		var row := _catmull_row(GLASS, float(r) / rings)
		var z: float = row[0]
		var wb: float = row[1]
		var wt: float = row[2]
		var yb: float = row[3]
		var yt: float = row[4]
		var pts := []
		for k in half + 1:
			var a := PI * k / half
			var se := _superellipse(a, 3.6)
			var y := yb + se.y * (yt - yb)
			var x := se.x * lerpf(wb, wt, se.y)
			pts.append(Vector3(x, y, z))
		grid.append(pts)
	# Split faces: roof panel (steep up-facing) is paint, the rest glass.
	for r in grid.size() - 1:
		for k in half:
			var a: Vector3 = grid[r][k]
			var b: Vector3 = grid[r][k + 1]
			var c: Vector3 = grid[r + 1][k]
			var d: Vector3 = grid[r + 1][k + 1]
			var mid_z := (a.z + d.z) * 0.5
			var inside := Vector3(0.0, 0.7, mid_z)
			var n := (c - a).cross(b - a).normalized()
			if n.dot((a + b + c) / 3.0 - inside) < 0.0:
				n = -n
			var is_roof := n.y > 0.8 and mid_z > -0.05 and mid_z < 0.95
			var st := roof_st if is_roof else glass_st
			_tri(st, a, b, c, inside)
			_tri(st, b, d, c, inside)
	glass_st.index()
	glass_st.generate_normals()
	roof_st.index()
	roof_st.generate_normals()
	var mesh := glass_st.commit()
	roof_st.commit(mesh)
	return mesh


func _emit_grid(st: SurfaceTool, grid: Array, closed: bool) -> void:
	var rows := grid.size()
	var cols: int = grid[0].size()
	for r in rows - 1:
		for k in cols:
			var k2 := (k + 1) % cols if closed else k + 1
			if k2 >= cols:
				continue
			var a: Vector3 = grid[r][k]
			var b: Vector3 = grid[r][k2]
			var c: Vector3 = grid[r + 1][k]
			var d: Vector3 = grid[r + 1][k2]
			var inside := Vector3(0.0, 0.55, (a.z + d.z) * 0.5)
			_tri(st, a, b, c, inside)
			_tri(st, b, d, c, inside)
	# End caps.
	for cap in [0, rows - 1]:
		var centre := Vector3.ZERO
		for v in grid[cap]:
			centre += v
		centre /= cols
		var inside := centre + Vector3(0.0, 0.0, 0.5 if cap == 0 else -0.5)
		for k in cols:
			_tri(st, centre, grid[cap][k], grid[cap][(k + 1) % cols], inside)


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


func _add_details(root: Node3D) -> void:
	# Headlights: slim lenses following the nose; mirrors on the A-pillars.
	for side in [-1.0, 1.0]:
		var hl := CapsuleMesh.new()
		hl.radius = 0.045
		hl.height = 0.42
		hl.radial_segments = 12
		hl.rings = 4
		var hi := _mesh(hl, head_mat)
		hi.position = Vector3(0.6 * side, 0.585, -2.075)
		hi.rotation = Vector3(0.0, 0.42 * side, PI * 0.5 + 0.12 * side)
		root.add_child(hi)
	var tail := BoxMesh.new()
	tail.size = Vector3(1.4, 0.045, 0.04)
	var ti := _mesh(tail, tail_mat)
	ti.position = Vector3(0, 0.765, 2.205)
	root.add_child(ti)
	var grille := BoxMesh.new()
	grille.size = Vector3(0.9, 0.1, 0.05)
	var gi := _mesh(grille, dark)
	gi.position = Vector3(0, 0.37, -2.19)
	root.add_child(gi)
	for s in [-1.0, 1.0]:
		var skirt := BoxMesh.new()
		skirt.size = Vector3(0.05, 0.1, 2.1)
		var si := _mesh(skirt, dark)
		si.position = Vector3(0.9 * s, 0.25, 0.0)
		root.add_child(si)


func _make_wheel(left: bool) -> Node3D:
	var w := Node3D.new()
	var t := CylinderMesh.new()
	t.top_radius = 0.34
	t.bottom_radius = 0.34
	t.height = 0.235
	t.radial_segments = 40
	var ti := _mesh(t, tyre)
	ti.rotation.z = PI * 0.5
	w.add_child(ti)
	var r := CylinderMesh.new()
	r.top_radius = 0.235
	r.bottom_radius = 0.235
	r.height = 0.012
	r.radial_segments = 32
	var ri := _mesh(r, rim)
	ri.rotation.z = PI * 0.5
	ri.position.x = (-0.118 if left else 0.118)
	w.add_child(ri)
	# Spokes make the rotation visible.
	for k in 5:
		var sp := BoxMesh.new()
		sp.size = Vector3(0.02, 0.42, 0.045)
		var spi := _mesh(sp, rim)
		spi.position.x = (-0.12 if left else 0.12)
		spi.rotation.x = TAU * k / 5.0
		w.add_child(spi)
	return w


func _add_lights() -> void:
	for s in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(0.6 * s, 0.6 + GROUND_Y, -2.25)
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

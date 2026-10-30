class_name Props
extends Node3D
## Roadside and landscape props: dry-stone walls, a west-coast lighthouse,
## guard rails, boulders and a handful of farmhouses. All procedural.

const SEED := 481516234
const CHUNK := 280.0
const ROAD_CELL := 64.0
const STONE_BUDGET := 26000
const SHADOW_RANGE := 145.0

var _data: TerrainData
var _rng := RandomNumberGenerator.new()
var _road_cells: Dictionary = {}
var _occupied: Dictionary = {}
var _batches: Dictionary = {}
var _houses: Array[Vector3] = []
var _lighthouse := Vector3.ZERO
var _cliff := Vector2(-1.0, 0.0)
var _pending_cliff := Vector2(-1.0, 0.0)
var _stone_count := 0
var _wall_runs := 0
var _rail_posts := 0
var _boulder_count := 0
var _best_wall: Array[Vector3] = []
var _rail_sample := Vector3.ZERO
var _boulder_sample := Vector3.ZERO
var _boulder_sample_s := 0.0

var _stone_mat: ShaderMaterial
var _build_mat: ShaderMaterial
var _window_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _lens_mat: StandardMaterial3D
var _leaf_mat: ShaderMaterial
var _bark_mat: StandardMaterial3D
var _rail_mat: ShaderMaterial
var _beam_mat: ShaderMaterial
var _metal_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D

var _stone_meshes: Array[ArrayMesh] = []
var _rock_meshes: Array[ArrayMesh] = []
var _ico_cache: Array = []

var _glow := 0.0
var _glow_set := false
var _lamp: Node3D
var _beam: MeshInstance3D
var _spots: Array[SpotLight3D] = []
var _shadow_nodes: Array[GeometryInstance3D] = []
var _shadow_at: PackedVector3Array = PackedVector3Array()
var _shadow_on: PackedByteArray = PackedByteArray()


func build(data: TerrainData, _sky: SkySystem) -> void:
	_data = data
	_rng.seed = SEED
	var t0 := Time.get_ticks_msec()
	_make_materials()
	_stone_meshes = _make_stone_meshes()
	_rock_meshes = _make_rock_meshes()
	_index_road()
	_build_lighthouse()
	_build_houses()
	_build_walls()
	_build_boulders()
	_build_rails()
	_update_shadows()
	if Game.clock:
		_glow = _glow_for(Game.clock.sun_elevation_deg())
		_glow_set = true
		_apply_glow()
	print("props: built in %d ms, stones=%d runs=%d boulders=%d houses=%d rail_posts=%d" % [
		Time.get_ticks_msec() - t0, _stone_count, _wall_runs, _boulder_count, _houses.size(), _rail_posts])
	print("PROPS lighthouse %.1f %.1f %.1f" % [_lighthouse.x, _lighthouse.y, _lighthouse.z])
	_print_shots()


func _process(delta: float) -> void:
	if _lamp:
		_lamp.rotate_y(delta * TAU / 8.0)
	var elev := 0.0
	if Game.clock:
		elev = Game.clock.sun_elevation_deg()
	var target := _glow_for(elev)
	if not _glow_set:
		_glow = target
		_glow_set = true
	else:
		_glow = lerpf(_glow, target, 1.0 - exp(-delta * 5.0))
	_apply_glow()
	var night := elev < -2.0
	if _beam:
		_beam.visible = night
	for spot in _spots:
		spot.visible = night
	_update_shadows()


func _glow_for(elev: float) -> float:
	return smoothstep(1.5, -8.0, elev)


func _apply_glow() -> void:
	if _window_mat:
		_window_mat.emission_energy_multiplier = _glow * 0.04
	if _lens_mat:
		_lens_mat.emission_energy_multiplier = _glow * 1.4
	if _glass_mat:
		_glass_mat.emission_energy_multiplier = _glow * 0.012


# --- placement helpers -------------------------------------------------------

func _index_road() -> void:
	for i in _data.road_points.size():
		var p := _data.road_points[i]
		var key := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
		if not _road_cells.has(key):
			_road_cells[key] = []
		(_road_cells[key] as Array).append(i)


func _road_distance(x: float, z: float) -> float:
	var cx := floori(x / ROAD_CELL)
	var cz := floori(z / ROAD_CELL)
	var best := 1.0e12
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _road_cells.has(key):
				continue
			for idx in _road_cells[key]:
				var p: Vector3 = _data.road_points[int(idx)]
				var d := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
				if d < best:
					best = d
	return sqrt(best)


func _near_road(x: float, z: float, dist: float) -> bool:
	return _road_distance(x, z) < dist


func _near_house(x: float, z: float, dist: float) -> bool:
	var r2 := dist * dist
	for h in _houses:
		var dx := h.x - x
		var dz := h.z - z
		if dx * dx + dz * dz < r2:
			return true
	if _lighthouse != Vector3.ZERO:
		var dx2 := _lighthouse.x - x
		var dz2 := _lighthouse.z - z
		if dx2 * dx2 + dz2 * dz2 < (dist + 10.0) * (dist + 10.0):
			return true
	return false


func _occ_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / 6.0), floori(z / 6.0))


func _mark_wall(pts: Array[Vector3]) -> void:
	for p in pts:
		_occupied[_occ_key(p.x, p.z)] = true


func _wall_blocked(x: float, z: float) -> bool:
	return _occupied.has(_occ_key(x, z))


func _wall_ok(x: float, z: float) -> bool:
	if _near_road(x, z, 10.5):
		return false
	if _near_house(x, z, 9.0):
		return false
	var h := _data.height_at(x, z)
	if h < 6.0:
		return false
	return _data.normal_at(x, z).y > 0.9


func _frame(i: int) -> Array:
	var p := _data.road_point(i)
	var t := _data.road_tangent(i)
	t.y = 0.0
	if t.length_squared() < 1e-6:
		t = Vector3.FORWARD
	t = t.normalized()
	var right := Vector3.UP.cross(t).normalized()
	return [p, t, right]


# --- lighthouse --------------------------------------------------------------

func _cliff_site(rp: Vector3) -> Vector3:
	var best := Vector3(1.0e12, 0.0, 0.0)
	var best_score := -1.0
	var dirs: Array[Vector2] = [Vector2(-1.0, 0.0), Vector2(-0.80, -0.60), Vector2(-0.88, 0.47)]
	for d in dirs:
		var dir := d.normalized()
		for dist in range(60, 121, 6):
			var xz := Vector2(rp.x, rp.z) + dir * float(dist)
			var h := _data.height_at(xz.x, xz.y)
			if h < 15.0:
				continue
			var ny := _data.normal_at(xz.x, xz.y).y
			if ny < 0.78:
				continue
			var ahead := xz + dir * 34.0
			var drop := h - _data.height_at(ahead.x, ahead.y)
			if drop < 6.0:
				continue
			var score := drop + ny * 10.0 - absf(float(dist) - 85.0) * 0.02
			if score > best_score:
				best_score = score
				best = Vector3(xz.x, h, xz.y)
				_pending_cliff = dir
	return best


func _build_lighthouse() -> void:
	var n := _data.road_points.size()
	var west_i := 0
	var west_x := 1.0e12
	for i in n:
		if _data.road_points[i].x < west_x:
			west_x = _data.road_points[i].x
			west_i = i
	# The westernmost road point is a low shelf already at the water. Walk the
	# coast from there until a west / north-west step of 60-120 m is still a
	# cliff above 15 m.
	var best := Vector3(1.0e12, 0.0, 0.0)
	var best_along := 1.0e9
	for step in range(0, n / 2):
		for sign in [-1, 1]:
			if step == 0 and sign == 1:
				continue
			var i := posmod(west_i + sign * step, n)
			var site := _cliff_site(_data.road_point(i))
			if site.x > 1.0e11:
				continue
			var along := float(step)
			if along < best_along - 12.0 or (absf(along - best_along) <= 12.0 and site.x < best.x):
				best = site
				best_along = along
				_cliff = _pending_cliff
		if best.x < 1.0e11 and float(step) > best_along + 80.0:
			break
	if best.x > 1.0e11:
		best = _data.road_point(west_i) + Vector3(-40.0, 0.0, -20.0)
		best.y = _data.height_at(best.x, best.z)
		_cliff = Vector2(-1.0, -0.3).normalized()
	_lighthouse = best
	var root := Node3D.new()
	root.name = "Lighthouse"
	var inland := Vector3(-_cliff.x, 0.0, -_cliff.y).normalized()
	if inland.length_squared() < 0.5:
		inland = Vector3.RIGHT
	var side := inland.cross(Vector3.UP).normalized()
	root.basis = Basis(inland, Vector3.UP, side)
	root.position = _lighthouse
	add_child(root)

	var shaft := Acc.new()
	_add_shaft(shaft)
	_add_mesh_child(root, shaft.to_mesh(), _build_mat, "Shaft", true)
	_add_primitive(root, _cylinder(2.55, 2.55, 0.55, 20), _concrete_mat, Vector3(0, 0.22, 0), "Plinth")
	_add_primitive(root, _cylinder(1.95, 1.95, 0.14, 24), _white_mat, Vector3(0, 18.85, 0), "Gallery")
	var rail := TorusMesh.new()
	rail.inner_radius = 1.72
	rail.outer_radius = 1.84
	rail.rings = 28
	rail.ring_segments = 6
	_add_primitive(root, rail, _metal_mat, Vector3(0, 19.15, 0), "Rail")
	_add_primitive(root, _cylinder(1.22, 1.22, 2.7, 16), _metal_mat, Vector3(0, 20.35, 0), "Lantern")
	var dome := SphereMesh.new()
	dome.radius = 0.78
	dome.height = 1.15
	dome.radial_segments = 16
	dome.rings = 8
	_add_primitive(root, dome, _metal_mat, Vector3(0, 21.85, 0), "Dome")
	var finial := SphereMesh.new()
	finial.radius = 0.09
	finial.height = 0.22
	finial.radial_segments = 8
	finial.rings = 4
	_add_primitive(root, finial, _metal_mat, Vector3(0, 22.55, 0), "Finial")

	var glass := Acc.new()
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var c := cos(ang)
		var s := sin(ang)
		var b := Basis(Vector3(-s, 0, c), Vector3.UP, Vector3(-c, 0, -s))
		glass.add_box(Vector3(c * 1.28, 20.35, s * 1.28), Vector3(0.62, 1.85, 0.04), b, Color(1, 1, 1, 1))
	_add_mesh_child(root, glass.to_mesh(), _glass_mat, "Glass", false)

	var door := Acc.new()
	door.add_box(Vector3(1.42, 1.35, 0.0), Vector3(0.08, 2.15, 0.92), Basis.IDENTITY, Color(0.12, 0.08, 0.06, 0.55))
	_add_mesh_child(root, door.to_mesh(), _build_mat, "Door", true)

	_lamp = Node3D.new()
	_lamp.name = "Lamp"
	_lamp.position = Vector3(0, 20.35, 0)
	root.add_child(_lamp)
	for i in 2:
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 6.0
		spot.spot_range = 320.0
		spot.spot_angle = 7.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = false
		spot.visible = false
		spot.rotation.y = PI if i == 1 else 0.0
		_lamp.add_child(spot)
		_spots.append(spot)
	var beams := Acc.new()
	_add_beam(beams, -1.0)
	_add_beam(beams, 1.0)
	_beam = _add_mesh_child(_lamp, beams.to_mesh(), _beam_mat, "Beam", false)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	for i in 2:
		var ang := PI if i == 1 else 0.0
		var lens := SphereMesh.new()
		lens.radius = 0.16
		lens.height = 0.32
		lens.radial_segments = 10
		lens.rings = 6
		var lens_mi := _add_primitive(_lamp, lens, _lens_mat, Vector3(sin(ang) * 1.05, 0.0, cos(ang) * 1.05), "Lens%d" % i)
		lens_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Keeper's house, inland of the tower, plus one wind-bent tree.
	var keeper_at := _lighthouse + inland * 18.0
	var best_ny := -1.0
	for ox in range(-10, 11, 4):
		for oz in range(8, 28, 4):
			var x := _lighthouse.x + inland.x * float(oz) + side.x * float(ox)
			var z := _lighthouse.z + inland.z * float(oz) + side.z * float(ox)
			var hh := _data.height_at(x, z)
			var ny := _data.normal_at(x, z).y
			if hh > 10.0 and ny > best_ny:
				best_ny = ny
				keeper_at = Vector3(x, hh, z)
	if keeper_at.y < 1.0:
		keeper_at.y = _data.height_at(keeper_at.x, keeper_at.z)
	var houses_acc := Acc.new()
	var glass_acc := Acc.new()
	var facing := Basis.looking_at(-inland, Vector3.UP)
	_cottage(houses_acc, glass_acc, Transform3D(facing, keeper_at), 0.72)
	_spawn_buildings(houses_acc, glass_acc)
	_add_tree(keeper_at + side * 7.5 + inland * 2.0)
	_houses.append(keeper_at)


func _add_shaft(acc: Acc) -> void:
	var segs := 24
	var y := 0.35
	var y_top := 18.7
	var r_bottom := 2.05
	var r_top := 1.32
	var step := 0.42
	while y < y_top - 0.01:
		var y1 := minf(y + step, y_top)
		var r0 := lerpf(r_bottom, r_top, (y - 0.35) / (y_top - 0.35))
		var r1 := lerpf(r_bottom, r_top, (y1 - 0.35) / (y_top - 0.35))
		var col := _shaft_color((y + y1) * 0.5)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p00 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var mid_a := (a0 + a1) * 0.5
			acc.add_face(p00, p01, p11, p10, Vector3(cos(mid_a), 0.0, sin(mid_a)), col)
		y = y1


func _shaft_color(y: float) -> Color:
	var white := Color(0.90, 0.88, 0.84, 0.52)
	var red := Color(0.58, 0.07, 0.05, 0.46)
	if (y > 6.1 and y < 7.55) or (y > 12.5 and y < 13.95):
		return red
	white.r *= _rng.randf_range(0.96, 1.0)
	white.g *= _rng.randf_range(0.96, 1.0)
	return white


func _add_beam(acc: Acc, z_sign: float) -> void:
	# A flat wedge: wide across, only a little tall, so from the side it is a
	# streak of light rather than a solid bar. Two opposite beams.
	# Vertical sheet so a side-on camera sees one soft horizontal wedge.
	var length := 140.0
	var z0 := z_sign * 1.6
	var z1 := z_sign * length
	var a := Vector3(0.0, -0.22, z0)
	var b := Vector3(0.0, 0.22, z0)
	var c := Vector3(0.0, 2.6, z1)
	var d := Vector3(0.0, -1.15, z1)
	acc.add_face(a, b, c, d, Vector3.RIGHT, Color.WHITE, Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1))


# --- houses and trees --------------------------------------------------------

func _build_houses() -> void:
	var opaque := Acc.new()
	var glass := Acc.new()
	var n := _data.road_points.size()
	var placed := 0
	var tries := 0
	while placed < 10 and tries < 900:
		tries += 1
		var i := _rng.randi_range(0, n - 1)
		var f := _frame(i)
		var p: Vector3 = f[0]
		var t: Vector3 = f[1]
		var right: Vector3 = f[2]
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var dist := _rng.randf_range(48.0, 145.0)
		var along := _rng.randf_range(-24.0, 24.0)
		var xz := Vector2(p.x, p.z) + Vector2(t.x, t.z) * along + Vector2(right.x, right.z) * side * dist
		if not _house_site(xz):
			continue
		var pos := Vector3(xz.x, _data.height_at(xz.x, xz.y), xz.y)
		var idx := _data.nearest_road_index(pos)
		var to_road := _data.road_point(idx) - pos
		to_road.y = 0.0
		if to_road.length_squared() < 1.0:
			continue
		var face := to_road.normalized()
		face = face.rotated(Vector3.UP, _rng.randf_range(-0.25, 0.25))
		var xf := Transform3D(Basis.looking_at(face, Vector3.UP), pos)
		_cottage(opaque, glass, xf, _rng.randf_range(0.88, 1.06))
		_houses.append(pos)
		_add_tree(pos + right * side * -8.5 + t * _rng.randf_range(-3.0, 3.0))
		if _rng.randf() < 0.7:
			_add_tree(pos + t * _rng.randf_range(8.0, 12.0) + right * side * _rng.randf_range(-2.0, 4.0))
		placed += 1
	_spawn_buildings(opaque, glass)
	print("props: house attempts %d placed %d" % [tries, placed])


func _house_site(xz: Vector2) -> bool:
	var h := _data.height_at(xz.x, xz.y)
	if h < 6.0 or h > 180.0:
		return false
	if _data.normal_at(xz.x, xz.y).y < 0.97:
		return false
	var rd := _road_distance(xz.x, xz.y)
	if rd < 40.0 or rd > 155.0:
		return false
	for prev in _houses:
		if Vector2(prev.x - xz.x, prev.z - xz.y).length() < 400.0:
			return false
	if _lighthouse != Vector3.ZERO and Vector2(_lighthouse.x - xz.x, _lighthouse.z - xz.y).length() < 400.0:
		return false
	var corners := [Vector2(-4.2, -3.0), Vector2(4.2, -3.0), Vector2(4.2, 3.0), Vector2(-4.2, 3.0)]
	var hmin := h
	var hmax := h
	for c in corners:
		var hc := _data.height_at(xz.x + c.x, xz.y + c.y)
		hmin = minf(hmin, hc)
		hmax = maxf(hmax, hc)
	return hmax - hmin < 0.85


func _cottage(opaque: Acc, glass: Acc, xf: Transform3D, scale: float) -> void:
	var w := _rng.randf_range(7.6, 9.4) * scale
	var d := _rng.randf_range(5.1, 6.3) * scale
	var wall_h := _rng.randf_range(2.8, 3.2) * scale
	var roof_h := _rng.randf_range(1.65, 2.15) * scale
	var oh := 0.42 * scale
	var local_o := Acc.new()
	var local_g := Acc.new()
	var white := Color(0.88, 0.86, 0.81, 0.74)
	white.r *= _rng.randf_range(0.97, 1.02)
	var stone := Color(0.42, 0.39, 0.35, 0.9)
	var roof := Color(_rng.randf_range(0.07, 0.12), _rng.randf_range(0.075, 0.11), _rng.randf_range(0.08, 0.12), 0.66)
	var door_c := Color(0.14, 0.09, 0.06, 0.58)
	var found_h := 0.42 * scale
	local_o.add_box(Vector3(0, found_h * 0.5 - 0.08, 0), Vector3(w + 0.22, found_h + 0.16, d + 0.22), Basis.IDENTITY, stone)
	var wall_span := wall_h - found_h
	local_o.add_box(Vector3(0, found_h + wall_span * 0.5, 0), Vector3(w, wall_span, d), Basis.IDENTITY, white)
	# Gables (ridge runs along X).
	var peak := wall_h + roof_h - 0.06
	local_o.add_tri(Vector3(-w * 0.5, wall_h, -d * 0.5), Vector3(-w * 0.5, wall_h, d * 0.5), Vector3(-w * 0.5, peak, 0.0), white)
	local_o.add_tri(Vector3(w * 0.5, wall_h, d * 0.5), Vector3(w * 0.5, wall_h, -d * 0.5), Vector3(w * 0.5, peak, 0.0), white)
	_add_roof(local_o, w, d, wall_h, roof_h, oh, roof)
	# Chimney on the slope.
	var chim := Vector3(w * 0.22, wall_h + roof_h * 0.45, d * 0.12)
	local_o.add_box(chim + Vector3(0, 0.7, 0), Vector3(0.55, 1.5, 0.55) * scale, Basis.IDENTITY, Color(0.40, 0.24, 0.18, 0.88))
	local_o.add_box(chim + Vector3(0, 1.5, 0), Vector3(0.7, 0.16, 0.7) * scale, Basis.IDENTITY, Color(0.28, 0.27, 0.26, 0.7))
	# Door on the front (-Z), slightly left of centre.
	local_o.add_box(Vector3(-w * 0.18, 1.15 * scale, -d * 0.5 - 0.03), Vector3(1.05 * scale, 2.15 * scale, 0.06), Basis.IDENTITY, door_c)
	_window(local_o, local_g, Vector3(-w * 0.38, 1.55 * scale, -d * 0.5), Vector3(0, 0, -1), scale)
	_window(local_o, local_g, Vector3(w * 0.22, 1.55 * scale, -d * 0.5), Vector3(0, 0, -1), scale)
	_window(local_o, local_g, Vector3(w * 0.5, 1.55 * scale, 0.15 * d), Vector3(1, 0, 0), scale)
	_window(local_o, local_g, Vector3(-w * 0.5, 1.55 * scale, -0.1 * d), Vector3(-1, 0, 0), scale)
	_window(local_o, local_g, Vector3(0.4, 1.5 * scale, d * 0.5), Vector3(0, 0, 1), scale * 0.85)
	_merge(opaque, local_o, xf)
	_merge(glass, local_g, xf)


func _window(opaque: Acc, glass: Acc, center: Vector3, normal: Vector3, scale: float) -> void:
	var n := normal.normalized()
	var ww := 0.92 * scale
	var wh := 1.2 * scale
	var sill_c := Color(0.9, 0.88, 0.84, 0.5)
	opaque.add_box(center + n * 0.02, _face_size(n, ww + 0.12, wh + 0.12, 0.04), _face_basis(n), Color(0.08, 0.07, 0.06, 0.4))
	opaque.add_box(center + n * 0.045 + Vector3.DOWN * (wh * 0.5 + 0.04), _face_size(n, ww + 0.28, 0.08, 0.1), _face_basis(n), sill_c)
	glass.add_box(center + n * 0.05, _face_size(n, ww, wh, 0.02), _face_basis(n), Color(1, 1, 1, 1))


func _face_size(n: Vector3, width: float, height: float, depth: float) -> Vector3:
	if absf(n.x) > 0.5:
		return Vector3(depth, height, width)
	return Vector3(width, height, depth)


func _face_basis(n: Vector3) -> Basis:
	if absf(n.x) > 0.5:
		return Basis(Vector3(0, 0, n.x), Vector3.UP, Vector3(-n.x, 0, 0))
	return Basis.IDENTITY


func _add_roof(acc: Acc, w: float, d: float, wall_h: float, roof_h: float, oh: float, col: Color) -> void:
	var hw := w * 0.5 + oh
	var hd := d * 0.5 + oh * 0.85
	var y0 := wall_h - 0.02
	var y1 := wall_h + roof_h
	var fl := Vector3(-hw, y0, -hd)
	var fr := Vector3(hw, y0, -hd)
	var bl := Vector3(-hw, y0, hd)
	var br := Vector3(hw, y0, hd)
	var rl := Vector3(-hw, y1, 0.0)
	var rr := Vector3(hw, y1, 0.0)
	var thick := 0.12
	_slab(acc, fl, fr, rr, rl, thick, col)
	_slab(acc, br, bl, rl, rr, thick, col)
	# Barge boards close the gable overhang.
	acc.add_face(Vector3(-hw, y0, -hd), Vector3(-hw, y1, 0.0), Vector3(-hw + 0.08, y1, 0.0), Vector3(-hw + 0.08, y0, -hd), Vector3(-1, 0, 0), col)
	acc.add_face(Vector3(-hw, y1, 0.0), Vector3(-hw, y0, hd), Vector3(-hw + 0.08, y0, hd), Vector3(-hw + 0.08, y1, 0.0), Vector3(-1, 0, 0), col)


func _slab(acc: Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thick: float, col: Color) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	var a2 := a - n * thick
	var b2 := b - n * thick
	var c2 := c - n * thick
	var d2 := d - n * thick
	acc.add_face(a, b, c, d, n, col)
	acc.add_face(a2, d2, c2, b2, -n, col)
	acc.add_face(a, d, d2, a2, (d - a).cross(n), col)
	acc.add_face(b, a, a2, b2, (a - b).cross(n), col)
	acc.add_face(c, b, b2, c2, (b - c).cross(n), col)
	acc.add_face(d, c, c2, d2, (c - d).cross(n), col)


func _spawn_buildings(opaque: Acc, glass: Acc) -> void:
	if opaque.verts.is_empty():
		return
	var mi := _add_mesh_child(self, opaque.to_mesh(), _build_mat, "Houses", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not glass.verts.is_empty():
		var win := _add_mesh_child(self, glass.to_mesh(), _window_mat, "Windows", false)
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


var _bark: Acc
var _leaves: Acc


func _add_tree(hint: Vector3) -> void:
	if _bark == null:
		_bark = Acc.new()
		_leaves = Acc.new()
	# Own stream so canopy detail does not shift walls and houses.
	var local := RandomNumberGenerator.new()
	local.seed = int(hash(Vector2(hint.x, hint.z))) ^ SEED
	var x := hint.x + local.randf_range(-1.5, 1.5)
	var z := hint.z + local.randf_range(-1.5, 1.5)
	if _near_road(x, z, 12.0):
		return
	var h := _data.height_at(x, z)
	if h < 4.0:
		return
	var base := Vector3(x, h - 0.15, z)
	var height := local.randf_range(5.4, 8.2)
	var bend := local.randf_range(1.8, 3.2)
	var segs := 8
	var sides := 7
	var rings: Array[Vector3] = []
	var radii: Array[float] = []
	for s in segs + 1:
		var t := float(s) / float(segs)
		var center := base + Vector3(bend * t * t, t * height, bend * 0.18 * sin(t * 2.4) * t)
		rings.append(center)
		radii.append(lerpf(0.34, 0.05, t))
	var bark_c := Color(0.16, 0.11, 0.07, 1.0)
	for s in segs:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var p00 := rings[s] + d0 * radii[s]
			var p01 := rings[s] + d1 * radii[s]
			var p11 := rings[s + 1] + d1 * radii[s + 1]
			var p10 := rings[s + 1] + d0 * radii[s + 1]
			_bark.add_face(p00, p01, p11, p10, d0 + d1, bark_c)
	var top := rings[segs]
	var src: Array = _ico(2)
	var unit_v: PackedVector3Array = src[0]
	var unit_f: PackedInt32Array = src[1]
	var clumps := local.randi_range(8, 11)
	for c in clumps:
		var ang := local.randf() * TAU
		var rad := local.randf_range(0.1, 1.7)
		var center := top + Vector3(cos(ang) * rad + bend * 0.45, local.randf_range(-1.3, 0.45), sin(ang) * rad * 0.55)
		var radius := local.randf_range(0.7, 1.35)
		var g := local.randf_range(0.13, 0.24)
		var leaf := Color(g * 0.34, g, g * 0.22, 1.0)
		var verts := unit_v.duplicate()
		for i in verts.size():
			var p := verts[i]
			var n := _value_noise(p * 2.4 + Vector3(float(c) * 1.7, x * 0.01, z * 0.01))
			var q := p * Vector3(1.0, 0.62, 0.85)
			verts[i] = center + q * radius * (0.9 + (n - 0.5) * 0.28)
		_append_faces(_leaves, verts, unit_f, leaf)


func _finish_trees() -> void:
	if _bark == null or _bark.verts.is_empty():
		return
	var bark_mi := _add_mesh_child(self, _bark.to_mesh(), _bark_mat, "Trunks", true)
	bark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var leaf_mi := _add_mesh_child(self, _leaves.to_mesh(), _leaf_mat, "Canopy", true)
	leaf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- dry-stone walls ---------------------------------------------------------

func _build_walls() -> void:
	var n := _data.road_points.size()
	var i := _rng.randi_range(0, n - 1)
	var guard := 0
	while _stone_count < STONE_BUDGET - 800 and guard < n * 3:
		guard += 1
		i = (i + _rng.randi_range(8, 18)) % n
		if _rng.randf() > 0.8:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		if _rng.randf() < 0.62:
			_try_field(i, side)
		else:
			_try_single(i, side)
		if _stone_count >= STONE_BUDGET:
			break
	if _stone_count < 18000:
		var j := 0
		while _stone_count < STONE_BUDGET - 800 and j < n:
			j += _rng.randi_range(6, 12)
			_try_single(j % n, -1.0 if _rng.randf() < 0.5 else 1.0)
	_flush_kind("wall", _stone_meshes, _stone_mat, 460.0, true)


func _try_field(i: int, side: float) -> void:
	var f := _frame(i)
	var p: Vector3 = f[0]
	var t: Vector3 = f[1]
	var right: Vector3 = f[2]
	var outward := right * side
	var d_near := _rng.randf_range(28.0, 52.0)
	var d_far := clampf(d_near + _rng.randf_range(16.0, 32.0), d_near + 14.0, 80.0)
	var length := _rng.randf_range(28.0, 70.0)
	var origin_a := p + outward * d_near - t * length * 0.5
	var origin_b := p + outward * d_far - t * length * 0.5
	if _wall_blocked(origin_a.x, origin_a.z):
		return
	var a := _trace(origin_a, t, length, true)
	var b := _trace(origin_b, t, length, true)
	if a.size() >= 22:
		_commit_wall(a)
	if b.size() >= 22:
		_commit_wall(b)
	if a.size() >= 22 and b.size() >= 16:
		_commit_wall(_trace(a[2], outward, d_far - d_near + 1.0, false))
		_commit_wall(_trace(a[a.size() - 3], outward, d_far - d_near + 1.0, false))
	elif a.size() >= 24 and _rng.randf() < 0.5:
		_commit_wall(_trace(a[_rng.randi_range(2, a.size() - 3)], -outward, 28.0, true))


func _try_single(i: int, side: float) -> void:
	var f := _frame(i)
	var p: Vector3 = f[0]
	var t: Vector3 = f[1]
	var right: Vector3 = f[2]
	var dist := _rng.randf_range(25.0, 78.0)
	var length := _rng.randf_range(24.0, 80.0)
	var origin := p + right * side * dist - t * length * 0.5
	if _wall_blocked(origin.x, origin.z) or not _wall_ok(origin.x, origin.z):
		return
	var pts := _trace(origin, t, length, true)
	if pts.size() < 20:
		return
	_commit_wall(pts)
	if _rng.randf() < 0.55 and pts.size() > 24:
		var at: Vector3 = pts[_rng.randi_range(4, pts.size() - 5)]
		var spur := right * side if _rng.randf() < 0.5 else -right * side
		_commit_wall(_trace(at, spur, _rng.randf_range(12.0, 36.0), true))


func _trace(origin: Vector3, dir: Vector3, length: float, stop_on_wall: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var d := dir
	d.y = 0.0
	if d.length_squared() < 1e-8:
		return pts
	d = d.normalized()
	var steps := int(length / 0.5)
	var yaw := 0.0
	var pos := origin
	var start_key := _occ_key(origin.x, origin.z)
	for s in steps:
		if _stone_count >= STONE_BUDGET:
			break
		if not _wall_ok(pos.x, pos.z):
			break
		if stop_on_wall and s > 4 and _wall_blocked(pos.x, pos.z) and _occ_key(pos.x, pos.z) != start_key:
			break
		pts.append(Vector3(pos.x, _data.height_at(pos.x, pos.z), pos.z))
		yaw = clampf(yaw + _rng.randf_range(-0.03, 0.03), -0.16, 0.16)
		pos += d.rotated(Vector3.UP, yaw) * 0.5
	return pts


func _commit_wall(pts: Array[Vector3]) -> void:
	if pts.size() < 18 or _stone_count >= STONE_BUDGET:
		return
	_lay_stones(pts)
	_mark_wall(pts)
	_wall_runs += 1
	if pts.size() > _best_wall.size():
		_best_wall = pts


func _lay_stones(pts: Array[Vector3]) -> void:
	var course := _rng.randf_range(0.55, 0.64)
	for i in pts.size():
		if _stone_count >= STONE_BUDGET:
			return
		var p := pts[i]
		var prev := pts[maxi(i - 1, 0)]
		var nxt := pts[mini(i + 1, pts.size() - 1)]
		var dir := nxt - prev
		dir.y = 0.0
		if dir.length_squared() < 1e-6:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var x_axis := Vector3.UP.cross(dir).normalized()
		for course_i in 2:
			var along := 0.24 if course_i == 1 else 0.0
			var y := p.y + 0.38 + float(course_i) * 0.22 + (course - 0.6) * 0.02
			var pos := Vector3(p.x, y, p.z) + dir * along
			pos += x_axis * (_rng.randf_range(-0.03, 0.03) + (0.08 if course_i == 0 else -0.02))
			pos.y += _rng.randf_range(-0.02, 0.015)
			var variant := _rng.randi() % 3
			var b := Basis(x_axis, Vector3.UP, dir)
			b *= Basis.from_euler(Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(-0.04, 0.04), _rng.randf_range(-0.025, 0.025)))
			b = b.scaled(Vector3(_rng.randf_range(0.92, 1.08), _rng.randf_range(0.88, 1.08), _rng.randf_range(0.92, 1.16)))
			var col := Color(_rng.randf_range(0.42, 0.82), _rng.randf_range(0.12, 0.42), _rng.randf_range(0.45, 1.0), _rng.randf())
			_add_inst("wall", pos.x, pos.z, variant, Transform3D(b, pos), col)
			_stone_count += 1


# --- boulders ----------------------------------------------------------------

func _build_boulders() -> void:
	var target := 880
	var tries := 0
	while _boulder_count < target and tries < 26000:
		tries += 1
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(600.0, 4900.0)
		if _rng.randf() < 0.45:
			ang = PI + _rng.randf_range(-1.2, 1.2)
			rad = _rng.randf_range(2800.0, 4900.0)
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var h := _data.height_at(x, z)
		if h < 1.5 or h > 420.0:
			continue
		var nrm := _data.normal_at(x, z)
		var steep := nrm.y < 0.86
		var coastal := false
		if h < 36.0:
			var out_d := Vector2(x, z)
			if out_d.length_squared() > 1.0:
				out_d = out_d.normalized()
				for step in [25.0, 55.0, 90.0]:
					if _data.height_at(x + out_d.x * step, z + out_d.y * step) < 0.4:
						coastal = true
						break
		if not steep and not coastal:
			continue
		if _near_road(x, z, 14.0) or _near_house(x, z, 16.0):
			continue
		var sy := _rng.randf_range(0.45, 2.6)
		if _rng.randf() < 0.72:
			sy = _rng.randf_range(0.45, 1.4)
		var sx := sy * _rng.randf_range(0.75, 1.4)
		var sz := sy * _rng.randf_range(0.7, 1.35)
		var y_axis := nrm
		var x_axis := Vector3.UP.cross(nrm)
		if x_axis.length_squared() < 1e-4:
			x_axis = Vector3.RIGHT
		x_axis = x_axis.normalized()
		var z_axis := x_axis.cross(y_axis).normalized()
		var b := Basis(x_axis, y_axis, z_axis)
		b *= Basis.from_euler(Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf() * TAU, _rng.randf_range(-0.15, 0.15)))
		b = b.scaled(Vector3(sx, sy, sz))
		var pos := Vector3(x, h, z) - nrm * (sy * 0.16)
		var variant := _rng.randi() % _rock_meshes.size()
		var moss := _rng.randf_range(0.45, 1.0) if coastal else _rng.randf_range(0.15, 0.7)
		var col := Color(_rng.randf_range(0.2, 0.45), _rng.randf_range(0.08, 0.32), moss, _rng.randf())
		_add_inst("rock", x, z, variant, Transform3D(b, pos), col)
		_boulder_count += 1
		if coastal and h > 10.0 and h < 55.0 and sy > _boulder_sample_s:
			_boulder_sample = pos + nrm * (sy * 0.35)
			_boulder_sample_s = sy
	_flush_kind("rock", _rock_meshes, _stone_mat, 340.0, true)
	_finish_trees()


# --- guard rails -------------------------------------------------------------

func _build_rails() -> void:
	var n := _data.road_points.size()
	var off := TerrainData.ROAD_HALF_WIDTH + TerrainData.ROAD_SHOULDER + 0.3
	var loop := _w_loop()
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var active: Array[bool] = []
		active.resize(n)
		for i in n:
			var f := _frame(i)
			var p: Vector3 = f[0]
			var right: Vector3 = f[2]
			# The road carve flattens the first ~15 m, so the cliff only shows
			# up a little further out. The rail itself still sits on the shoulder.
			var sample := p + right * side * 20.0
			var drop := p.y - _data.height_at(sample.x, sample.z)
			active[i] = drop > 4.5
		var gap_at := -1
		for i in n:
			if not active[i]:
				gap_at = i
				break
		var run: Array[int] = []
		if gap_at < 0:
			for i in n:
				run.append(i)
			_flush_run(run, side, off, loop, true)
		else:
			for k in n:
				var i := (gap_at + 1 + k) % n
				if active[i]:
					run.append(i)
					if run.size() >= 40:
						_flush_run(run, side, off, loop, false)
						run = [run[run.size() - 1]]
				else:
					_flush_run(run, side, off, loop, false)
					run = []
			_flush_run(run, side, off, loop, false)


func _flush_run(run: Array[int], side: float, off: float, loop: PackedVector2Array, split: bool) -> void:
	if run.size() < 2:
		return
	if split:
		var i := 0
		while i < run.size() - 1:
			var j := mini(i + 40, run.size())
			_emit_rail(run.slice(i, j), side, off, loop)
			i = j - 1
		return
	_emit_rail(run, side, off, loop)


func _emit_rail(run: Array, side: float, off: float, loop: PackedVector2Array) -> void:
	if run.size() < 2:
		return
	var acc := Acc.new()
	var stations: Array[Dictionary] = []
	for k in run.size():
		stations.append(_rail_station(int(run[k]), side, off, true, float(k) * 4.0))
		if k + 1 < run.size():
			stations.append(_rail_station_mid(int(run[k]), int(run[k + 1]), side, off, float(k) * 4.0 + 2.0))
	var lp := loop.size()
	for s in stations.size() - 1:
		var a_st: Dictionary = stations[s]
		var b_st: Dictionary = stations[s + 1]
		var o0: Vector3 = a_st["o"]
		var o1: Vector3 = b_st["o"]
		var in0: Vector3 = a_st["in"]
		var in1: Vector3 = b_st["in"]
		var chain0: float = a_st["chain"]
		var chain1: float = b_st["chain"]
		for p in lp:
			var q0: Vector2 = loop[p]
			var q1: Vector2 = loop[(p + 1) % lp]
			var a := o0 + in0 * q0.x + Vector3.UP * q0.y
			var b := o0 + in0 * q1.x + Vector3.UP * q1.y
			var c := o1 + in1 * q1.x + Vector3.UP * q1.y
			var d := o1 + in1 * q0.x + Vector3.UP * q0.y
			var mid := (a + b + c + d) * 0.25
			acc.add_face(a, b, c, d, mid - (o0 + o1) * 0.5, Color.WHITE,
				Vector2(float(p), chain0), Vector2(float(p + 1), chain0),
				Vector2(float(p + 1), chain1), Vector2(float(p), chain1))
	for k in run.size():
		var i := int(run[k])
		var f := _frame(i)
		var p: Vector3 = f[0]
		var right: Vector3 = f[2]
		var tang: Vector3 = f[1]
		var px := p + right * side * off
		var ground := _data.height_at(px.x, px.z)
		var top := p.y + 0.58
		var bottom := p.y - 0.45
		if p.y - ground < 2.2 and p.y - ground > -0.4:
			bottom = minf(bottom, ground - 0.04)
		var height := maxf(top - bottom, 0.4)
		var center := Vector3(px.x, (top + bottom) * 0.5, px.z) + right * side * 0.05
		var basis := Basis(right, Vector3.UP, tang)
		acc.add_box(center, Vector3(0.09, height, 0.16), basis, Color.WHITE)
		_rail_posts += 1
	if _rail_sample == Vector3.ZERO:
		var mid_i := int(run[run.size() / 2])
		_rail_sample = _data.road_point(mid_i)
	var mi := _add_mesh_child(self, acc.to_mesh(), _rail_mat, "Rail", false)
	mi.visibility_range_end = 190.0
	mi.visibility_range_end_margin = 24.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track_shadow(mi, acc.verts[acc.verts.size() / 2])


func _rail_station(i: int, side: float, off: float, post: bool, chain: float) -> Dictionary:
	var f := _frame(i)
	var p: Vector3 = f[0]
	var tang: Vector3 = f[1]
	var right: Vector3 = f[2]
	var origin := p + right * side * off + Vector3.UP * 0.66
	return {"o": origin, "in": -right * side, "chain": chain, "post": post}


func _rail_station_mid(i0: int, i1: int, side: float, off: float, chain: float) -> Dictionary:
	var a := _rail_station(i0, side, off, false, chain)
	var b := _rail_station(i1, side, off, false, chain)
	var o: Vector3 = (a["o"] as Vector3).lerp(b["o"], 0.5)
	var inn: Vector3 = ((a["in"] as Vector3) + (b["in"] as Vector3)).normalized()
	return {"o": o, "in": inn, "chain": chain, "post": false}


func _w_loop() -> PackedVector2Array:
	var cl: Array[Vector2] = [
		Vector2(0.00, 0.150), Vector2(0.040, 0.142), Vector2(0.058, 0.095),
		Vector2(0.016, 0.048), Vector2(0.016, 0.012), Vector2(0.058, -0.012),
		Vector2(0.058, -0.048), Vector2(0.016, -0.095), Vector2(0.040, -0.142),
		Vector2(0.00, -0.150),
	]
	var n := cl.size()
	var tang: Array[Vector2] = []
	for i in n:
		var a: Vector2 = cl[maxi(i - 1, 0)]
		var b: Vector2 = cl[mini(i + 1, n - 1)]
		var d := b - a
		tang.append(d.normalized() if d.length_squared() > 1e-8 else Vector2.RIGHT)
	var loop := PackedVector2Array()
	var half := 0.006
	for i in n:
		var nor := Vector2(-tang[i].y, tang[i].x)
		loop.append(cl[i] + nor * half)
	for i in range(n - 1, -1, -1):
		var nor := Vector2(-tang[i].y, tang[i].x)
		loop.append(cl[i] - nor * half)
	return loop


# --- instancing --------------------------------------------------------------

func _add_inst(kind: String, x: float, z: float, variant: int, xf: Transform3D, col: Color) -> void:
	var key := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
	var id := "%s|%d|%d|%d" % [kind, key.x, key.y, variant]
	var batch: Array = _batches.get(id, [])
	if batch.is_empty():
		batch = [[], []]
		_batches[id] = batch
	(batch[0] as Array).append(xf)
	(batch[1] as Array).append(col)


func _flush_kind(kind: String, meshes: Array, mat: Material, vis: float, shadow: bool) -> void:
	var ids: Array = _batches.keys()
	for id in ids:
		var s := String(id)
		if not s.begins_with(kind + "|"):
			continue
		var variant := int(s.split("|")[3])
		var batch: Array = _batches[id]
		_commit_mm(meshes[variant], batch[0], batch[1], mat, vis, shadow)
		_batches.erase(id)


func _commit_mm(mesh: Mesh, xforms: Array, cols: Array, mat: Material, vis: float, shadow: bool) -> void:
	var count := xforms.size()
	if count == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var buf := PackedFloat32Array()
	buf.resize(count * 16)
	var mn := Vector3(1.0e9, 1.0e9, 1.0e9)
	var mx := Vector3(-1.0e9, -1.0e9, -1.0e9)
	var k := 0
	for i in count:
		var xf: Transform3D = xforms[i]
		var b := xf.basis
		var o := xf.origin
		var c: Color = cols[i]
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = o.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = o.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = o.z
		buf[k + 12] = c.r
		buf[k + 13] = c.g
		buf[k + 14] = c.b
		buf[k + 15] = c.a
		k += 16
		mn = mn.min(o)
		mx = mx.max(o)
	mm.buffer = buf
	var aabb := AABB(mn - Vector3(3, 2, 3), (mx - mn) + Vector3(6, 8, 6))
	mm.custom_aabb = aabb
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.custom_aabb = aabb
	inst.visibility_range_end = vis
	inst.visibility_range_end_margin = 36.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	if shadow:
		_track_shadow(inst, aabb.get_center())


func _track_shadow(node: GeometryInstance3D, at: Vector3) -> void:
	_shadow_nodes.append(node)
	_shadow_at.append(at)
	_shadow_on.append(0)


func _update_shadows() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var cp := cam.global_position
	for i in _shadow_nodes.size():
		var on := _shadow_at[i].distance_squared_to(cp) < SHADOW_RANGE * SHADOW_RANGE
		var flag := 1 if on else 0
		if _shadow_on[i] == flag:
			continue
		_shadow_on[i] = flag
		_shadow_nodes[i].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- meshes ------------------------------------------------------------------

func _make_stone_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	out.append(_jitter_box(Vector3(0.60, 0.64, 0.90), 0.045, 11))
	out.append(_jitter_box(Vector3(0.66, 0.58, 0.76), 0.04, 29))
	out.append(_jitter_box(Vector3(0.56, 0.70, 1.04), 0.05, 47))
	return out


func _make_rock_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	out.append(_rock_mesh(2, 1.0, 1.15, Vector3(1.05, 0.82, 0.9)))
	out.append(_rock_mesh(2, 2.4, 1.25, Vector3(0.9, 0.7, 1.15)))
	out.append(_rock_mesh(2, 3.1, 0.95, Vector3(1.2, 0.78, 0.85)))
	out.append(_rock_mesh(2, 5.5, 1.35, Vector3(1.15, 0.65, 1.0)))
	return out


func _jitter_box(size: Vector3, jitter: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var acc := Acc.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c: Array[Vector3] = []
	for z in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for x in [-1.0, 1.0]:
				c.append(Vector3(
					x * hx + rng.randf_range(-jitter, jitter),
					y * hy + rng.randf_range(-jitter * 0.65, jitter * 0.65),
					z * hz + rng.randf_range(-jitter, jitter)))
	# Corner order: x + 2*y + 4*z with x,y,z in {0,1} mapped from -1,1.
	acc.add_face(c[1], c[5], c[7], c[3], Vector3.RIGHT, Color.WHITE)
	acc.add_face(c[4], c[0], c[2], c[6], Vector3.LEFT, Color.WHITE)
	acc.add_face(c[2], c[3], c[7], c[6], Vector3.UP, Color.WHITE)
	acc.add_face(c[0], c[4], c[5], c[1], Vector3.DOWN, Color.WHITE)
	acc.add_face(c[5], c[4], c[6], c[7], Vector3.BACK, Color.WHITE)
	acc.add_face(c[0], c[1], c[3], c[2], Vector3.FORWARD, Color.WHITE)
	return acc.to_mesh()


func _ico_base() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	if (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]]).dot(v[f[0]]) < 0.0:
		for i in range(0, f.size(), 3):
			var tmp := f[i + 1]
			f[i + 1] = f[i + 2]
			f[i + 2] = tmp
	return [v, f]


func _subdivide(src_v: PackedVector3Array, src_f: PackedInt32Array) -> Array:
	var verts := src_v.duplicate()
	var cache := {}
	var faces := PackedInt32Array()
	var mid := func(i: int, j: int) -> int:
		var a := mini(i, j)
		var b := maxi(i, j)
		var key := a * 8192 + b
		if cache.has(key):
			return int(cache[key])
		verts.append(((verts[i] + verts[j]) * 0.5).normalized())
		var idx := verts.size() - 1
		cache[key] = idx
		return idx
	for t in range(0, src_f.size(), 3):
		var i0 := src_f[t]
		var i1 := src_f[t + 1]
		var i2 := src_f[t + 2]
		var a: int = mid.call(i0, i1)
		var b: int = mid.call(i1, i2)
		var c: int = mid.call(i2, i0)
		faces.append_array([i0, a, c, i1, b, a, i2, c, b, a, b, c])
	return [verts, faces]


func _ico(subdiv: int) -> Array:
	if _ico_cache.is_empty():
		_ico_cache.append(_ico_base())
	while _ico_cache.size() <= subdiv:
		var prev: Array = _ico_cache[_ico_cache.size() - 1]
		_ico_cache.append(_subdivide(prev[0], prev[1]))
	return _ico_cache[subdiv]


func _rock_mesh(subdiv: int, seed: float, amp: float, scale: Vector3) -> ArrayMesh:
	var src: Array = _ico(subdiv)
	var verts: PackedVector3Array = (src[0] as PackedVector3Array).duplicate()
	var faces: PackedInt32Array = src[1]
	for i in verts.size():
		var p := verts[i]
		var nse := _value_noise(p * 2.1 + Vector3(seed, seed * 1.7, seed * 0.37))
		var n2 := _value_noise(p * 6.4 + Vector3(seed * 2.2, 4.0, seed))
		p *= 1.0 + (nse - 0.5) * amp + (n2 - 0.5) * amp * 0.55
		verts[i] = Vector3(p.x * scale.x, p.y * scale.y, p.z * scale.z)
	return _mesh_from_faces(verts, faces, Color.WHITE)


func _mesh_from_faces(verts: PackedVector3Array, faces: PackedInt32Array, col: Color) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.ZERO)
	for t in range(0, faces.size(), 3):
		var i0 := faces[t]
		var i1 := faces[t + 1]
		var i2 := faces[t + 2]
		var n := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-8 else Vector3.UP
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(col)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	uvs.fill(Vector2.ZERO)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_faces(acc: Acc, verts: PackedVector3Array, faces: PackedInt32Array, col: Color) -> void:
	for t in range(0, faces.size(), 3):
		acc.add_tri(verts[faces[t]], verts[faces[t + 1]], verts[faces[t + 2]], col)


func _hash_cell(ix: int, iy: int, iz: int) -> float:
	var n := sin(float(ix) * 127.1 + float(iy) * 311.7 + float(iz) * 74.7) * 43758.5453
	return n - floor(n)


func _value_noise(p: Vector3) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var iz := floori(p.z)
	var fx := p.x - float(ix)
	var fy := p.y - float(iy)
	var fz := p.z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var n000 := _hash_cell(ix, iy, iz)
	var n100 := _hash_cell(ix + 1, iy, iz)
	var n010 := _hash_cell(ix, iy + 1, iz)
	var n110 := _hash_cell(ix + 1, iy + 1, iz)
	var n001 := _hash_cell(ix, iy, iz + 1)
	var n101 := _hash_cell(ix + 1, iy, iz + 1)
	var n011 := _hash_cell(ix, iy + 1, iz + 1)
	var n111 := _hash_cell(ix + 1, iy + 1, iz + 1)
	var x00 := lerpf(n000, n100, fx)
	var x10 := lerpf(n010, n110, fx)
	var x01 := lerpf(n001, n101, fx)
	var x11 := lerpf(n011, n111, fx)
	return lerpf(lerpf(x00, x10, fy), lerpf(x01, x11, fy), fz)


func _cylinder(radius_bottom: float, radius_top: float, height: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius_bottom
	m.top_radius = radius_top
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	return m


func _add_primitive(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _add_mesh_child(parent: Node3D, mesh: ArrayMesh, mat: Material, node_name: String, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _merge(dst: Acc, src: Acc, xf: Transform3D) -> void:
	if src.verts.is_empty():
		return
	var base := dst.verts.size()
	var b := xf.basis
	for i in src.verts.size():
		dst.verts.append(xf * src.verts[i])
		var n := b * src.normals[i]
		dst.normals.append(n.normalized() if n.length_squared() > 1e-8 else Vector3.UP)
		dst.colors.append(src.colors[i])
		dst.uvs.append(src.uvs[i])
	for i in src.indices.size():
		dst.indices.append(src.indices[i] + base)


# --- materials and shots -----------------------------------------------------

func _make_materials() -> void:
	_stone_mat = ShaderMaterial.new()
	_stone_mat.shader = preload("res://shaders/stone.gdshader")
	_build_mat = ShaderMaterial.new()
	_build_mat.shader = preload("res://shaders/building.gdshader")
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = preload("res://shaders/foliage.gdshader")
	_rail_mat = ShaderMaterial.new()
	_rail_mat.shader = preload("res://shaders/rail.gdshader")
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://shaders/beam.gdshader")
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(0.22, 0.14, 0.07)
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.62, 0.28)
	_window_mat.emission_energy_multiplier = 0.0
	_window_mat.roughness = 0.35
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.62, 0.78, 0.84, 0.22)
	_glass_mat.roughness = 0.05
	_glass_mat.metallic = 0.05
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(0.85, 0.92, 1.0)
	_glass_mat.emission_energy_multiplier = 0.0
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color = Color(0.95, 0.94, 0.9)
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color(1.0, 0.97, 0.9)
	_lens_mat.emission_energy_multiplier = 0.0
	_lens_mat.roughness = 0.12
	_bark_mat = StandardMaterial3D.new()
	_bark_mat.vertex_color_use_as_albedo = true
	_bark_mat.roughness = 0.92
	_metal_mat = StandardMaterial3D.new()
	_metal_mat.albedo_color = Color(0.02, 0.02, 0.025)
	_metal_mat.metallic = 0.72
	_metal_mat.roughness = 0.32
	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.albedo_color = Color(0.55, 0.53, 0.50)
	_concrete_mat.roughness = 0.88
	_white_mat = StandardMaterial3D.new()
	_white_mat.albedo_color = Color(0.86, 0.84, 0.80)
	_white_mat.roughness = 0.62


func _print_shots() -> void:
	if _best_wall.size() >= 2:
		var mid: Vector3 = _best_wall[_best_wall.size() / 2]
		var a: Vector3 = _best_wall[0]
		var b: Vector3 = _best_wall[_best_wall.size() - 1]
		var dir := b - a
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
		var side := Vector3.UP.cross(dir).normalized()
		var cam := mid + side * 8.0 + Vector3.UP * 1.7
		cam.y = _data.height_at(cam.x, cam.z) + 2.3
		print("PROPS shot wall cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam.x, cam.y, cam.z, mid.x, mid.y + 0.6, mid.z])
		var wide := mid + side * 22.0 + dir * 14.0 + Vector3.UP * 3.0
		wide.y = _data.height_at(wide.x, wide.z) + 2.4
		print("PROPS shot wall_wide cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [wide.x, wide.y, wide.z, mid.x, mid.y + 0.8, mid.z])
	for i in _houses.size():
		if i == 0 and _lighthouse != Vector3.ZERO and _houses[0].distance_to(_lighthouse) < 30.0:
			continue
		var h := _houses[i]
		var cam_h := h + Vector3(14.0, 0.0, 10.0)
		cam_h.y = _data.height_at(cam_h.x, cam_h.z) + 2.2
		print("PROPS shot house cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam_h.x, cam_h.y, cam_h.z, h.x, h.y + 2.0, h.z])
		break
	if _lighthouse != Vector3.ZERO:
		var inland := Vector3(-_cliff.x, 0.0, -_cliff.y).normalized()
		var cam_l := _lighthouse + inland * 42.0 + Vector3.UP * 6.0
		cam_l.y = maxf(_data.height_at(cam_l.x, cam_l.z) + 3.0, _lighthouse.y + 4.0)
		var look := _lighthouse + Vector3(0, 14.0, 0)
		print("PROPS shot light cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam_l.x, cam_l.y, cam_l.z, look.x, look.y, look.z])
		var idx := _data.nearest_road_index(_lighthouse)
		var rp := _data.road_point(idx)
		var cam_r := rp + Vector3(0, 2.4, 0)
		print("PROPS shot light_road cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam_r.x, cam_r.y, cam_r.z, look.x, look.y, look.z])
	if _rail_sample != Vector3.ZERO:
		var ri := _data.nearest_road_index(_rail_sample)
		var f := _frame(ri)
		var p: Vector3 = f[0]
		var t: Vector3 = f[1]
		var cam_g := p - t * 12.0 + Vector3.UP * 2.0
		var look_g := p + t * 18.0 + Vector3.UP * 0.6
		print("PROPS shot rail cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam_g.x, cam_g.y, cam_g.z, look_g.x, look_g.y, look_g.z])
	if _boulder_sample != Vector3.ZERO and _boulder_sample.length_squared() > 1.0:
		var cam_b := _boulder_sample + Vector3(5.5, 0.0, 4.0)
		cam_b.y = maxf(_data.height_at(cam_b.x, cam_b.z) + 1.4, _boulder_sample.y + 0.6)
		print("PROPS shot rock cam %.1f,%.1f,%.1f look %.1f,%.1f,%.1f" % [cam_b.x, cam_b.y, cam_b.z, _boulder_sample.x, _boulder_sample.y + 0.6, _boulder_sample.z])
	for h in _houses:
		print("PROPS house %.1f %.1f %.1f" % [h.x, h.y, h.z])


class Acc extends RefCounted:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
		var n := (b - a).cross(c - a)
		var l := n.length()
		if l < 1e-8:
			return
		n /= l
		var i := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		normals.append(n)
		normals.append(n)
		normals.append(n)
		colors.append(col)
		colors.append(col)
		colors.append(col)
		uvs.append(uva)
		uvs.append(uvb)
		uvs.append(uvc)
		indices.append(i)
		indices.append(i + 1)
		indices.append(i + 2)

	func add_face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, uvd := Vector2.ZERO) -> void:
		if (b - a).cross(c - a).dot(outward) < 0.0:
			add_tri(a, d, c, col, uva, uvd, uvc)
			add_tri(a, c, b, col, uva, uvc, uvb)
		else:
			add_tri(a, b, c, col, uva, uvb, uvc)
			add_tri(a, c, d, col, uva, uvc, uvd)

	func add_box(center: Vector3, size: Vector3, basis: Basis, col: Color) -> void:
		var x := basis.x * (size.x * 0.5)
		var y := basis.y * (size.y * 0.5)
		var z := basis.z * (size.z * 0.5)
		var c0 := center + (-x - y - z)
		var c1 := center + (x - y - z)
		var c2 := center + (x - y + z)
		var c3 := center + (-x - y + z)
		var c4 := center + (-x + y - z)
		var c5 := center + (x + y - z)
		var c6 := center + (x + y + z)
		var c7 := center + (-x + y + z)
		add_face(c4, c5, c6, c7, basis.y, col)
		add_face(c3, c2, c1, c0, -basis.y, col)
		add_face(c1, c2, c6, c5, basis.x, col)
		add_face(c3, c0, c4, c7, -basis.x, col)
		add_face(c2, c3, c7, c6, basis.z, col)
		add_face(c0, c1, c5, c4, -basis.z, col)

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		if verts.size() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

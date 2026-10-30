class_name TerrainData
extends Node
## Island heightmap + coastal road loop. The base relief is baked on the GPU,
## the road is planned and carved on the CPU, and the result is cached in
## user://cache so later launches start quickly.

signal generated

const SIZE := 4096
const ECO_SIZE := 2048
const WORLD := 10240.0
const TEXEL := WORLD / SIZE
const H_MIN := -200.0
const H_RANGE := 1000.0
const CACHE_PATH := "user://cache/terrain_v7.bin"
const ROAD_HALF_WIDTH := 3.6
const ROAD_SHOULDER := 1.8
const ROAD_STEP := 4.0
const CARVE_REACH := 70.0

var heights := PackedFloat32Array()
var mask := PackedByteArray()
var road_points := PackedVector3Array()
var road_length := 0.0
var height_texture: ImageTexture
var normal_texture: ImageTexture
var mask_texture: ImageTexture
var eco_texture: ImageTexture
var eco_image: Image
var is_ready := false


func generate() -> void:
	var t0 := Time.get_ticks_msec()
	if not Game.args.has("regen") and _load_cache():
		print("terrain: cache loaded in %d ms" % (Time.get_ticks_msec() - t0))
	else:
		await _bake_base()
		var t1 := Time.get_ticks_msec()
		_build_road()
		_carve()
		_save_cache()
		print("terrain: base %d ms, road+carve %d ms, road %.1f km" % [t1 - t0, Time.get_ticks_msec() - t1, road_length / 1000.0])
	await _make_textures()
	is_ready = true
	generated.emit()


func height_at(x: float, z: float) -> float:
	var fx := (x + WORLD * 0.5) / TEXEL - 0.5
	var fz := (z + WORLD * 0.5) / TEXEL - 0.5
	var ix := clampi(floori(fx), 0, SIZE - 2)
	var iz := clampi(floori(fz), 0, SIZE - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var i := iz * SIZE + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + SIZE], heights[i + SIZE + 1], tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := TEXEL
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Index of the road point closest to a world position (coarse search).
func nearest_road_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in range(0, road_points.size(), 8):
		var d := Vector2(road_points[i].x - pos.x, road_points[i].z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	for i in range(best - 8, best + 9):
		var j := posmod(i, road_points.size())
		var d := Vector2(road_points[j].x - pos.x, road_points[j].z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = j
	return best


func road_point(i: int) -> Vector3:
	return road_points[posmod(i, road_points.size())]


func road_tangent(i: int) -> Vector3:
	return (road_point(i + 1) - road_point(i - 1)).normalized()


# --- generation ------------------------------------------------------------------

func _bake_base() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bake/terrain_height.gdshader")
	mat.set_shader_parameter("world_size", WORLD)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGF)
	var raw := img.get_data().to_float32_array()
	heights.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		heights[i] = (raw[i * 2] + raw[i * 2 + 1] / 1024.0) * H_RANGE + H_MIN
	mask.resize(SIZE * SIZE)
	mask.fill(0)


func _build_road() -> void:
	const N := 96
	var radii := PackedFloat32Array()
	var dirs: Array[Vector2] = []
	for k in N:
		var a := TAU * k / N
		var dir := Vector2(cos(a), sin(a))
		var coast := 4800.0
		var d := 600.0
		while d < 5000.0:
			if height_at(dir.x * d, dir.y * d) < 0.5:
				coast = d
				break
			d += 10.0
		var west := clampf(-dir.x - 0.15 * dir.y, 0.0, 1.0)
		var inset := lerpf(340.0, 115.0, smoothstep(0.35, 0.85, west))
		# Detour inland over the mountain pass (north-east) and a valley (south).
		var ne := angle_difference(a, -PI * 0.25)
		inset += 1150.0 * exp(-ne * ne / 0.12)
		var so := angle_difference(a, PI * 0.55)
		inset += 380.0 * exp(-so * so / 0.05)
		inset += 140.0 * sin(a * 7.0 + 1.3) + 90.0 * sin(a * 13.0)
		dirs.append(dir)
		radii.append(maxf(coast - inset, 800.0))
	for _pass in 1:
		var sm := radii.duplicate()
		for k in N:
			sm[k] = radii[posmod(k - 1, N)] * 0.25 + radii[k] * 0.5 + radii[(k + 1) % N] * 0.25
		radii = sm

	var ctrl: Array[Vector2] = []
	for k in N:
		ctrl.append(dirs[k] * radii[k])
	var dense: Array[Vector2] = []
	for i in N:
		var p0 := ctrl[posmod(i - 1, N)]
		var p1 := ctrl[i]
		var p2 := ctrl[(i + 1) % N]
		var p3 := ctrl[(i + 2) % N]
		for s in 48:
			var t := s / 48.0
			dense.append(_catmull(p0, p1, p2, p3, t))

	# Resample at a constant step along the arc.
	var pts: Array[Vector2] = [dense[0]]
	var carry := 0.0
	for i in dense.size():
		var a := dense[i]
		var b := dense[(i + 1) % dense.size()]
		var seg := a.distance_to(b)
		var pos := ROAD_STEP - carry
		while pos <= seg:
			pts.append(a.lerp(b, pos / seg))
			pos += ROAD_STEP
		carry = seg - (pos - ROAD_STEP)
	if pts[0].distance_to(pts[pts.size() - 1]) < ROAD_STEP * 0.5:
		pts.pop_back()

	# Vertical profile: smoothed terrain, kept above the sea, grade-limited.
	var n := pts.size()
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = maxf(height_at(pts[i].x, pts[i].y), 3.5)
	for _pass in 3:
		var sm := PackedFloat32Array()
		sm.resize(n)
		var win := 14
		var acc := 0.0
		for j in range(-win, win + 1):
			acc += h[posmod(j, n)]
		for i in n:
			sm[i] = acc / (2 * win + 1)
			acc += h[(i + win + 1) % n] - h[posmod(i - win, n)]
		h = sm
	var max_dh := 0.09 * ROAD_STEP
	for _pass in 6:
		for i in n:
			var prev := h[posmod(i - 1, n)]
			h[i] = clampf(h[i], prev - max_dh, prev + max_dh)
		for i in range(n - 1, -1, -1):
			var nxt := h[(i + 1) % n]
			h[i] = clampf(h[i], nxt - max_dh, nxt + max_dh)
	road_points.resize(n)
	for i in n:
		var ground := height_at(pts[i].x, pts[i].y)
		var y := h[i]
		if ground - y > 3.0:
			y += (ground - y - 3.0) * 0.5
		road_points[i] = Vector3(pts[i].x, maxf(y, 3.0), pts[i].y)
	road_length = n * ROAD_STEP


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _carve() -> void:
	var best := PackedFloat32Array()
	best.resize(SIZE * SIZE)
	best.fill(1e9)
	var target := PackedFloat32Array()
	target.resize(SIZE * SIZE)
	var touched := PackedInt32Array()
	var n := road_points.size()
	var reach_tx := int(ceil(CARVE_REACH / TEXEL)) + 1
	var half := WORLD * 0.5
	var i := 0
	while i < n:
		var a := road_points[i]
		var b := road_points[(i + 2) % n]
		var ax := (a.x + half) / TEXEL - 0.5
		var az := (a.z + half) / TEXEL - 0.5
		var bx := (b.x + half) / TEXEL - 0.5
		var bz := (b.z + half) / TEXEL - 0.5
		var x0 := clampi(int(minf(ax, bx)) - reach_tx, 0, SIZE - 1)
		var x1 := clampi(int(maxf(ax, bx)) + reach_tx, 0, SIZE - 1)
		var z0 := clampi(int(minf(az, bz)) - reach_tx, 0, SIZE - 1)
		var z1 := clampi(int(maxf(az, bz)) + reach_tx, 0, SIZE - 1)
		var abx := b.x - a.x
		var abz := b.z - a.z
		var inv := 1.0 / maxf(abx * abx + abz * abz, 1e-6)
		for z in range(z0, z1 + 1):
			var wz := (z + 0.5) * TEXEL - half
			var row := z * SIZE
			for x in range(x0, x1 + 1):
				var wx := (x + 0.5) * TEXEL - half
				var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) * inv, 0.0, 1.0)
				var dx := wx - (a.x + abx * t)
				var dz := wz - (a.z + abz * t)
				var d := sqrt(dx * dx + dz * dz)
				var idx := row + x
				if d < best[idx]:
					if best[idx] > 1e8:
						touched.append(idx)
					best[idx] = d
					target[idx] = lerpf(a.y, b.y, t)
		i += 2
	var flat := ROAD_HALF_WIDTH + ROAD_SHOULDER + 1.2
	for idx in touched:
		var d := best[idx]
		if d >= CARVE_REACH:
			continue
		var tgt := target[idx] - 0.15
		var dh := absf(heights[idx] - tgt)
		var slope_w := clampf(dh * 1.5, 5.0, CARVE_REACH - flat)
		var w := 1.0 - smoothstep(flat, flat + slope_w, d)
		heights[idx] = lerpf(heights[idx], tgt, w)
		mask[idx] = int(255.0 * (1.0 - smoothstep(flat - 2.2, flat + 0.6, d)))


func _save_cache() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	var f := FileAccess.open_compressed(CACHE_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var({"heights": heights, "mask": mask, "road": road_points, "length": road_length})
	f.close()


func _load_cache() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return false
	var f := FileAccess.open_compressed(CACHE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var d: Dictionary = f.get_var()
	f.close()
	heights = d["heights"]
	mask = d["mask"]
	road_points = d["road"]
	road_length = d["length"]
	return heights.size() == SIZE * SIZE


func _make_textures() -> void:
	var himg := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())
	height_texture = ImageTexture.create_from_image(himg)
	var mimg := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, mask)
	mimg.generate_mipmaps()
	mask_texture = ImageTexture.create_from_image(mimg)

	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bake/terrain_normals.gdshader")
	mat.set_shader_parameter("heightmap", height_texture)
	mat.set_shader_parameter("texel", TEXEL)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var nimg := vp.get_texture().get_image()
	vp.queue_free()
	nimg.convert(Image.FORMAT_RGBA8)
	if Game.args.has("dump_terrain"):
		var small := nimg.duplicate()
		small.resize(512, 512)
		small.save_png("res://dev/out/terrain_normals.png")
		var m2 := mimg.duplicate()
		m2.clear_mipmaps()
		m2.resize(512, 512)
		m2.save_png("res://dev/out/terrain_mask.png")
		var hv := Image.create(512, 512, false, Image.FORMAT_L8)
		for z in 512:
			for x in 512:
				hv.set_pixel(x, z, Color.from_hsv(0, 0, clampf((heights[z * 4 * SIZE + x * 4] + 20.0) / 300.0, 0.0, 1.0)))
		hv.save_png("res://dev/out/terrain_height.png")
	nimg.generate_mipmaps()
	normal_texture = ImageTexture.create_from_image(nimg)
	await _bake_eco()


## Where things grow: R grass density, G forest density, B shrubs, A dryness.
func _bake_eco() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(ECO_SIZE, ECO_SIZE)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(ECO_SIZE, ECO_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bake/terrain_eco.gdshader")
	mat.set_shader_parameter("heightmap", height_texture)
	mat.set_shader_parameter("normalmap", normal_texture)
	mat.set_shader_parameter("maskmap", mask_texture)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	eco_image = vp.get_texture().get_image()
	vp.queue_free()
	eco_image.convert(Image.FORMAT_RGBA8)
	if Game.args.has("dump_terrain"):
		eco_image.save_png("res://dev/out/terrain_eco.png")
	var mipped := eco_image.duplicate()
	mipped.generate_mipmaps()
	eco_texture = ImageTexture.create_from_image(mipped)


func eco_at(x: float, z: float) -> Color:
	var px := clampi(int((x + WORLD * 0.5) / WORLD * ECO_SIZE), 0, ECO_SIZE - 1)
	var pz := clampi(int((z + WORLD * 0.5) / WORLD * ECO_SIZE), 0, ECO_SIZE - 1)
	return eco_image.get_pixel(px, pz)

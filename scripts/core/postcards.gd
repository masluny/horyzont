class_name Postcards
extends Node
## "Pocztówki": places on the island that need a particular light or weather.
## Drive there, wait for the moment (T speeds up time), press F for a photo.
## Photos go to user://album as PNG + JSON sidecar.

signal photo_taken(texture: Texture2D, title: String, stars: int)

const ALBUM_DIR := "user://album"
const PROGRESS_PATH := "user://progress.cfg"
const NEAR := 90.0

var cards: Array[Dictionary] = []
var current := 0
var done := {}

var ui: UIRoot
var terrain: TerrainData
var beacon: MeshInstance3D

var _hint_cooldown := 0.0
var _was_near := false


func setup(p_terrain: TerrainData, p_ui: UIRoot) -> void:
	terrain = p_terrain
	ui = p_ui
	_define_cards()
	_load_progress()
	_make_beacon()
	_select(_first_open())


func _define_cards() -> void:
	var pts := terrain.road_points
	var west := 0
	var east := 0
	var north := 0
	var south := 0
	var high := 0
	for i in pts.size():
		if pts[i].x < pts[west].x: west = i
		if pts[i].x > pts[east].x: east = i
		if pts[i].z < pts[north].z: north = i
		if pts[i].z > pts[south].z: south = i
		if pts[i].y > pts[high].y: high = i
	var islets := terrain.nearest_road_index(Vector3(-3300, 0, 900))
	cards = [
		_card("zlote_klify", "Złota godzina na klifach", "Słońce 0–8° nad horyzontem, bez deszczu.", west,
			func(): return _sun(0.5, 8.0) and not _weather(["deszcz", "pochmurno"])),
		_card("zachod_wysepki", "Zachód nad wysepkami", "Słońce dotyka horyzontu (−1° do 2,5°) wieczorem.", islets,
			func(): return _sun(-1.0, 2.5) and _evening()),
		_card("niebieska_godzina", "Niebieska godzina", "Słońce 3–8° pod horyzontem.", north,
			func(): return _sun(-8.0, -3.0)),
		_card("swit_przelecz", "Świt na przełęczy", "Rano, słońce od −3° do 5°.", high,
			func(): return _sun(-3.0, 5.0) and not _evening()),
		_card("mgla_dolina", "Mgła w dolinie", "Poranna mgła (pogoda „Poranna mgła”).", south,
			func(): return _weather(["poranna_mgla"])),
		_card("burza", "Burzowe niebo", "Burzowy zachód albo deszcz.", east,
			func(): return _weather(["burzowy_zachod", "deszcz"])),
		_card("gwiazdy", "Gwiazdy nad wyspą", "Głęboka noc (słońce poniżej −14°), pogodnie.", high,
			func(): return _sun(-90.0, -14.0) and _weather(["pogodnie", "po_deszczu"])),
		_card("plaza_poranek", "Plaża o poranku", "Słońce 1–15° rano.", east,
			func(): return _sun(1.0, 15.0) and not _evening()),
		_card("po_deszczu", "Mokra droga po deszczu", "Po deszczu: mokry asfalt odbija niebo.", north + 60,
			func(): return Game.weather.wetness > 0.4 and Game.weather.rain < 0.2),
	]


func _card(id: String, title: String, hint: String, road_index: int, cond: Callable) -> Dictionary:
	var p := terrain.road_point(road_index)
	return {"id": id, "title": title, "hint": hint, "pos": p, "cond": cond}


func _sun(lo: float, hi: float) -> bool:
	var e := Game.clock.sun_elevation_deg()
	return e >= lo and e <= hi


func _evening() -> bool:
	return Game.clock.time > 12.0


func _weather(ids: Array) -> bool:
	return ids.has(Game.weather.current_id)


func _first_open() -> int:
	for i in cards.size():
		if not done.has(cards[i]["id"]):
			return i
	return 0


func next_card() -> void:
	_select((current + 1) % cards.size())


func _select(i: int) -> void:
	current = i
	var c := cards[i]
	if ui and ui.hud:
		var mark := " ✓" if done.has(c["id"]) else ""
		ui.hud.set_objective("%s%s — %s" % [c["title"], mark, c["hint"]], c["pos"])
	if beacon:
		beacon.global_position = c["pos"] + Vector3(0, 80, 0)


func is_ready_here(pos: Vector3) -> bool:
	var c := cards[current]
	return pos.distance_to(c["pos"]) < NEAR and c["cond"].call()


func _process(delta: float) -> void:
	if cards.is_empty() or Game.car == null or ui == null:
		return
	_hint_cooldown -= delta
	var c := cards[current]
	var near := Game.car.global_position.distance_to(c["pos"]) < NEAR
	if near and not _was_near:
		_hint_cooldown = 0.0
	_was_near = near
	if near and _hint_cooldown <= 0.0:
		_hint_cooldown = 8.0
		if c["cond"].call():
			ui.hud.show_toast("Kadr gotowy — naciśnij F, aby zrobić zdjęcie", 5.0)
		else:
			ui.hud.show_toast("%s  (T — przyspiesz czas)" % c["hint"], 5.0)
	if beacon:
		var mat := beacon.material_override as ShaderMaterial
		mat.set_shader_parameter("fade", clampf((Game.car.global_position.distance_to(c["pos"]) - 40.0) / 200.0, 0.0, 1.0))


func take_photo() -> void:
	var c := cards[current]
	var pos := get_viewport().get_camera_3d().global_position
	var at_card := pos.distance_to(c["pos"]) < NEAR * 1.4 or Game.car.global_position.distance_to(c["pos"]) < NEAR
	var stars := 0
	var title := "Wolne zdjęcie"
	if at_card:
		title = c["title"]
		stars = 1
		if c["cond"].call():
			stars = 2
			if _sun_in_frame() or Game.clock.sun_elevation_deg() < -3.0:
				stars = 3
	ui.visible = false
	if beacon:
		beacon.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	ui.visible = true
	if beacon:
		beacon.visible = true
	DirAccess.make_dir_recursive_absolute(ALBUM_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := "%s/%s_%s" % [ALBUM_DIR, c["id"] if at_card else "wolne", stamp]
	img.save_png(base + ".png")
	var meta := {"title": title, "stars": stars, "time": "%02d:%02d" % [int(Game.clock.time), int(fmod(Game.clock.time, 1.0) * 60.0)],
		"weather": Game.weather.preset_name()}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	if at_card and stars > int(done.get(c["id"], 0)):
		done[c["id"]] = stars
		_save_progress()
	var tex := ImageTexture.create_from_image(img)
	photo_taken.emit(tex, title, stars)
	if ui.photo_overlay:
		ui.photo_overlay.flash()
		ui.photo_overlay.show_result(tex, title, stars)
	if at_card and stars >= 2:
		await get_tree().create_timer(3.5).timeout
		_select(_first_open())


func _sun_in_frame() -> bool:
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	return fwd.angle_to(Game.clock.sun_dir) < deg_to_rad(cam.fov * 0.6)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	for k in done:
		cfg.set_value("done", k, done[k])
	cfg.save(PROGRESS_PATH)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return
	if cfg.has_section("done"):
		for k in cfg.get_section_keys("done"):
			done[k] = cfg.get_value("done", k)


func _make_beacon() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 160.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/beacon.gdshader")
	beacon = MeshInstance3D.new()
	beacon.mesh = cyl
	beacon.material_override = mat
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	beacon.top_level = true

extends Node
# Prints heightmap statistics after generation (run as an autoload-free helper via --stats).
func _ready() -> void:
	await get_tree().create_timer(0.1).timeout
	while Game.terrain == null or not Game.terrain.is_ready:
		await get_tree().process_frame
	var h := Game.terrain.heights
	var mn := INF
	var mx := -INF
	var land := 0
	var sum := 0.0
	for i in range(0, h.size(), 17):
		mn = minf(mn, h[i]); mx = maxf(mx, h[i]); sum += h[i]
		if h[i] > 0.0: land += 1
	print("STATS min=%.1f max=%.1f mean=%.1f land%%=%.1f" % [mn, mx, sum / (h.size() / 17), 100.0 * land / (h.size() / 17)])
	for p in [Vector2(0, 0), Vector2(900, -1000), Vector2(-3000, 0), Vector2(2000, 2000), Vector2(-1500, 1500)]:
		print("STATS h(%s)=%.1f" % [p, Game.terrain.height_at(p.x, p.y)])
	var r := Game.terrain.road_points
	var rmin := INF
	var rmax := -INF
	for p in r:
		rmin = minf(rmin, p.y); rmax = maxf(rmax, p.y)
	print("STATS road y %.1f..%.1f n=%d" % [rmin, rmax, r.size()])
	get_tree().quit()

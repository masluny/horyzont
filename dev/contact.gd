extends SceneTree
# godot --headless --script dev/contact.gd -- out.png cols width img1 img2 ...

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var cols := int(a[1])
	var w := int(a[2])
	var imgs: Array[Image] = []
	for i in range(3, a.size()):
		var img := Image.load_from_file(a[i])
		img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		imgs.append(img)
	var h := imgs[0].get_height()
	var rows := int(ceil(imgs.size() / float(cols)))
	var sheet := Image.create(cols * w + (cols - 1) * 4, rows * h + (rows - 1) * 4, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.2, 0.2, 0.2))
	for i in imgs.size():
		imgs[i].convert(Image.FORMAT_RGB8)
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * (w + 4), (i / cols) * (h + 4)))
	sheet.save_png(out)
	quit()

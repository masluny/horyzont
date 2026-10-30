extends SceneTree
func _init() -> void:
	var t: Texture2D = load("res://assets/textures/leafy_grass/leafy_grass_diffuse.jpg")
	print("TEX ", t, " size=", t.get_size() if t else "null")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("grass_albedo", t)
	print("TEX param back: ", m.get_shader_parameter("grass_albedo"))
	for u in m.shader.get_shader_uniform_list():
		if String(u["name"]).begins_with("grass"):
			print("TEX uniform ", u["name"], " hint=", u["hint"], " type=", u["type"])
	quit()

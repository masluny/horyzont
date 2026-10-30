extends Node
## Global access point: command-line options and references to world systems.

var args := {}
var world: Node3D
var sky: SkySystem
var clock: TimeOfDay
var weather: Weather
var terrain: TerrainData
var car: Node3D


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			args[s] = "1"


func arg(name: String, default := "") -> String:
	return args.get(name, default)


func vec3_arg(name: String, default: Vector3) -> Vector3:
	if not args.has(name):
		return default
	var p := String(args[name]).split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

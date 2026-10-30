extends Node
## Sweeps the procedural car voices, then quits.

const SWEEP_SEC := 6.0
const CarScript := preload("res://scripts/audio/car_audio.gd")
const AmbScript := preload("res://scripts/audio/ambient_audio.gd")

var _car: Node
var _elapsed := 0.0


func _ready() -> void:
	var car: Node = CarScript.new()
	car.name = "CarAudio"
	car.set("auto_from_game", false)
	car.set("throttle", 0.65)
	car.set("slip", 0.22)
	car.set("rain", 0.4)
	car.set("wet", 0.55)
	add_child(car)
	_car = car

	var ambient: Node = AmbScript.new()
	ambient.name = "AmbientAudio"
	add_child(ambient)

	var camera := Camera3D.new()
	camera.name = "Listener"
	camera.current = true
	add_child(camera)


func _process(delta: float) -> void:
	_elapsed += delta
	var k := clampf(_elapsed / SWEEP_SEC, 0.0, 1.0)
	_car.set("rpm", lerpf(800.0, 6500.0, k))
	_car.set("speed_kmh", lerpf(0.0, 160.0, k))
	if _elapsed >= SWEEP_SEC:
		get_tree().quit()

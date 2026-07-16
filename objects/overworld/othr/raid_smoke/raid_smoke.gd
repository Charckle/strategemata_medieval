extends Node2D

## Rising dark squares marking raid / raze smoke.
## `intensity` scales particle count and opacity (1.0 = full / raze, ~0.35 = light raid).

const BASE_PARTICLE_COUNT := 16
const RADIUS := 30.0

## 0.0–1.0; set before add_child or via set_intensity after.
var intensity: float = 1.0

var _particles: Array = []


func _ready() -> void:
	_rebuild_particles()
	set_process(true)
	queue_redraw()


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	_rebuild_particles()
	queue_redraw()


func _rebuild_particles() -> void:
	_particles.clear()
	var count := maxi(2, int(round(float(BASE_PARTICLE_COUNT) * intensity)))
	for i in count:
		_particles.append(_spawn_particle())


func _spawn_particle() -> Dictionary:
	var alpha_scale := clampf(intensity, 0.15, 1.0)
	return {
		"pos": Vector2(randf_range(-RADIUS, RADIUS), randf_range(-6.0, 14.0)),
		"size": randf_range(2.5, 5.0 + 2.0 * intensity),
		"speed": randf_range(12.0, 20.0 + 12.0 * intensity),
		"drift": randf_range(-12.0, 12.0),
		"life": randf_range(0.0, 1.5),
		"max_life": randf_range(1.1, 2.5),
		"alpha": randf_range(0.25, 0.75) * alpha_scale,
	}


func _process(delta: float) -> void:
	for p in _particles:
		p["life"] = float(p["life"]) + delta
		p["pos"].y -= float(p["speed"]) * delta
		p["pos"].x += float(p["drift"]) * delta * 0.12
		if float(p["life"]) >= float(p["max_life"]):
			var fresh := _spawn_particle()
			p["pos"] = fresh["pos"]
			p["size"] = fresh["size"]
			p["speed"] = fresh["speed"]
			p["drift"] = fresh["drift"]
			p["life"] = 0.0
			p["max_life"] = fresh["max_life"]
			p["alpha"] = fresh["alpha"]
	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var t: float = float(p["life"]) / float(p["max_life"])
		var a: float = float(p["alpha"]) * clampf(1.0 - t, 0.0, 1.0)
		var s: float = float(p["size"])
		var r := Rect2(p["pos"] - Vector2(s * 0.5, s * 0.5), Vector2(s, s))
		draw_rect(r, Color(0.1, 0.1, 0.1, a), true)

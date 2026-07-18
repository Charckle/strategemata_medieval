extends Node2D

## Red pixel squares dripping down from a starving army / garrison.

const BASE_PARTICLE_COUNT := 12
const RADIUS := 22.0

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
	var alpha_scale := clampf(intensity, 0.2, 1.0)
	return {
		"pos": Vector2(randf_range(-RADIUS, RADIUS), randf_range(-4.0, 4.0)),
		"size": randf_range(2.0, 3.5 + intensity),
		# Slow drip; short life so they don't travel far.
		"speed": randf_range(4.0, 9.0),
		"drift": randf_range(-4.0, 4.0),
		"life": randf_range(0.0, 0.6),
		"max_life": randf_range(0.55, 1.0),
		"alpha": randf_range(0.35, 0.8) * alpha_scale,
	}


func _process(delta: float) -> void:
	for p in _particles:
		p["life"] = float(p["life"]) + delta
		p["pos"].y += float(p["speed"]) * delta
		p["pos"].x += float(p["drift"]) * delta * 0.08
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
		var col := Color(0.55 + 0.25 * (1.0 - t), 0.05, 0.05, a)
		draw_rect(r, col, true)

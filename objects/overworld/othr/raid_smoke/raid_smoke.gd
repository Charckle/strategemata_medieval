extends Node2D

## Rising dark squares marking raid / raze smoke.
## `intensity` scales particle count and opacity (1.0 = full / raze, ~0.35 = light raid).
## `tall_plume` adds a single faster center stream that rises above the cloud (raze).

const BASE_PARTICLE_COUNT := 16
const RADIUS := 30.0

## 0.0–1.0; set before add_child or via set_intensity after.
var intensity: float = 1.0
## Extra tall center stream (raze only).
var tall_plume: bool = false

var _particles: Array = []
var _plume: Dictionary = {}


func _ready() -> void:
	_rebuild_particles()
	set_process(true)
	queue_redraw()


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	_rebuild_particles()
	queue_redraw()


func set_tall_plume(enabled: bool) -> void:
	tall_plume = enabled
	if tall_plume:
		_plume = _spawn_plume()
	else:
		_plume.clear()
	queue_redraw()


func _rebuild_particles() -> void:
	_particles.clear()
	var count := maxi(2, int(round(float(BASE_PARTICLE_COUNT) * intensity)))
	for i in count:
		_particles.append(_spawn_particle())
	if tall_plume:
		_plume = _spawn_plume()
	else:
		_plume.clear()


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


func _spawn_plume() -> Dictionary:
	return {
		"pos": Vector2(randf_range(-3.0, 3.0), randf_range(0.0, 8.0)),
		"size": randf_range(4.0, 6.5),
		"speed": randf_range(38.0, 52.0),
		"drift": randf_range(-4.0, 4.0),
		"life": 0.0,
		"max_life": randf_range(2.4, 3.4),
		"alpha": randf_range(0.55, 0.85),
	}


func _process(delta: float) -> void:
	for p in _particles:
		_advance_particle(p, delta, false)
	if tall_plume and not _plume.is_empty():
		_advance_particle(_plume, delta, true)
	queue_redraw()


func _advance_particle(p: Dictionary, delta: float, is_plume: bool) -> void:
	p["life"] = float(p["life"]) + delta
	p["pos"].y -= float(p["speed"]) * delta
	p["pos"].x += float(p["drift"]) * delta * (0.08 if is_plume else 0.12)
	if float(p["life"]) >= float(p["max_life"]):
		var fresh := _spawn_plume() if is_plume else _spawn_particle()
		p["pos"] = fresh["pos"]
		p["size"] = fresh["size"]
		p["speed"] = fresh["speed"]
		p["drift"] = fresh["drift"]
		p["life"] = 0.0
		p["max_life"] = fresh["max_life"]
		p["alpha"] = fresh["alpha"]


func _draw() -> void:
	for p in _particles:
		_draw_particle(p)
	if tall_plume and not _plume.is_empty():
		_draw_particle(_plume)


func _draw_particle(p: Dictionary) -> void:
	var t: float = float(p["life"]) / float(p["max_life"])
	var a: float = float(p["alpha"]) * clampf(1.0 - t, 0.0, 1.0)
	var s: float = float(p["size"])
	var r := Rect2(p["pos"] - Vector2(s * 0.5, s * 0.5), Vector2(s, s))
	draw_rect(r, Color(0.1, 0.1, 0.1, a), true)

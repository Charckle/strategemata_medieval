extends Node2D

## Seasonal easter-egg balloon. Drift path is deterministic from a shared seed.

const INTERIOR_WAYPOINTS := 5
const ARRIVE_DIST := 12.0

## Tunable in play — keep slow for now.
@export var speed: float = 28.0
@export var turn_rate: float = 1.2  # radians / second

@onready var _shadow: Sprite2D = $shadow

var _waypoints: Array[Vector2] = []
var _wp_index: int = 0
var _map_rect: Rect2 = Rect2()
var _edge_margin: float = 100.0
var _heading: float = 0.0


func _ready() -> void:
	_shadow.texture = _make_ellipse_shadow(24, 10, 0.4)


func setup(map_rect: Rect2, edge_margin: float, path_seed: int) -> void:
	_map_rect = map_rect
	_edge_margin = edge_margin
	z_index = 30
	z_as_relative = false
	rotation = 0.0

	var rng := RandomNumberGenerator.new()
	rng.seed = path_seed as int

	_waypoints.clear()
	_waypoints.append(_random_edge_point(rng))
	for _i in range(INTERIOR_WAYPOINTS):
		_waypoints.append(_random_interior_point(rng))
	_waypoints.append(_random_edge_point(rng))

	global_position = _waypoints[0]
	_wp_index = 1
	if _waypoints.size() > 1:
		_heading = (_waypoints[1] - _waypoints[0]).angle()


func _make_ellipse_shadow(width: int, height: int, strength: float) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var cx := width * 0.5
	var cy := height * 0.5
	var rx := maxf(cx - 0.5, 1.0)
	var ry := maxf(cy - 0.5, 1.0)
	var fill := Color(0, 0, 0, strength)
	for y in range(height):
		for x in range(width):
			var nx := (x + 0.5 - cx) / rx
			var ny := (y + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _wp_index >= _waypoints.size():
		queue_free()
		return

	var target: Vector2 = _waypoints[_wp_index]
	var to_target := target - global_position
	var dist := to_target.length()
	if dist <= ARRIVE_DIST:
		_wp_index += 1
		if _wp_index >= _waypoints.size():
			queue_free()
		return

	var desired := to_target.angle()
	var diff := wrapf(desired - _heading, -PI, PI)
	var max_step := turn_rate * delta
	_heading = wrapf(_heading + clampf(diff, -max_step, max_step), -PI, PI)
	global_position += Vector2.from_angle(_heading) * speed * delta
	rotation = 0.0


func _random_interior_point(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(_map_rect.position.x, _map_rect.end.x),
		rng.randf_range(_map_rect.position.y, _map_rect.end.y),
	)


func _random_edge_point(rng: RandomNumberGenerator) -> Vector2:
	var r := _map_rect.grow(_edge_margin)
	var edge := rng.randi() % 4
	match edge:
		0:  # top
			return Vector2(rng.randf_range(r.position.x, r.end.x), r.position.y)
		1:  # bottom
			return Vector2(rng.randf_range(r.position.x, r.end.x), r.end.y)
		2:  # left
			return Vector2(r.position.x, rng.randf_range(r.position.y, r.end.y))
		_:  # right
			return Vector2(r.end.x, rng.randf_range(r.position.y, r.end.y))

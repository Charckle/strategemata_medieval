extends Node2D

## Draws the tiles a selected army can reach this turn, plus a marker on the
## tile where a previewed move would stop (where movement points run out).

var pathfinding: Node = null

var reachable_cells: Dictionary = {}
var has_stop := false
var stop_cell: Vector2i = Vector2i.ZERO

@export var reachable_color := Color(0.2, 0.8, 0.3, 0.25)
@export var stop_color := Color(0.95, 0.85, 0.2, 0.9)
@export var reachable_radius := 10.0
@export var stop_radius := 7.0


func set_reachable(cells: Dictionary) -> void:
	reachable_cells = cells
	queue_redraw()


func set_stop_cell(cell: Vector2i) -> void:
	has_stop = true
	stop_cell = cell
	queue_redraw()


func clear_stop() -> void:
	has_stop = false
	queue_redraw()


func clear_all() -> void:
	reachable_cells = {}
	has_stop = false
	queue_redraw()


func _draw() -> void:
	if pathfinding == null:
		return
	var map_layer = pathfinding.map_layer
	if map_layer == null:
		return
	for cell_variant in reachable_cells.keys():
		var cell: Vector2i = cell_variant
		var world: Vector2 = map_layer.global_position + map_layer.map_to_local(cell)
		draw_circle(to_local(world), reachable_radius, reachable_color)
	if has_stop:
		var stop_world: Vector2 = map_layer.global_position + map_layer.map_to_local(stop_cell)
		draw_circle(to_local(stop_world), stop_radius, stop_color)

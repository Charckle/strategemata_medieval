extends Node2D

## Draws the tiles a selected army can reach this turn, plus markers for the
## tile where a previewed move would stop and (optionally) the interaction
## target (army / fleet / building / …) beyond that stop.

var pathfinding: Node = null

var reachable_cells: Dictionary = {}
var has_stop := false
var stop_cell: Vector2i = Vector2i.ZERO
var has_interact := false
var interact_cell: Vector2i = Vector2i.ZERO
var interact_reachable := false

@export var reachable_color := Color(0.2, 0.8, 0.3, 0.25)
@export var stop_color := Color(0.95, 0.85, 0.2, 0.9)
@export var interact_color := Color(0.85, 0.35, 0.05, 0.95)
@export var interact_unreachable_color := Color(0.55, 0.55, 0.55, 0.9)
@export var reachable_radius := 10.0
@export var stop_radius := 7.0
@export var interact_radius := 7.0


func set_reachable(cells: Dictionary) -> void:
	reachable_cells = cells
	queue_redraw()


func set_stop_cell(cell: Vector2i) -> void:
	has_stop = true
	stop_cell = cell
	queue_redraw()


func set_interact_cell(cell: Vector2i, can_interact: bool = true) -> void:
	has_interact = true
	interact_cell = cell
	interact_reachable = can_interact
	queue_redraw()


func clear_stop() -> void:
	has_stop = false
	has_interact = false
	interact_reachable = false
	queue_redraw()


func clear_all() -> void:
	reachable_cells = {}
	has_stop = false
	has_interact = false
	interact_reachable = false
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
	if has_interact:
		var interact_world: Vector2 = map_layer.global_position + map_layer.map_to_local(interact_cell)
		var color := interact_color if interact_reachable else interact_unreachable_color
		draw_circle(to_local(interact_world), interact_radius, color)

extends Node2D

@export var enabled := true:
	set(value):
		enabled = value
		visible = value
		queue_redraw()

@export var circle_radius := 8.0
@export var circle_color := Color(0.653, 0.154, 0.29, 0.5)

@onready var _base_map: Node2D = get_parent()
@onready var _tilemap_root: Node = _base_map.get_node_or_null("tilemap")
@onready var _pathfinding: Node = _base_map.get_node_or_null("pathfinding")


func _ready() -> void:
	visible = enabled
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	if _pathfinding == null or not _pathfinding.has_method("get_walkable_cells"):
		return
	var map_layer := _get_map_layer()
	if map_layer == null:
		return
	var walkable_cells: Dictionary = _pathfinding.get_walkable_cells()
	for cell_variant in walkable_cells.keys():
		var cell: Vector2i = cell_variant
		var world := map_layer.global_position + map_layer.map_to_local(cell)
		var local_pos := to_local(world)
		draw_circle(local_pos, circle_radius, circle_color)


func _get_map_layer() -> TileMapLayer:
	if _tilemap_root == null:
		return null
	for child in _tilemap_root.get_children():
		if child is TileMapLayer and child.tile_set != null:
			return child as TileMapLayer
	return null

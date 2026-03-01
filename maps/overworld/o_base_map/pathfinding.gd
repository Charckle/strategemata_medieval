extends Node

@onready var base_map = get_parent()
@onready var armies = base_map.get_node("armies")
@onready var path_line = base_map.get_node("PathLine")
@onready var tilemap = base_map.get_node("tilemap")

var astar_graph: AStar2D
var walkable_cells: Dictionary = {}
var cell_to_point_id: Dictionary = {}
var point_id_to_cell: Dictionary = {}
var map_layer: TileMapLayer
var selected_army: Node2D = null
var path_target_cell: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)  # invalid sentinel
var current_path: Array[Vector2i] = []

const ARMY_CENTER_OFFSET := Vector2(32, 16)
const MOVE_DIRS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


func initialize() -> void:
	_setup_astar_graph()


# to ni OK. čekira samo en layer če je walkable
func _get_map_layer() -> TileMapLayer:
	for child in tilemap.get_children():
		if child is TileMapLayer and child.tile_set != null:
			return child as TileMapLayer
	return null


func _setup_astar_graph() -> void:
	# to ni ok, čekiramo samo en layer za walkable!!!!
	map_layer = _get_map_layer()
	
	astar_graph = AStar2D.new()

	# set walkable tiles
	for cell in map_layer.get_used_cells():
		var tile_data = map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		
		var is_walkable = tile_data.get_custom_data("walkable")
		
		if is_walkable:
			walkable_cells[cell] = true

	var next_id := 0
	for cell_variant in walkable_cells.keys():
		var cell: Vector2i = cell_variant
		cell_to_point_id[cell] = next_id
		point_id_to_cell[next_id] = cell
		astar_graph.add_point(next_id, map_layer.map_to_local(cell))
		next_id += 1
	
	for cell_variant in walkable_cells.keys():
		var cell: Vector2i = cell_variant
		var from_id: int = cell_to_point_id[cell]
		for dir_variant in MOVE_DIRS:
			var dir: Vector2i = dir_variant
			var to_cell: Vector2i = cell + dir
			if not walkable_cells.has(to_cell):
				continue
			var to_id: int = cell_to_point_id[to_cell]
			if not astar_graph.are_points_connected(from_id, to_id):
				astar_graph.connect_points(from_id, to_id, true)



func _is_walkable_cell(cell: Vector2i) -> bool:
	return walkable_cells.has(cell)


func _find_path_cells(from_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	if astar_graph == null:
		return []
	if not _is_walkable_cell(from_cell) or not _is_walkable_cell(target_cell):
		return []
	var from_id: int = cell_to_point_id[from_cell]
	var to_id: int = cell_to_point_id[target_cell]
	var id_path: PackedInt64Array = astar_graph.get_id_path(from_id, to_id)
	var cell_path: Array[Vector2i] = []
	for id in id_path:
		cell_path.append(point_id_to_cell[id])
	return cell_path


func get_cell_at_mouse() -> Vector2i:
	if map_layer == null:
		return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	var global_mouse = base_map.get_global_mouse_position()
	var local := map_layer.to_local(global_mouse)
	return map_layer.local_to_map(local)


func get_army_cell(army: Node2D) -> Vector2i:
	if map_layer == null:
		return Vector2i(0, 0)
	var local := map_layer.to_local(_get_army_center_global(army))
	return map_layer.local_to_map(local)


func _get_cell_center_global(cell: Vector2i) -> Vector2:
	if map_layer == null:
		return Vector2.ZERO
	var local := map_layer.map_to_local(cell)
	return map_layer.global_position + local


func _get_army_center_global(army: Node2D) -> Vector2:
	return army.global_position + ARMY_CENTER_OFFSET


func select_army(army: Node2D) -> void:
	selected_army = army
	clear_path_preview()
	army.set_selected(true)


func clear_path_preview() -> void:
	path_line.clear_points()
	current_path.clear()
	path_target_cell = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_army != null:
				selected_army.set_selected(false)
			selected_army = null
			clear_path_preview()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and selected_army != null:
			var cell := get_cell_at_mouse()
			if not _is_walkable_cell(cell):
				return
			if cell == path_target_cell and current_path.size() > 0:
				execute_move()
			else:
				_try_show_path(cell)


func _try_show_path(target_cell: Vector2i) -> void:
	var from_cell := get_army_cell(selected_army)
	var path_ids: Array[Vector2i] = _find_path_cells(from_cell, target_cell)
	
	print("Army path from %s to %s: %s" % [from_cell, target_cell, path_ids])
	current_path.clear()
	
	for id in path_ids:
		current_path.append(id)
	if current_path.is_empty():
		clear_path_preview()
		return
	path_target_cell = target_cell
	path_line.clear_points()
	
	for cell in current_path:
		path_line.add_point(base_map.to_local(_get_cell_center_global(cell)))


func execute_move() -> void:
	if selected_army == null or current_path.is_empty():
		clear_path_preview()
		return
	var end_cell: Vector2i = current_path[current_path.size() - 1]
	var army = selected_army
	army.global_position = _get_cell_center_global(end_cell) - ARMY_CENTER_OFFSET
	army.set_selected(false)
	clear_path_preview()
	selected_army = null

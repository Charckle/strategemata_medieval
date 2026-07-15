extends Node

@onready var base_map = get_parent()
@onready var armies = base_map.get_node("armies")
@onready var path_line = base_map.get_node("PathLine")
@onready var tilemap = base_map.get_node("tilemap")

var astar_graph: AStar2D
var walkable_cells: Dictionary = {}
var cell_to_point_id: Dictionary = {}
var point_id_to_cell: Dictionary = {}
var blocked_cell_to_object: Dictionary = {}   # Vector2i -> Node
var object_to_footprint: Dictionary = {}      # Node -> Array[Vector2i]
var map_layer: TileMapLayer
var selected_army: Node2D = null
var current_path: Array[Vector2i] = []
# Cell -> army Node currently standing on it (rebuilt after every move).
var occupancy: Dictionary = {}

# Preview visuals (created at runtime).
var rest_line: Line2D = null            # out-of-range portion of the previewed path
var reachable_overlay: Node2D = null    # reachable tiles + stop marker

const REACHABLE_OVERLAY_SCRIPT := preload("res://maps/overworld/o_base_map/reachable_overlay.gd")
const PATH_REACHABLE_COLOR := Color(0.2, 0.85, 0.35, 0.9)
const PATH_REST_COLOR := Color(0.6, 0.6, 0.6, 0.6)

const ARMY_CENTER_OFFSET := Vector2(32, 16)
# Isometric cell space: the only true neighbors are the 4 cardinal cell
# directions (tiles sharing a diamond edge). A (1,1)-style step touches only at
# a vertex and is NOT adjacent, so movement is strictly edge-based.
const EDGE_DIRS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func initialize() -> void:
	_setup_astar_graph()
	_setup_preview_nodes()
	rebuild_occupancy()


func _setup_preview_nodes() -> void:
	path_line.default_color = PATH_REACHABLE_COLOR

	rest_line = Line2D.new()
	rest_line.name = "PathLineRest"
	rest_line.width = path_line.width
	rest_line.default_color = PATH_REST_COLOR
	base_map.add_child(rest_line)

	reachable_overlay = Node2D.new()
	reachable_overlay.name = "ReachableOverlay"
	reachable_overlay.set_script(REACHABLE_OVERLAY_SCRIPT)
	base_map.add_child(reachable_overlay)
	reachable_overlay.pathfinding = self


func rebuild_occupancy() -> void:
	occupancy.clear()
	for army in armies.get_children():
		occupancy[get_army_cell(army)] = army


func cell_center_global(cell: Vector2i) -> Vector2:
	return _get_cell_center_global(cell)


func place_army_at_cell(army: Node2D, cell: Vector2i) -> void:
	army.global_position = _get_cell_center_global(cell) - ARMY_CENTER_OFFSET


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

	# remove cells covered by objects (they return list of global tile-center positions)
	blocked_cell_to_object.clear()
	object_to_footprint.clear()
	var blocked_objects: Array = base_map.get_objects_with_pathfinding_blocked_tiles()
	for node in blocked_objects:
		var positions: Array = node.get_pathfinding_blocked_tile_centers()
		var footprint: Array[Vector2i] = []
		for pos in positions:
			var cell: Vector2i = map_layer.local_to_map(map_layer.to_local(pos))
			walkable_cells.erase(cell)
			blocked_cell_to_object[cell] = node
			footprint.append(cell)
		object_to_footprint[node] = footprint

	var overlay = base_map.get_node_or_null("WalkableOverlay")
	if overlay and overlay.has_method("refresh"):
		overlay.refresh()

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
		# Only edge-adjacent (cardinal) tiles are neighbors.
		for dir_variant in EDGE_DIRS:
			var dir: Vector2i = dir_variant
			var to_cell: Vector2i = cell + dir
			if not walkable_cells.has(to_cell):
				continue
			var to_id: int = cell_to_point_id[to_cell]
			if not astar_graph.are_points_connected(from_id, to_id):
				astar_graph.connect_points(from_id, to_id, true)



func get_walkable_cells() -> Dictionary:
	return walkable_cells


func _is_walkable_cell(cell: Vector2i) -> bool:
	return walkable_cells.has(cell)


# walkable tiles that ring a building's footprint (its "approach"/entrance tiles)
# Only edge-adjacent tiles count as "next to" the building.
func get_approach_cells(node: Node) -> Array[Vector2i]:
	var footprint: Array = object_to_footprint.get(node, [])
	var result: Array[Vector2i] = []
	for cell in footprint:
		for dir in EDGE_DIRS:
			var n: Vector2i = cell + dir
			if walkable_cells.has(n) and not (n in footprint) and not (n in result):
				result.append(n)
	return result


# Cells reachable from a start cell within max_steps edge-moves (BFS).
# Note: does not treat armies as blockers yet (interaction logic pending).
func get_reachable_cells(from_cell: Vector2i, max_steps: int) -> Dictionary:
	var result: Dictionary = {from_cell: 0}
	var frontier: Array[Vector2i] = [from_cell]
	var dist := 0
	while not frontier.is_empty() and dist < max_steps:
		dist += 1
		var next_frontier: Array[Vector2i] = []
		for cell in frontier:
			for dir in EDGE_DIRS:
				var n: Vector2i = cell + dir
				if walkable_cells.has(n) and not result.has(n):
					result[n] = dist
					next_frontier.append(n)
		frontier = next_frontier
	return result


# Walkable, unoccupied tiles edge-adjacent to a single cell (its "approach").
func _approach_cells_of_cell(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in EDGE_DIRS:
		var n: Vector2i = cell + dir
		if walkable_cells.has(n) and not occupancy.has(n) and not (n in result):
			result.append(n)
	return result


func _best_path_to_cells(from_cell: Vector2i, target_cells: Array[Vector2i]) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = []
	for target_cell in target_cells:
		var path_cells: Array[Vector2i] = _find_path_cells(from_cell, target_cell)
		if path_cells.is_empty():
			continue
		if best_path.is_empty() or path_cells.size() < best_path.size():
			best_path = path_cells
	return best_path


# Returns true if a path exists between two cells in the AStar graph.
# Safely returns false when either cell is not in the graph at all.
func has_path_from(from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not cell_to_point_id.has(from_cell) or not cell_to_point_id.has(target_cell):
		return false
	if from_cell == target_cell:
		return true
	var from_id: int = cell_to_point_id[from_cell]
	var to_id: int = cell_to_point_id[target_cell]
	return astar_graph.get_id_path(from_id, to_id).size() > 0


func _find_path_cells(from_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	# check if its a building
	# check if its an army
	
	if not _is_walkable_cell(target_cell):
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
	if selected_army != null and selected_army != army:
		selected_army.set_selected(false)
	selected_army = army
	clear_path_preview()
	army.set_selected(true)
	_update_reachable_overlay()
	_update_hover_preview()


func deselect_army() -> void:
	if selected_army != null:
		selected_army.set_selected(false)
	selected_army = null
	clear_path_preview()
	if reachable_overlay != null:
		reachable_overlay.clear_all()


func clear_path_preview() -> void:
	path_line.clear_points()
	if rest_line != null:
		rest_line.clear_points()
	if reachable_overlay != null:
		reachable_overlay.clear_stop()
	current_path.clear()


func _update_reachable_overlay() -> void:
	if reachable_overlay == null or selected_army == null:
		return
	var from_cell := get_army_cell(selected_army)
	reachable_overlay.set_reachable(get_reachable_cells(from_cell, selected_army.movement_left))


func _unhandled_input(event: InputEvent) -> void:
	if selected_army == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			deselect_army()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _confirm_move():
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_hover_preview()


# Resolve the path to whatever is under the cursor: a free tile, a building's
# approach tile, or an occupied (army) tile's approach tile.
func _resolve_target_path(from_cell: Vector2i, cell: Vector2i) -> Array[Vector2i]:
	if _is_walkable_cell(cell) and not occupancy.has(cell):
		return _find_path_cells(from_cell, cell)
	if occupancy.has(cell) and occupancy[cell] != selected_army:
		return _best_path_to_cells(from_cell, _approach_cells_of_cell(cell))
	var building = blocked_cell_to_object.get(cell, null)
	if building != null:
		return _best_path_to_cells(from_cell, get_approach_cells(building))
	return []


func _update_hover_preview() -> void:
	if selected_army == null:
		return
	var from_cell := get_army_cell(selected_army)
	var cell := get_cell_at_mouse()
	var path_cells := _resolve_target_path(from_cell, cell)
	_render_path_preview(path_cells)


func _render_path_preview(path_cells: Array[Vector2i]) -> void:
	clear_path_preview()
	if path_cells.is_empty():
		return
	current_path = path_cells
	var reachable_steps: int = min(selected_army.movement_left, path_cells.size() - 1)

	for i in range(0, reachable_steps + 1):
		path_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))
	# Out-of-range remainder, dimmed (shows where the army would continue later).
	if reachable_steps < path_cells.size() - 1:
		for i in range(reachable_steps, path_cells.size()):
			rest_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))

	if reachable_overlay != null:
		reachable_overlay.set_stop_cell(path_cells[reachable_steps])


func _confirm_move() -> bool:
	if selected_army == null or current_path.size() < 2:
		return false

	# If the cursor is hovering a building cell, treat the click as a building
	# interaction rather than a move. The building's Area2D input_event fires
	# before _unhandled_input, so normally it would beat us here — but if the
	# building has no Area2D covering the hovered cell we fall through. Either
	# way, when the final stop of the current path lands on a building's
	# approach, we forward to on_building_clicked on the building itself.
	var mouse_cell := get_cell_at_mouse()
	var building_under_cursor = blocked_cell_to_object.get(mouse_cell, null)
	if building_under_cursor != null and building_under_cursor.has_method("get_garrison_capacity"):
		# Let on_building_clicked handle it (checks movement, opens garrison menu).
		var consumed = base_map.on_building_clicked(building_under_cursor)
		if consumed:
			return true

	var reachable_steps: int = min(selected_army.movement_left, current_path.size() - 1)
	if reachable_steps <= 0:
		return false  # no movement points left this turn
	var end_cell: Vector2i = current_path[reachable_steps]
	var army_name := String(selected_army.name)
	deselect_army()
	base_map.request_army_move.rpc_id(1, army_name, end_cell.x, end_cell.y, reachable_steps)
	# Army teleports under the cursor on call_local; suppress the follow-up
	# Area2D click on this same frame so the Army Menu does not reopen.
	base_map.suppress_army_click_this_frame()
	return true


# Returns the nearest walkable, unoccupied cell adjacent to `from_cell`, or
# Vector2i(0x7FFFFFFF, 0x7FFFFFFF) if none exists.
func get_free_adjacent_cell(from_cell: Vector2i) -> Vector2i:
	for dir in EDGE_DIRS:
		var n: Vector2i = from_cell + dir
		if walkable_cells.has(n) and not occupancy.has(n):
			return n
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


# Placeholder for future army-vs-army interaction (attack / merge / trade / ...).
# Wired for later: occupancy + adjacency pathing already resolve to the target.
func open_army_interaction(_mover: Node2D, _target: Node2D) -> void:
	pass

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
var roads_layer: TileMapLayer
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
# MP cost to enter a cell (charged on the destination tile).
const COST_ROAD := 1
const COST_OFF_ROAD := 2
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


# Walkable terrain layer (skips decorative layers like roads).
func _get_map_layer() -> TileMapLayer:
	for child in tilemap.get_children():
		if child is TileMapLayer and child.tile_set != null and child.name != "roads":
			return child as TileMapLayer
	return null


func _get_roads_layer() -> TileMapLayer:
	var layer = tilemap.get_node_or_null("roads")
	if layer is TileMapLayer:
		return layer as TileMapLayer
	return null


func is_road_cell(cell: Vector2i) -> bool:
	if roads_layer == null:
		return false
	var tile_data := roads_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return bool(tile_data.get_custom_data("road"))


## MP cost to enter `cell` (start cell is never charged).
func enter_cost(cell: Vector2i) -> int:
	return COST_ROAD if is_road_cell(cell) else COST_OFF_ROAD


## Sum of enter-costs along a path (index 0 is free; each later cell is charged).
func path_mp_cost(path_cells: Array[Vector2i]) -> int:
	var total := 0
	for i in range(1, path_cells.size()):
		total += enter_cost(path_cells[i])
	return total


## Farthest path index affordable with `mp` movement points.
func _farthest_affordable_index(path_cells: Array[Vector2i], mp: int) -> int:
	var spent := 0
	var best := 0
	for i in range(1, path_cells.size()):
		var step_cost := enter_cost(path_cells[i])
		if spent + step_cost > mp:
			break
		spent += step_cost
		best = i
	return best


func _setup_astar_graph() -> void:
	map_layer = _get_map_layer()
	roads_layer = _get_roads_layer()

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


# Cells reachable from a start cell within max_mp movement points (Dijkstra).
# Values are cumulative MP cost. Other armies block entry — path to approach.
func get_reachable_cells(from_cell: Vector2i, max_mp: int) -> Dictionary:
	var result: Dictionary = {from_cell: 0}
	# Entries are [cost, cell]; expand cheapest first.
	var frontier: Array = [[0, from_cell]]
	while not frontier.is_empty():
		var best_i := 0
		var best_cost: int = frontier[0][0]
		for i in range(1, frontier.size()):
			if int(frontier[i][0]) < best_cost:
				best_cost = int(frontier[i][0])
				best_i = i
		var item: Array = frontier.pop_at(best_i)
		var cost: int = int(item[0])
		var cell: Vector2i = item[1]
		if cost > int(result.get(cell, 0x7FFFFFFF)):
			continue
		for dir in EDGE_DIRS:
			var n: Vector2i = cell + dir
			if not walkable_cells.has(n):
				continue
			# Occupied by another army: cannot enter.
			if occupancy.has(n) and n != from_cell:
				continue
			var next_cost: int = cost + enter_cost(n)
			if next_cost > max_mp:
				continue
			if result.has(n) and int(result[n]) <= next_cost:
				continue
			result[n] = next_cost
			frontier.append([next_cost, n])
	return result


# Walkable, unoccupied tiles edge-adjacent to a single cell (its "approach").
# `ignore_army` (if set) may stand on an approach tile — its cell still counts.
func _approach_cells_of_cell(cell: Vector2i, ignore_army: Node2D = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in EDGE_DIRS:
		var n: Vector2i = cell + dir
		if not walkable_cells.has(n) or n in result:
			continue
		if occupancy.has(n) and occupancy[n] != ignore_army:
			continue
		result.append(n)
	return result


func _best_path_to_cells(from_cell: Vector2i, target_cells: Array[Vector2i]) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = []
	var best_cost := 0x7FFFFFFF
	for target_cell in target_cells:
		var path_cells: Array[Vector2i] = _find_path_cells(from_cell, target_cell)
		if path_cells.is_empty():
			continue
		var cost := path_mp_cost(path_cells)
		if best_path.is_empty() or cost < best_cost:
			best_path = path_cells
			best_cost = cost
	return best_path


# True when two cells share an edge (cardinal neighbors in iso cell space).
func _cells_edge_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d: Vector2i = a - b
	return (absi(d.x) + absi(d.y)) == 1


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


# Path that never steps onto another army's cell. Dijkstra over enter-costs so
# roads are preferred; occupancy is respected (AStar is static).
func _find_path_cells(from_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	if not _is_walkable_cell(from_cell) or not _is_walkable_cell(target_cell):
		return []
	# Cannot path onto an occupied tile (approach tiles are always free).
	if occupancy.has(target_cell) and target_cell != from_cell:
		return []
	if from_cell == target_cell:
		return [from_cell]

	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = {from_cell: 0}
	var frontier: Array = [[0, from_cell]]
	came_from[from_cell] = from_cell  # sentinel: start maps to itself
	var found := false
	while not frontier.is_empty():
		var best_i := 0
		var best_cost: int = frontier[0][0]
		for i in range(1, frontier.size()):
			if int(frontier[i][0]) < best_cost:
				best_cost = int(frontier[i][0])
				best_i = i
		var item: Array = frontier.pop_at(best_i)
		var cost: int = int(item[0])
		var current: Vector2i = item[1]
		if cost > int(cost_so_far.get(current, 0x7FFFFFFF)):
			continue
		if current == target_cell:
			found = true
			break
		for dir_variant in EDGE_DIRS:
			var dir: Vector2i = dir_variant
			var n: Vector2i = current + dir
			if not walkable_cells.has(n):
				continue
			if occupancy.has(n) and n != from_cell:
				continue
			var next_cost: int = cost + enter_cost(n)
			if cost_so_far.has(n) and int(cost_so_far[n]) <= next_cost:
				continue
			cost_so_far[n] = next_cost
			came_from[n] = current
			frontier.append([next_cost, n])

	if not found:
		return []
	var cell_path: Array[Vector2i] = []
	var c: Vector2i = target_cell
	while true:
		cell_path.push_front(c)
		if c == from_cell:
			break
		c = came_from[c]
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
	if base_map != null and base_map.has_method("is_mouse_over_gui") and base_map.is_mouse_over_gui():
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
	# Hovering the selected army's own tile — stay put.
	if cell == from_cell or occupancy.get(cell) == selected_army:
		return [from_cell]
	if _is_walkable_cell(cell) and not occupancy.has(cell):
		return _find_path_cells(from_cell, cell)
	if occupancy.has(cell) and occupancy[cell] != selected_army:
		return _best_path_to_cells(from_cell, _approach_cells_of_cell(cell, selected_army))
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
	var stop_i: int = _farthest_affordable_index(path_cells, selected_army.movement_left)

	for i in range(0, stop_i + 1):
		path_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))
	# Out-of-range remainder, dimmed (shows where the army would continue later).
	if stop_i < path_cells.size() - 1:
		for i in range(stop_i, path_cells.size()):
			rest_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))

	if reachable_overlay != null:
		reachable_overlay.set_stop_cell(path_cells[stop_i])


func _confirm_move() -> bool:
	if selected_army == null:
		return false

	var mouse_cell := get_cell_at_mouse()
	var army_cell := get_army_cell(selected_army)

	# Same tile as the selected army → open its menu (not a zero-length move).
	if mouse_cell == army_cell or occupancy.get(mouse_cell) == selected_army:
		base_map.open_selected_army_menu(selected_army)
		return true

	# Another army under the cursor: interact if adjacent, otherwise approach.
	if occupancy.has(mouse_cell) and occupancy[mouse_cell] != selected_army:
		var target_army: Node2D = occupancy[mouse_cell]
		if _cells_edge_adjacent(army_cell, mouse_cell):
			open_army_interaction(selected_army, target_army)
			return true
		return confirm_move_to_army(target_army)

	# If the cursor is on a garrisonable building, prefer building interaction.
	# When already adjacent the path is often length < 2, so handle that before
	# the empty-path early-out.
	var building_under_cursor = blocked_cell_to_object.get(mouse_cell, null)
	if building_under_cursor != null and building_under_cursor.has_method("get_garrison_capacity"):
		if army_cell in get_approach_cells(building_under_cursor):
			var consumed = base_map.on_building_clicked(building_under_cursor)
			if consumed:
				return true
		else:
			return confirm_move_to_building(building_under_cursor)

	# Destination resolves to staying put (nearest tile is the army's own cell).
	if current_path.size() == 1 and current_path[0] == army_cell:
		base_map.open_selected_army_menu(selected_army)
		return true
	if current_path.size() < 2:
		return false

	return _execute_move_along_path(null, null)


# Move toward a garrisonable building's approach cells. When the army can reach
# an approach tile with MP left, queues opening the garrison transfer menu.
func confirm_move_to_building(building: Node) -> bool:
	if selected_army == null or building == null:
		return false
	var from_cell := get_army_cell(selected_army)
	var path_cells := _best_path_to_cells(from_cell, get_approach_cells(building))
	if path_cells.size() < 2:
		return false
	_render_path_preview(path_cells)
	return _execute_move_along_path(building, null)


# Move toward another army's approach cells. When arrival leaves MP, queues
# merge/attack interaction (same pattern as garrison).
func confirm_move_to_army(target: Node2D) -> bool:
	if selected_army == null or target == null:
		return false
	var from_cell := get_army_cell(selected_army)
	var target_cell := get_army_cell(target)
	var path_cells := _best_path_to_cells(from_cell, _approach_cells_of_cell(target_cell, selected_army))
	if path_cells.size() < 2:
		return false
	_render_path_preview(path_cells)
	return _execute_move_along_path(null, target)


func _execute_move_along_path(garrison_building: Node, target_army: Node2D) -> bool:
	if selected_army == null or current_path.size() < 2:
		return false
	var stop_i: int = _farthest_affordable_index(current_path, selected_army.movement_left)
	if stop_i <= 0:
		return false  # no movement points left this turn

	# Never end on a tile occupied by another army (path should already avoid
	# this; clamp as a safety net).
	var army := selected_army
	while stop_i > 0:
		var candidate: Vector2i = current_path[stop_i]
		if occupancy.has(candidate) and occupancy[candidate] != army:
			stop_i -= 1
			continue
		break
	if stop_i <= 0:
		return false

	var end_cell: Vector2i = current_path[stop_i]
	var spent_mp := 0
	for i in range(1, stop_i + 1):
		spent_mp += enter_cost(current_path[i])
	var army_name := String(army.name)
	var remaining_mp = army.movement_left - spent_mp

	# Moving onto a building's approach with MP left to spend: open the garrison
	# transfer UI once the move applies (avoids a second click that only shows
	# an empty building info card).
	if garrison_building != null and garrison_building.has_method("get_garrison_capacity") \
			and end_cell in get_approach_cells(garrison_building) and remaining_mp > 0:
		base_map.set_pending_garrison(army_name, army.force_id, garrison_building)

	# Same for army targets: arrive on approach with MP left → merge/attack UI.
	if target_army != null and remaining_mp > 0:
		var target_cell := get_army_cell(target_army)
		if _cells_edge_adjacent(end_cell, target_cell):
			base_map.set_pending_army_interaction(army_name, target_army)

	deselect_army()
	# Pathfinding and the building Area2D can both receive this click. After we
	# deselect, a second pass would open the empty building info card — block it.
	base_map.suppress_building_click_this_frame()
	base_map.request_army_move.rpc_id(1, army_name, end_cell.x, end_cell.y, spent_mp)
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


# True when the two armies share an edge (can interact: merge / attack).
func are_armies_adjacent(a: Node2D, b: Node2D) -> bool:
	return _cells_edge_adjacent(get_army_cell(a), get_army_cell(b))


func open_army_interaction(mover: Node2D, target: Node2D) -> void:
	deselect_army()
	base_map._on_army_interaction(mover, target)


func _alloc_astar_point_id() -> int:
	var best := -1
	for id in point_id_to_cell.keys():
		best = maxi(best, int(id))
	return best + 1


## Remove a currently walkable cell from the graph and mark it blocked by obj.
func block_cell_for_object(cell: Vector2i, obj: Node) -> bool:
	if not walkable_cells.has(cell):
		return false
	if occupancy.has(cell):
		return false
	walkable_cells.erase(cell)
	blocked_cell_to_object[cell] = obj
	var footprint: Array[Vector2i] = []
	if object_to_footprint.has(obj):
		footprint = object_to_footprint[obj]
	if cell not in footprint:
		footprint.append(cell)
	object_to_footprint[obj] = footprint
	var point_id: int = int(cell_to_point_id.get(cell, -1))
	if point_id >= 0 and astar_graph != null and astar_graph.has_point(point_id):
		astar_graph.remove_point(point_id)
	cell_to_point_id.erase(cell)
	point_id_to_cell.erase(point_id)
	var overlay = base_map.get_node_or_null("WalkableOverlay")
	if overlay and overlay.has_method("refresh"):
		overlay.refresh()
	return true


## Restore cells previously blocked by obj (if still walkable terrain and free).
func unblock_object(obj: Node) -> void:
	var footprint: Array = object_to_footprint.get(obj, [])
	object_to_footprint.erase(obj)
	if map_layer == null or astar_graph == null:
		return
	for cell_variant in footprint:
		var cell: Vector2i = cell_variant
		if blocked_cell_to_object.get(cell) == obj:
			blocked_cell_to_object.erase(cell)
		if blocked_cell_to_object.has(cell):
			continue
		var tile_data = map_layer.get_cell_tile_data(cell)
		if tile_data == null or not tile_data.get_custom_data("walkable"):
			continue
		if walkable_cells.has(cell):
			continue
		walkable_cells[cell] = true
		var new_id := _alloc_astar_point_id()
		cell_to_point_id[cell] = new_id
		point_id_to_cell[new_id] = cell
		astar_graph.add_point(new_id, map_layer.map_to_local(cell))
		for dir in EDGE_DIRS:
			var n: Vector2i = cell + dir
			if not walkable_cells.has(n) or not cell_to_point_id.has(n):
				continue
			var to_id: int = int(cell_to_point_id[n])
			if not astar_graph.are_points_connected(new_id, to_id):
				astar_graph.connect_points(new_id, to_id, true)
	var overlay = base_map.get_node_or_null("WalkableOverlay")
	if overlay and overlay.has_method("refresh"):
		overlay.refresh()

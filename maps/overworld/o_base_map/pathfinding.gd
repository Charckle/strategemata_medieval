extends Node

@onready var base_map = get_parent()
@onready var armies = base_map.get_node("armies")
@onready var caravans = base_map.get_node_or_null("caravans")
@onready var fleets = base_map.get_node_or_null("fleets")
@onready var path_line = base_map.get_node("PathLine")
@onready var tilemap = base_map.get_node("tilemap")

var astar_graph: AStar2D
var walkable_cells: Dictionary = {}
## Sea tiles (custom data "sea"); fleets path here only.
var sea_cells: Dictionary = {}
var cell_to_point_id: Dictionary = {}
var point_id_to_cell: Dictionary = {}
var blocked_cell_to_object: Dictionary = {}   # Vector2i -> Node
var object_to_footprint: Dictionary = {}      # Node -> Array[Vector2i]
var map_layer: TileMapLayer
var roads_layer: TileMapLayer
var selected_army: Node2D = null
var current_path: Array[Vector2i] = []
# Cell -> army or caravan Node currently standing on it (rebuilt after every move).
var occupancy: Dictionary = {}
# Cell -> Array of fleet Nodes on that sea tile (stacking allowed).
var fleet_occupancy: Dictionary = {}
const COST_SEA := 1

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
const COST_HILLS := 4
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
	fleet_occupancy.clear()
	for army in armies.get_children():
		occupancy[get_army_cell(army)] = army
	if caravans != null:
		for c in caravans.get_children():
			occupancy[get_army_cell(c)] = c
	if fleets != null:
		for f in fleets.get_children():
			var cell := get_army_cell(f)
			if not fleet_occupancy.has(cell):
				fleet_occupancy[cell] = []
			fleet_occupancy[cell].append(f)
	if base_map != null and base_map.has_method("refresh_fleet_stack_visuals"):
		base_map.refresh_fleet_stack_visuals()


func cell_center_global(cell: Vector2i) -> Vector2:
	return _get_cell_center_global(cell)


func place_army_at_cell(army: Node2D, cell: Vector2i) -> void:
	army.global_position = _get_cell_center_global(cell) - ARMY_CENTER_OFFSET


func place_caravan_at_cell(caravan: Node2D, cell: Vector2i) -> void:
	place_army_at_cell(caravan, cell)


func place_fleet_at_cell(fleet: Node2D, cell: Vector2i) -> void:
	place_army_at_cell(fleet, cell)


func _is_caravan(node: Node) -> bool:
	return node != null and node.has_method("is_caravan") and node.is_caravan()


func _is_fleet(node: Node) -> bool:
	return node != null and node.has_method("is_fleet") and node.is_fleet()


func fleets_at_cell(cell: Vector2i) -> Array:
	return fleet_occupancy.get(cell, [])


func is_sea_cell(cell: Vector2i) -> bool:
	return sea_cells.has(cell)


func _unit_controller(node: Node2D) -> int:
	if node == null:
		return -1
	if node.has_method("get_controller"):
		return int(node.get_controller())
	return int(node.get("player_owner") if node.get("player_owner") != null else -1)


## True when `occupant` blocks `mover` from entering `cell` mid-path.
## Friendly/allied armies may pass through each other. Caravans never share a
## tile with other caravans; armies cannot enter a caravan tile (approach instead).
## Caravans may pass through friendly/allied armies. Fleets ignore land occupancy.
func _occupant_blocks_entry(mover: Node2D, cell: Vector2i) -> bool:
	if _is_fleet(mover):
		return false
	if not occupancy.has(cell):
		return false
	var occ: Node2D = occupancy[cell]
	if occ == mover:
		return false
	var mover_caravan := _is_caravan(mover)
	var occ_caravan := _is_caravan(occ)
	# Caravans never stack with caravans or armies.
	if mover_caravan or occ_caravan:
		if mover_caravan and not occ_caravan:
			# Caravan may path through friendly/allied armies.
			if base_map != null and base_map.has_method("are_friendly_players"):
				return not base_map.are_friendly_players(_unit_controller(mover), _unit_controller(occ))
			return true
		return true
	# Army vs army: block enemies only.
	if base_map != null and base_map.has_method("are_friendly_players"):
		return not base_map.are_friendly_players(_unit_controller(mover), _unit_controller(occ))
	return true


## Never end a move on an occupied tile (even friendly). Fleets may stack.
func _cell_blocked_for_stop(mover: Node2D, cell: Vector2i) -> bool:
	if _is_fleet(mover):
		return false
	if not occupancy.has(cell):
		return false
	return occupancy[cell] != mover


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


func is_hills_cell(cell: Vector2i) -> bool:
	if map_layer == null:
		return false
	var tile_data := map_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return bool(tile_data.get_custom_data("hills"))


## MP cost to enter `cell` (start cell is never charged).
## Road takes precedence over hills. Sea is flat 1 MP for fleets.
func enter_cost(cell: Vector2i, mover: Node2D = null) -> int:
	if mover != null and _is_fleet(mover):
		return COST_SEA
	if is_road_cell(cell):
		return COST_ROAD
	if is_hills_cell(cell):
		return COST_HILLS
	return COST_OFF_ROAD


## Sum of enter-costs along a path (index 0 is free; each later cell is charged).
func path_mp_cost(path_cells: Array[Vector2i], mover: Node2D = null) -> int:
	if mover == null:
		mover = selected_army
	var total := 0
	for i in range(1, path_cells.size()):
		total += enter_cost(path_cells[i], mover)
	return total


## Farthest path index affordable with `mp` movement points.
func _farthest_affordable_index(path_cells: Array[Vector2i], mp: int, mover: Node2D = null) -> int:
	if mover == null:
		mover = selected_army
	var spent := 0
	var best := 0
	for i in range(1, path_cells.size()):
		var step_cost := enter_cost(path_cells[i], mover)
		if spent + step_cost > mp:
			break
		spent += step_cost
		best = i
	return best


func _setup_astar_graph() -> void:
	map_layer = _get_map_layer()
	roads_layer = _get_roads_layer()

	astar_graph = AStar2D.new()
	walkable_cells.clear()
	sea_cells.clear()
	cell_to_point_id.clear()
	point_id_to_cell.clear()

	# set walkable + sea tiles
	for cell in map_layer.get_used_cells():
		var tile_data = map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue

		var is_walkable = tile_data.get_custom_data("walkable")
		if is_walkable:
			walkable_cells[cell] = true
		if bool(tile_data.get_custom_data("sea")):
			sea_cells[cell] = true

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


func _mover_graph_has(cell: Vector2i, mover: Node2D) -> bool:
	if _is_fleet(mover):
		return sea_cells.has(cell)
	return walkable_cells.has(cell)



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
# Friendly/allied armies are pass-through; enemies and caravans block entry.
# Fleets use sea tiles only (flat 1 MP, no fleet blocking).
func get_reachable_cells(from_cell: Vector2i, max_mp: int, mover: Node2D = null) -> Dictionary:
	if mover == null:
		mover = selected_army
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
			if mover != null and not _mover_graph_has(n, mover):
				continue
			elif mover == null and not walkable_cells.has(n):
				continue
			if mover != null and _occupant_blocks_entry(mover, n):
				continue
			elif mover == null and occupancy.has(n) and n != from_cell:
				continue
			var next_cost: int = cost + enter_cost(n, mover)
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


func _best_path_to_cells(from_cell: Vector2i, target_cells: Array[Vector2i], mover: Node2D = null) -> Array[Vector2i]:
	if mover == null:
		mover = selected_army
	var best_path: Array[Vector2i] = []
	var best_cost := 0x7FFFFFFF
	for target_cell in target_cells:
		var path_cells: Array[Vector2i] = _find_path_cells(from_cell, target_cell, mover)
		if path_cells.is_empty():
			continue
		var cost := path_mp_cost(path_cells, mover)
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


# Path preferring roads; enemies/caravans block entry, friends are pass-through.
# Destination must be free to stop on (never end on an occupied tile).
# Fleets path on sea only and may end on tiles with other fleets.
func _find_path_cells(from_cell: Vector2i, target_cell: Vector2i, mover: Node2D = null) -> Array[Vector2i]:
	if mover == null:
		mover = selected_army
	if mover != null:
		if not _mover_graph_has(from_cell, mover) or not _mover_graph_has(target_cell, mover):
			return []
	elif not _is_walkable_cell(from_cell) or not _is_walkable_cell(target_cell):
		return []
	# Cannot end on an occupied tile (fleets exempt).
	if mover != null and _cell_blocked_for_stop(mover, target_cell) and target_cell != from_cell:
		return []
	elif mover == null and occupancy.has(target_cell) and target_cell != from_cell:
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
			if mover != null and not _mover_graph_has(n, mover):
				continue
			elif mover == null and not walkable_cells.has(n):
				continue
			if mover != null and _occupant_blocks_entry(mover, n):
				continue
			elif mover == null and occupancy.has(n) and n != from_cell:
				continue
			var next_cost: int = cost + enter_cost(n, mover)
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


## Best path for a caravan (or any mover) toward any of `target_cells`.
func find_path_for_mover(mover: Node2D, from_cell: Vector2i, target_cells: Array[Vector2i]) -> Array[Vector2i]:
	return _best_path_to_cells(from_cell, target_cells, mover)


func farthest_affordable_index(path_cells: Array[Vector2i], mp: int, mover: Node2D = null) -> int:
	return _farthest_affordable_index(path_cells, mp, mover)


func cell_blocked_for_stop(mover: Node2D, cell: Vector2i) -> bool:
	return _cell_blocked_for_stop(mover, cell)


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
# approach tile, or an occupied (army/caravan/fleet) tile's approach tile.
func _resolve_target_path(from_cell: Vector2i, cell: Vector2i) -> Array[Vector2i]:
	# Hovering the selected army's own tile — stay put.
	if cell == from_cell or occupancy.get(cell) == selected_army:
		return [from_cell]
	if _is_fleet(selected_army):
		if sea_cells.has(cell):
			return _find_path_cells(from_cell, cell, selected_army)
		# Shore tile (empty or occupied): path to an adjacent sea cell for landing.
		if walkable_cells.has(cell):
			return _best_path_to_cells(from_cell, _fleet_approach_sea_cells(cell), selected_army)
		return []
	# Free tile, or friendly pass-through tile we won't stop on as destination
	# unless vacant — only allow direct path onto unoccupied cells.
	if _is_walkable_cell(cell) and not occupancy.has(cell):
		return _find_path_cells(from_cell, cell, selected_army)
	if occupancy.has(cell) and occupancy[cell] != selected_army:
		return _best_path_to_cells(from_cell, _approach_cells_of_cell(cell, selected_army), selected_army)
	# Land army → fleet: approach shore tiles next to the fleet's sea cell.
	if fleet_occupancy.has(cell):
		return _best_path_to_cells(from_cell, _approach_cells_of_cell(cell, selected_army), selected_army)
	var building = blocked_cell_to_object.get(cell, null)
	if building != null:
		return _best_path_to_cells(from_cell, get_approach_cells(building), selected_army)
	return []


## Cell the mover would interact with under the cursor, or null for a plain move.
func _resolve_interact_cell(from_cell: Vector2i, cell: Vector2i):
	if cell == from_cell or occupancy.get(cell) == selected_army:
		return null
	if _is_fleet(selected_army):
		if sea_cells.has(cell) and fleet_occupancy.has(cell):
			return cell
		# Shore landing target (army on it, or empty beach with sea access).
		if walkable_cells.has(cell) and not _fleet_approach_sea_cells(cell).is_empty():
			return cell
		return null
	if occupancy.has(cell) and occupancy[cell] != selected_army:
		return cell
	if fleet_occupancy.has(cell):
		return cell
	if blocked_cell_to_object.has(cell):
		return cell
	return null


## Sea tiles edge-adjacent to a shore cell — where a fleet would stop to land.
func _fleet_approach_sea_cells(shore_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in EDGE_DIRS:
		var n: Vector2i = shore_cell + dir
		if sea_cells.has(n):
			out.append(n)
	return out


func _update_hover_preview() -> void:
	if selected_army == null:
		return
	var from_cell := get_army_cell(selected_army)
	var cell := get_cell_at_mouse()
	var path_cells := _resolve_target_path(from_cell, cell)
	_render_path_preview(path_cells, _resolve_interact_cell(from_cell, cell))


func _render_path_preview(path_cells: Array[Vector2i], interact_cell = null) -> void:
	clear_path_preview()
	if path_cells.is_empty():
		return
	current_path = path_cells
	var stop_i: int = _farthest_affordable_index(path_cells, selected_army.movement_left, selected_army)

	for i in range(0, stop_i + 1):
		path_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))
	# Out-of-range remainder, dimmed (shows where the army would continue later).
	if stop_i < path_cells.size() - 1:
		for i in range(stop_i, path_cells.size()):
			rest_line.add_point(base_map.to_local(_get_cell_center_global(path_cells[i])))

	if reachable_overlay != null:
		var stop: Vector2i = path_cells[stop_i]
		reachable_overlay.set_stop_cell(stop)
		# Target marker when distinct from this turn's stop tile.
		# Orange if interaction is possible this turn; gray if MP runs out short.
		if interact_cell != null and interact_cell != stop:
			reachable_overlay.set_interact_cell(
				interact_cell, _can_interact_this_turn(path_cells, stop_i)
			)


## True when this turn's move reaches the path end with enough MP to interact
## (land: need MP left after arriving on approach; fleet: reaching end is enough).
func _can_interact_this_turn(path_cells: Array[Vector2i], stop_i: int) -> bool:
	if path_cells.is_empty():
		return false
	# Already on the approach / in position — click interacts without moving.
	if path_cells.size() == 1:
		return true
	if stop_i < path_cells.size() - 1:
		return false
	var spent := 0
	for i in range(1, stop_i + 1):
		spent += enter_cost(path_cells[i], selected_army)
	var remaining: int = selected_army.movement_left - spent
	if _is_fleet(selected_army):
		return remaining >= 0
	# Land units need leftover MP after arriving to open the interact UI.
	return remaining > 0


func _confirm_move() -> bool:
	if selected_army == null:
		return false

	var mouse_cell := get_cell_at_mouse()
	var army_cell := get_army_cell(selected_army)

	# Fleet movement / embark / disembark.
	if _is_fleet(selected_army):
		return _confirm_fleet_move(selected_army, army_cell, mouse_cell)

	# Same tile as the selected army → open its menu (not a zero-length move).
	if mouse_cell == army_cell or occupancy.get(mouse_cell) == selected_army:
		base_map.open_selected_army_menu(selected_army)
		return true

	# Another army/caravan under the cursor: interact if adjacent, else approach.
	if occupancy.has(mouse_cell) and occupancy[mouse_cell] != selected_army:
		var target_unit: Node2D = occupancy[mouse_cell]
		if _cells_edge_adjacent(army_cell, mouse_cell):
			open_army_interaction(selected_army, target_unit)
			return true
		return confirm_move_to_army(target_unit)

	# If the cursor is on a garrisonable building, merchant, or field, prefer interaction.
	# When already adjacent the path is often length < 2, so handle that before
	# the empty-path early-out.
	var building_under_cursor = blocked_cell_to_object.get(mouse_cell, null)
	var click_target = building_under_cursor != null and (
		building_under_cursor.has_method("get_garrison_capacity")
		or (
			building_under_cursor.get("type_") != null
			and building_under_cursor.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT
			and not bool(building_under_cursor.get("camp_hidden"))
		)
		or (
			building_under_cursor.get("type_") != null
			and building_under_cursor.type_ == GlobalStuff.BUILDING_TYPE.FIELD
		)
	)
	if click_target:
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


func _confirm_fleet_move(fleet: Node2D, fleet_cell: Vector2i, mouse_cell: Vector2i) -> bool:
	# Same sea tile → fleet menu / stack picker.
	if mouse_cell == fleet_cell:
		base_map.open_selected_army_menu(fleet)
		return true

	# Adjacent walkable shore: land (empty / merge / attack).
	if walkable_cells.has(mouse_cell) and _cells_edge_adjacent(fleet_cell, mouse_cell):
		if occupancy.has(mouse_cell):
			var target: Node2D = occupancy[mouse_cell]
			if _is_caravan(target) or _is_fleet(target):
				pass
			else:
				deselect_army()
				base_map.open_fleet_disembark_prompt(fleet, mouse_cell)
				return true
		else:
			deselect_army()
			base_map.open_fleet_disembark_prompt(fleet, mouse_cell)
			return true

	# Adjacent own fleet on another sea tile → combine vs stack.
	if sea_cells.has(mouse_cell) and _cells_edge_adjacent(fleet_cell, mouse_cell):
		var others: Array = fleets_at_cell(mouse_cell)
		var own_other: Node2D = null
		for f in others:
			if f != fleet and _unit_controller(f) == _unit_controller(fleet):
				own_other = f
				break
		if own_other != null:
			deselect_army()
			base_map.open_fleet_combine_prompt(fleet, own_other, mouse_cell)
			return true

	# Sea path move.
	if current_path.size() == 1 and current_path[0] == fleet_cell:
		base_map.open_selected_army_menu(fleet)
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
	var path_cells := _best_path_to_cells(from_cell, get_approach_cells(building), selected_army)
	if path_cells.size() < 2:
		return false
	var interact = null
	var footprint: Array = object_to_footprint.get(building, [])
	if not footprint.is_empty():
		interact = footprint[0]
	_render_path_preview(path_cells, interact)
	return _execute_move_along_path(building, null)


# Move toward another army/caravan's approach cells. When arrival leaves MP,
# queues merge/attack/capture interaction (same pattern as garrison).
# Fleet→fleet: path onto the target's sea tile (stacking allowed).
func confirm_move_to_army(target: Node2D) -> bool:
	if selected_army == null or target == null:
		return false
	var from_cell := get_army_cell(selected_army)
	var target_cell := get_army_cell(target)
	var path_cells: Array[Vector2i]
	if _is_fleet(selected_army) and _is_fleet(target):
		path_cells = _find_path_cells(from_cell, target_cell, selected_army)
	else:
		path_cells = _best_path_to_cells(
			from_cell, _approach_cells_of_cell(target_cell, selected_army), selected_army
		)
	if path_cells.size() < 2:
		return false
	_render_path_preview(path_cells, target_cell)
	return _execute_move_along_path(null, target)


func _execute_move_along_path(garrison_building: Node, target_army: Node2D) -> bool:
	if selected_army == null or current_path.size() < 2:
		return false
	var stop_i: int = _farthest_affordable_index(current_path, selected_army.movement_left, selected_army)
	if stop_i <= 0:
		return false  # no movement points left this turn

	# Never end on an occupied tile (path should already avoid; clamp as safety).
	var army := selected_army
	while stop_i > 0:
		var candidate: Vector2i = current_path[stop_i]
		if _cell_blocked_for_stop(army, candidate):
			stop_i -= 1
			continue
		break
	if stop_i <= 0:
		return false

	var end_cell: Vector2i = current_path[stop_i]
	var spent_mp := 0
	for i in range(1, stop_i + 1):
		spent_mp += enter_cost(current_path[i], army)
	var army_name := String(army.name)
	var remaining_mp = army.movement_left - spent_mp
	var is_fleet_mover := _is_fleet(army)

	# Moving onto a building/merchant/field approach with MP left: open interaction UI.
	var can_garrison := garrison_building != null and garrison_building.has_method("get_garrison_capacity")
	if can_garrison and garrison_building.has_method("is_army_interactable") \
			and not garrison_building.is_army_interactable():
		can_garrison = false
	var pending_ok = garrison_building != null and (
		can_garrison
		or (
			garrison_building.get("type_") != null
			and garrison_building.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT
			and not bool(garrison_building.get("camp_hidden"))
		)
		or (
			garrison_building.get("type_") != null
			and garrison_building.type_ == GlobalStuff.BUILDING_TYPE.FIELD
		)
	)
	if not is_fleet_mover and pending_ok and end_cell in get_approach_cells(garrison_building) and remaining_mp > 0:
		base_map.set_pending_garrison(army_name, army.force_id, garrison_building)

	# Same for army/caravan targets: arrive on approach with MP left → interact UI.
	if not is_fleet_mover and target_army != null and remaining_mp > 0:
		var target_cell := get_army_cell(target_army)
		if _cells_edge_adjacent(end_cell, target_cell):
			base_map.set_pending_army_interaction(army_name, target_army)

	# Fleet arrives on a sea tile that already has own fleets → combine/stack prompt.
	if is_fleet_mover and remaining_mp >= 0:
		var others: Array = fleets_at_cell(end_cell)
		for f in others:
			if f != army and _unit_controller(f) == _unit_controller(army):
				base_map.set_pending_fleet_combine(army_name, f)
				break

	deselect_army()
	# Pathfinding and the building Area2D can both receive this click. After we
	# deselect, a second pass would open the empty building info card — block it.
	base_map.suppress_building_click_this_frame()
	if is_fleet_mover:
		base_map.request_fleet_move.rpc_id(1, army_name, end_cell.x, end_cell.y, spent_mp)
	else:
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
